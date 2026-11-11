#!/usr/bin/env python3
"""Build an isolated instrumented Lab from explicit sources; never runs it automatically."""
import argparse
import plistlib
import subprocess
from pathlib import Path

# 진단 링크는 native 빌드의 object 배치(PrivacyCore.build/*.o, PrivacyBackdrop.build)에 의존함. 기본 swiftbuild에는 이 산출물이 없음.
SWIFT_BUILD = ['swift', 'build', '--build-system', 'native']
# 앱 진입점과 Sparkle 연결부는 진단 앱에 넣지 않음.
APP_ONLY_SOURCES = {'PrivacyAirPodsApp.swift', 'SparkleUpdater.swift'}
ROOT = Path(__file__).resolve().parents[2]
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--lab-source', type=Path, required=True)
parser.add_argument('--cover-source', type=Path, required=True)
parser.add_argument('--output', type=Path, required=True)
args = parser.parse_args()
args.output.mkdir(parents=True, exist_ok=False)
lab = args.lab_source.read_text()
cover = args.cover_source.read_text()
# 비교용 과거 판본도 내장 화면에 고정하며 외장 작업의 포커스를 가져오지 않음.
lab = lab.replace('NSScreen.screens.count == 1', 'NSScreen.screens.contains(where: { CGDisplayIsBuiltin($0.displayID) != 0 })')
lab = lab.replace('guard let screen = NSScreen.screens.first else',
    'guard let screen = NSScreen.screens.first(where: { CGDisplayIsBuiltin($0.displayID) != 0 }) else')
show_start = lab.index('    @objc private func show()')
show_end = lab.index('    @objc private func quit()', show_start)
lab = lab[:show_start] + """    @objc private func show() {
        guard let screen = NSScreen.screens.first(where: { CGDisplayIsBuiltin($0.displayID) != 0 }) else { return }
        window.setFrameOrigin(NSPoint(x: screen.frame.minX + 100, y: screen.frame.minY + 120))
        window.orderFrontRegardless()
    }
""" + lab[show_end:]
assert lab.count('    private func update() {') == 1
lab = lab.replace('    private func update() {', '    private func update() {\n        benchmarkUpdates += 1')
lab = lab.replace('    private var window:', '    private var benchmarkUpdates = 0\n    private var window:', 1)
assert lab.count('        show()') == 1
lab = lab.replace('        show()', '        show()\n        if ProcessInfo.processInfo.arguments.contains("--benchmark") { runBenchmark() }', 1)
# Pre-counter historical sources still need a research-only submission count.
# Current product-backed and research covers already expose maskUpdateCount; do
# not instrument PBUpdateMask there because that misses ScreenCover submissions.
if 'maskUpdateCount' not in cover:
    marker = '    private var panels:'
    needle = '            guard PBUpdateMask(layer, image, setting.radius, &failure) else { throw failure! }'
    assert cover.count(marker) == 1
    assert cover.count(needle) == 1
    cover = cover.replace(marker, '    private(set) var maskUpdateCount = 0\n' + marker, 1)
    cover = cover.replace(needle, needle + '\n            maskUpdateCount += 1', 1)
