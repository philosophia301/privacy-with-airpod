#!/usr/bin/env python3
"""Exercise the production grid extractor on synthetic BGRA, without screen access."""
from pathlib import Path
import subprocess
import tempfile
import unittest

HERE = Path(__file__).resolve().parent
SWIFT = r'''
import Foundation
@main struct Check {
 static func main() {
  let w = 160, h = 90, stride = 672
  func pixels(_ alternating: Bool, _ bottom: Bool = false) -> [UInt8] {
   var b = [UInt8](repeating: 0, count: stride * h)
   for y in 0..<h { for x in 0..<w {
    let p = y * stride + x * 4
    if bottom && y >= 80 { b[p] = 200; b[p+2] = 200 }
    else { b[p+1] = alternating && x % 2 != 0 ? 50 : 200 }
    b[p+3] = 255
   }}
   return b
  }
  let mode = CommandLine.arguments[1]
  switch mode {
  case "constant":
   let value = GridMetrics.measure(bytes: pixels(false), width:w,height:h,rowBytes:stride)!
   precondition(value.energy == [Double](repeating:0,count:144))
   precondition(value.regions == [UInt8](repeating:1,count:144))
   precondition(value.samples.allSatisfy { $0 > 0 })
  case "contrast":
   let value = GridMetrics.measure(bytes: pixels(true), width:w,height:h,rowBytes:stride)!
   precondition(value.energy.allSatisfy { $0 == 150 })
  case "bottom":
   let value = GridMetrics.measure(bytes: pixels(false,true), width:w,height:h,rowBytes:stride)!
   precondition(Array(value.regions.suffix(16)) == [UInt8](repeating:2,count:16))
   precondition(Array(value.regions.prefix(128)) == [UInt8](repeating:1,count:128))
  case "cellEdge":
   var b = pixels(false)
   for y in 0..<h { for x in 10..<w { if (x / 10) % 2 == 1 {
    let p = y*stride+x*4; b[p+1]=0; b[p]=200; b[p+2]=200
   }}}
   let value = GridMetrics.measure(bytes:b,width:w,height:h,rowBytes:stride)!
   precondition(value.energy.allSatisfy { $0 == 0 })
  case "padding":
   var b = pixels(false)
   for y in 0..<h { for x in w*4..<stride { b[y*stride+x] = 255 } }
   let a = GridMetrics.measure(bytes:pixels(false),width:w,height:h,rowBytes:stride)!
   let c = GridMetrics.measure(bytes:b,width:w,height:h,rowBytes:stride)!
   precondition(a == c)
  case "malformed":
   precondition(GridMetrics.measure(bytes:[],width:w,height:h,rowBytes:stride) == nil)
   precondition(GridMetrics.measure(bytes:pixels(false),width:w,height:h,rowBytes:1) == nil)
   precondition(GridMetrics.measure(bytes:[],width:0,height:1,rowBytes:4) == nil)
  default: fatalError("Unknown case")
  }
 }
}
'''


class GridMetricsTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.directory = tempfile.TemporaryDirectory()
        cls.addClassCleanup(cls.directory.cleanup)
        root = Path(cls.directory.name)
        source = root / "Check.swift"
        source.write_text(SWIFT)
        cls.binary = root / "check"
        subprocess.run(["swiftc", "-parse-as-library", str(HERE / "GridMetrics.swift"), str(source),
                        "-o", str(cls.binary)], check=True, capture_output=True, text=True)

    def check_case(self, name):
        result = subprocess.run([str(self.binary), name], capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_constant_all_cells_are_observed(self): self.check_case("constant")
    def test_independent_adjacent_contrast(self): self.check_case("contrast")
    def test_bottom_row_is_measured(self): self.check_case("bottom")
    def test_grid_boundaries_do_not_create_false_contrast(self): self.check_case("cellEdge")
    def test_row_padding_is_not_interpreted_as_pixels(self): self.check_case("padding")
    def test_malformed_buffers_are_rejected(self): self.check_case("malformed")


if __name__ == "__main__":
    unittest.main()
