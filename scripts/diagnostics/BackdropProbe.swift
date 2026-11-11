import AppKit
import ScreenCaptureKit
import CoreImage

@MainActor final class Pattern: NSView {
    override func draw(_ rect: NSRect) {
        for x in stride(from: 0, to: Int(bounds.width), by: 8) {
            (x / 8 % 2 == 0 ? NSColor(calibratedRed: 0.2, green: 0.6, blue: 0.9, alpha: 1) : NSColor(calibratedRed: 0.9, green: 0.3, blue: 0.2, alpha: 1)).setFill()
            CGRect(x: x, y: 0, width: 8, height: Int(bounds.height)).fill()
        }
    }
}

@MainActor final class ProbeDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        Task { @MainActor in
            do { try await Probe.run() } catch { print("FAIL", error) }
            fflush(stdout); NSApp.terminate(nil)
        }
    }
}

@main struct Probe {
    @MainActor static func main() {
        let app = NSApplication.shared
        let delegate = ProbeDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.regular)
        withExtendedLifetime(delegate) { app.run() }
    }

    @MainActor static func run() async throws {
        let screen = NSScreen.screens[0]
        let frame = CGRect(x: screen.frame.minX + 200, y: screen.frame.minY + 200, width: 800, height: 400)
        let pattern = NSWindow(contentRect: frame, styleMask: .borderless, backing: .buffered, defer: false)
        pattern.isReleasedWhenClosed = false
        pattern.level = NSWindow.Level(rawValue: 28)
        pattern.collectionBehavior = [.canJoinAllSpaces, .canJoinAllApplications, .fullScreenAuxiliary, .stationary]
        pattern.contentView = Pattern(frame: CGRect(origin: .zero, size: frame.size))
        pattern.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        pattern.orderFrontRegardless()
        defer { pattern.close() }
        let panel = NSPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isReleasedWhenClosed = false
        panel.isFloatingPanel = true
        panel.level = NSWindow.Level(rawValue: 29)
        panel.isOpaque = false; panel.backgroundColor = .clear
        panel.hasShadow = false; panel.ignoresMouseEvents = true
        panel.collectionBehavior = pattern.collectionBehavior
        panel.contentView = NSView(frame: CGRect(origin: .zero, size: frame.size))
        panel.contentView!.wantsLayer = true
        defer { panel.close() }
        let root = panel.contentView!.layer!
        var maskBytes = [UInt8](repeating: 255, count: 256 * 4)
        for x in 0..<256 { maskBytes[x * 4 + 3] = UInt8(x) }
        let mask = CGImage(width: 256, height: 1, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: 256 * 4,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue),
            provider: CGDataProvider(data: Data(maskBytes) as CFData)!, decode: nil, shouldInterpolate: true, intent: .defaultIntent)!
        pattern.displayIfNeeded()
        print("FRAME", screen.frame, pattern.frame, pattern.windowNumber, pattern.isVisible)
        try await Task.sleep(for: .seconds(2))
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
        let display = content.displays.first { $0.displayID == (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as! NSNumber).uint32Value }!
        let candidate = content.windows.first { $0.windowID == CGWindowID(pattern.windowNumber) }
        print("CAPTURE WINDOW", candidate?.frame as Any, candidate?.isOnScreen as Any)
        guard candidate?.isOnScreen == true else { throw NSError(domain: "FixtureNotOnScreen", code: 1) }
        let filter = SCContentFilter(display: display, excludingWindows: [])
        filter.includeMenuBar = true
        let cfg = SCStreamConfiguration()
        cfg.sourceRect = CGRect(x: 200, y: screen.frame.height - 600, width: 800, height: 400)
        cfg.width = 800; cfg.height = 400; cfg.preservesAspectRatio = false; cfg.showsCursor = false
        let context = CIContext(options: [.cacheIntermediates: false])
        func measure(_ label: String) async throws {
            let cg = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: cfg)
            var pixels = [UInt8](repeating: 0, count: 800 * 400 * 4)
            context.render(CIImage(cgImage: cg), toBitmap: &pixels, rowBytes: 3200,
                bounds: CGRect(x: 0, y: 0, width: 800, height: 400), format: .RGBA8, colorSpace: CGColorSpaceCreateDeviceRGB())
            let summaries = [40, 200, 390, 570, 720].map { start -> String in
                let values = (start..<start + 40).map { Double(pixels[(200 * 800 + $0) * 4]) }
                let mean = values.reduce(0, +) / Double(values.count)
                let deviation = sqrt(values.map { pow($0 - mean, 2) }.reduce(0, +) / Double(values.count))
                return String(format: "%.2f:%.2f", mean, deviation)
            }
            print("RESULT", label, summaries.joined(separator: " ")); fflush(stdout)
        }
        try await measure("raw")
        for host in [false, true] {
            var failure: NSError?
            if host, !PBConfigureWindow(panel, &failure) { throw failure! }
            for variable in [false, true] {
                guard let backdrop = PBDiagnosticBackdrop(variable, 24, mask, &failure) else { throw failure! }
                backdrop.frame = root.bounds
                CATransaction.begin(); CATransaction.setDisableActions(true)
                root.sublayers = [backdrop]
                CATransaction.commit()
                panel.orderFrontRegardless()
                try await Task.sleep(for: .milliseconds(600))
                try await measure("host=\(host) variable=\(variable)")
            }
        }
        print("DONE")
    }
}