lab += r'''

extension BlurLab {
    private func benchmarkUsage() -> rusage_info_v2 {
        var value = rusage_info_v2()
        let result = withUnsafeMutablePointer(to: &value) {
            $0.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) {
                proc_pid_rusage(getpid(), RUSAGE_INFO_V2, $0)
            }
        }
        precondition(result == 0, "process usage query failed")
        return value
    }
    private func benchmarkCPUSeconds() -> Double {
        var usage = rusage()
        precondition(getrusage(RUSAGE_SELF, &usage) == 0)
        return Double(usage.ru_utime.tv_sec + usage.ru_stime.tv_sec)
            + Double(usage.ru_utime.tv_usec + usage.ru_stime.tv_usec) / 1e6
    }
    private func runBenchmark() {
        Task { @MainActor in
            start()
            try? await Task.sleep(for: .milliseconds(500))
            guard cover != nil else {
                print("BENCH FAIL", status.stringValue); fflush(stdout); quit(); return
            }
            for mode in ["manual-idle", "sensor-static", "sensor-jitter", "sensor-sweep"] {
                let sensorInput = mode != "manual-idle"
                stop()
                sensor.state = sensorInput ? .on : .off
                reference = sensorInput ? 0 : nil
                if sensorInput {
                    let now = ProcessInfo.processInfo.systemUptime
                    motion.onSample?(HeadSample(timestamp: now, receivedAt: now, yaw: -45,
                        acceleration: .zero, gravity: SIMD3(0,0,-1), source: 0))
                }
                start()
                try? await Task.sleep(for: .milliseconds(300))
                precondition(cover != nil, "phase cover failed")
                let before = benchmarkUsage(), cpuBefore = benchmarkCPUSeconds(), started = ProcessInfo.processInfo.systemUptime
                let updates = benchmarkUpdates, maskUpdates = cover!.maskUpdateCount
                print("BENCH BEGIN", mode); fflush(stdout)
                if sensorInput {
                    for index in 0..<480 {
                        let now = ProcessInfo.processInfo.systemUptime
                        let amplitude = mode == "sensor-jitter" ? 0.000001 : mode == "sensor-sweep" ? 15.0 : 0
                        let yaw = -(45 + sin(Double(index) / 20) * amplitude)
                        motion.onSample?(HeadSample(timestamp: now, receivedAt: now, yaw: yaw,
                            acceleration: .zero, gravity: SIMD3(0,0,-1), source: 0))
                        try? await Task.sleep(for: .milliseconds(16))
                    }
                } else { try? await Task.sleep(for: .seconds(8)) }
                precondition(cover != nil, "benchmark cover unexpectedly stopped")
                let after = benchmarkUsage(), seconds = ProcessInfo.processInfo.systemUptime - started
                let cpu = benchmarkCPUSeconds() - cpuBefore
                print("BENCH RESULT", mode, "seconds", seconds, "cpuPercent", cpu / seconds * 100,
                    "interruptWakeups", after.ri_interrupt_wkups - before.ri_interrupt_wkups,
                    // Keep the historical `commits` field while sourcing it from the
                    // product/research cover's observed mask submission count.
                    "updates", benchmarkUpdates - updates, "commits", cover!.maskUpdateCount - maskUpdates,
                    "footprintBefore", before.ri_phys_footprint, "footprintAfter", after.ri_phys_footprint)
                fflush(stdout)
            }
            stop(); print("BENCH DONE"); fflush(stdout); quit()
        }
    }
}
'''
lab_path, cover_path = args.output/'BlurLab.swift', args.output/'PrivateCover.swift'
lab_path.write_text(lab)
cover_path.write_text(cover)
objc = args.output/'BackdropSPI.o'
subprocess.run([*SWIFT_BUILD, '--target', 'PrivacyCore'], cwd=ROOT, check=True)
subprocess.run([*SWIFT_BUILD, '--target', 'PrivacyBackdrop'], cwd=ROOT, check=True)
bin_path = Path(subprocess.check_output([*SWIFT_BUILD, '--show-bin-path'], cwd=ROOT, text=True).strip())
backdrop_build = bin_path/'PrivacyBackdrop.build'
backdrop_object = backdrop_build/'PrivacyBackdrop.m.o'
backdrop_modulemap = backdrop_build/'module.modulemap'
if not backdrop_object.exists() or not backdrop_modulemap.exists():
    raise SystemExit('Build PrivacyBackdrop with swift build first')
subprocess.run(['clang', '-fobjc-arc', '-fmodules', f'-fmodule-map-file={backdrop_modulemap}',
    '-I', str(ROOT/'Sources/PrivacyBackdrop/include'), '-c', str(ROOT/'scripts/diagnostics/BackdropSPI.m'), '-o', str(objc)], check=True)
# 삭제된 소스의 오래된 object가 링크되지 않도록 현재 소스에 대응하는 object만 사용함.
objects = [bin_path/'PrivacyCore.build'/f'{p.name}.o' for p in (ROOT/'Sources/PrivacyCore').glob('*.swift')]
assert objects and all(p.exists() for p in objects), 'build PrivacyCore first'
sources = [p for p in (ROOT/'Sources/PrivacyAirPods').glob('*.swift') if p.name not in APP_ONLY_SOURCES]
app = args.output/'Privacy Blur Benchmark.app'
binary = app/'Contents/MacOS/PrivacyBlurBenchmark'
binary.parent.mkdir(parents=True)
subprocess.run(['swiftc', '-parse-as-library', '-import-objc-header', str(ROOT/'scripts/diagnostics/BackdropSPI.h'),
    '-I', str(bin_path/'Modules'), '-I', str(backdrop_build), '-Xcc', f'-fmodule-map-file={backdrop_modulemap}',
    *map(str, sources), str(cover_path), str(lab_path), str(objc), str(backdrop_object), *map(str, objects),
    '-o', str(binary)], check=True)
info = plistlib.loads((ROOT/'Resources/Info.plist').read_bytes())
info.update(CFBundleExecutable='PrivacyBlurBenchmark', CFBundleIdentifier='local.privacy-with-airpod.benchmark',
    CFBundleName='Privacy Blur Benchmark', LSUIElement=True)
(app/'Contents/Info.plist').write_bytes(plistlib.dumps(info))
subprocess.run(['codesign', '--force', '--sign', (ROOT/'.build/signing-identity').read_text().strip(), str(app)], check=True)
subprocess.run(['codesign', '--verify', '--strict', str(app)], check=True)
print(app)
