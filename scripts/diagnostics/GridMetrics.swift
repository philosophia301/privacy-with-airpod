import Foundation

/// Bounded, screen-content-free measurements for a fixed 16 by 9 grid.
///
/// The input is a borrowed BGRA byte buffer. The helper never keeps a copy of
/// it. `energy` is the mean absolute difference between horizontally adjacent
/// sampled chroma values. Adjacent pairs that cross a cell edge are skipped.
/// `samples` counts the sampled pixels in each cell, including the first
/// sampled column which has no left neighbour.
struct GridMetrics: Equatable, Sendable {
    static let columns = 16
    static let rows = 9
    static let cellCount = columns * rows

    let energy: [Double]
    let regions: [UInt8]
    let samples: [Int]

    /// Measures a borrowed BGRA buffer. Sampling visits every fourth pixel in
    /// each direction, and classifies each sampled pixel in its own cell.
    /// Returns nil for malformed buffers so callers can report the bad frame.
    init?(bytes: UnsafeRawBufferPointer, width: Int, height: Int, rowBytes: Int) {
        guard width > 0, height > 0,
              width <= Int.max / Self.columns,
              height <= Int.max / Self.rows,
              rowBytes >= width * 4,
              height <= Int.max / rowBytes,
              bytes.count >= rowBytes * height else {
            return nil
        }

        var energySums = [Double](repeating: 0, count: Self.cellCount)
        var regions = [UInt8](repeating: 0, count: Self.cellCount)
        var samples = [Int](repeating: 0, count: Self.cellCount)
        var pairCounts = [Int](repeating: 0, count: Self.cellCount)

        guard let baseAddress = bytes.baseAddress else { return nil }
        let pixels = baseAddress.assumingMemoryBound(to: UInt8.self)

        for y in stride(from: 0, to: height, by: 4) {
            let row = pixels.advanced(by: y * rowBytes)
            let cellY = min(Self.rows - 1, y * Self.rows / height)

            for x in stride(from: 0, to: width, by: 4) {
                let cellX = min(Self.columns - 1, x * Self.columns / width)
                let index = cellY * Self.columns + cellX
                let offset = x * 4
                let chroma = Self.chroma(at: row, offset: offset)
                samples[index] += 1

                if chroma > 25 {
                    regions[index] |= 1
                } else if chroma < -25 {
                    regions[index] |= 2
                } else {
                    regions[index] |= 4
                }

                // The first sampled column has no left neighbour. The cell
                // check prevents an adjacent contrast from leaking across a
                // grid boundary.
                guard x > 0 else { continue }
                let previousCellX = min(Self.columns - 1, (x - 1) * Self.columns / width)
                guard previousCellX == cellX else { continue }
                let previous = Self.chroma(at: row, offset: offset - 4)
                energySums[index] += abs(chroma - previous)
                pairCounts[index] += 1
            }
        }

        self.energy = zip(energySums, pairCounts).map { sum, count in
            count == 0 ? 0 : sum / Double(count)
        }
        self.regions = regions
        self.samples = samples
    }

    init?(bytes: [UInt8], width: Int, height: Int, rowBytes: Int) {
        guard let result = bytes.withUnsafeBytes({ raw in
            GridMetrics(bytes: raw, width: width, height: height, rowBytes: rowBytes)
        }) else { return nil }
        self = result
    }

    static func measure(bytes: UnsafeRawBufferPointer, width: Int, height: Int, rowBytes: Int) -> GridMetrics? {
        GridMetrics(bytes: bytes, width: width, height: height, rowBytes: rowBytes)
    }

    static func measure(bytes: [UInt8], width: Int, height: Int, rowBytes: Int) -> GridMetrics? {
        GridMetrics(bytes: bytes, width: width, height: height, rowBytes: rowBytes)
    }

    private static func chroma(at row: UnsafePointer<UInt8>, offset: Int) -> Double {
        // CVPixelBuffer is configured as 32BGRA: B at 0, G at 1, R at 2.
        Double(row[offset + 1]) - (Double(row[offset]) + Double(row[offset + 2])) / 2
    }
}
