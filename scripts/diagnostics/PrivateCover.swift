import AppKit

@MainActor final class PrivateCover {
    private var panels: [NSPanel] = []
    private var productCover: ScreenCover?
    private var productFailure: String?
    private var rebased: [(NSPanel, Double)] = []
    private var masks: [(CALayer, CGRect, Double, CGDirectDisplayID, Bool)] = []
    private var submittedMasks: [ObjectIdentifier: (Data, Double)] = [:]
    private var researchMaskUpdateCount = 0
    var maskUpdateCount: Int { productCover?.maskUpdateCount ?? researchMaskUpdateCount }
    private var latest: [CGDirectDisplayID: RenderSettings] = [:]
    private var compensated: [(NSPanel, CALayer, Double)] = []
    private var diagnosticBackdrops: [CALayer] = []
    func start(settings: [CGDirectDisplayID: RenderSettings], host: Bool, independent: Bool = false, swipeBits: UInt32 = 0, unflattened: Bool = false, stationary: Bool = true, native: Bool = false, nativeBaseline: Bool = false, windowBlur: Bool = false, level: Int = 25, joining: Int = 0, overscan: Bool = false, overscanScreens: Double = 1, tiled: Bool = false, broadTiles: Bool = false, immovable: Bool = false, pinnedMesh: Bool = false, rebase: Bool = false, marker: Bool = false, partial: Bool = false, compensate: Bool = false, periodic: Bool = false) async throws {
        guard panels.isEmpty, productCover == nil else {
            throw NSError(domain: "PrivacyBlurLab", code: 1, userInfo: [NSLocalizedDescriptionKey: "Cover is already running"])
        }
        do {
            if independent {
                let cover = ScreenCover()
                cover.onFailure = { [weak self] message in self?.productFailure = message }
                productCover = cover
                try await cover.start(settings: settings)
                return
            }
            for screen in NSScreen.screens {
                guard let setting = settings[screen.displayID] else { continue }
                let frames = independent ? [screen.frame] : broadTiles ? (-1...1).map { screen.frame.insetBy(dx: -screen.frame.width, dy: 0).offsetBy(dx: Double($0) * screen.frame.width * 3, dy: 0) }
                    : tiled ? (-4...4).map { screen.frame.offsetBy(dx: Double($0) * screen.frame.width, dy: 0) }
                    : [overscan ? screen.frame.insetBy(dx: -screen.frame.width * overscanScreens, dy: 0) : screen.frame]
                for panelFrame in frames {
                let panel = NSPanel(contentRect: panelFrame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
                panel.isReleasedWhenClosed = false
                if immovable { panel.isMovable = false }
                panel.animationBehavior = .none
                panel.isFloatingPanel = true
                panel.level = NSWindow.Level(rawValue: level)
                panel.isOpaque = false; panel.backgroundColor = .clear
                panel.hasShadow = false; panel.ignoresMouseEvents = true
                panel.hidesOnDeactivate = false
                panel.collectionBehavior = [.canJoinAllSpaces, .canJoinAllApplications, .fullScreenAuxiliary, .stationary, .ignoresCycle]
                if independent { panel.collectionBehavior = [.stationary, .ignoresCycle, .fullScreenNone] }
                if joining >= 1 { panel.collectionBehavior.remove(.canJoinAllApplications) }
                if joining >= 2 { panel.collectionBehavior.remove(.fullScreenAuxiliary) }
                if !stationary { panel.collectionBehavior.remove(.stationary) }
                panels.append(panel)
                if rebase && !independent { rebased.append((panel, screen.frame.width)) }
                let frame = CGRect(origin: .zero, size: panelFrame.size)
                let view: NSView = native ? NSVisualEffectView(frame: frame) : unflattened ? PBUnflattenedView(frame) : NSView(frame: frame)
                if let effect = view as? NSVisualEffectView {
                    effect.blendingMode = .behindWindow; effect.state = .active; effect.material = .hudWindow
                }
                view.wantsLayer = true
                panel.contentView = view
                let period = screen.frame.width + 64 // 현재 OS 실측 pitch. 다른 환경 검증 전임.
                let repeating = periodic && !independent
                let blurFrame = repeating ? frame.insetBy(dx: -period, dy: 0) : frame
                let maskData = makeMaskData(frame: blurFrame, width: screen.frame.width, periodic: repeating, partial: partial, setting: setting)
                let mask = makeMaskImage(maskData)
                var failure: NSError?
                if !native && !windowBlur {
                guard let backdrop = PBDiagnosticBackdrop(true, setting.radius, mask, &failure) else { throw failure! }
                backdrop.frame = blurFrame
                view.layer?.addSublayer(backdrop)
                diagnosticBackdrops.append(backdrop)
                if periodic || independent {
                    masks.append((backdrop, blurFrame, screen.frame.width, screen.displayID, repeating))
                    submittedMasks[ObjectIdentifier(backdrop)] = (maskData, setting.radius)
                }
                if compensate && !independent { compensated.append((panel, backdrop, repeating ? period : 0)) }
                }
                if marker {
                    let line = CALayer(); line.backgroundColor = NSColor.blue.cgColor
                    line.frame = CGRect(x: frame.width / 2 - 3, y: 0, width: 6, height: frame.height)
                    view.layer?.addSublayer(line)
                }
                if host && !native && !windowBlur {
                    var failure: NSError?
                    guard PBConfigureWindow(panel, &failure) else { throw failure! }
                }
                panel.orderFrontRegardless()
                if pinnedMesh { guard PBPinDiagnosticWindowMesh(panel, &failure) else { throw failure! } }
                if windowBlur {
                    guard PBWindowBlur(panel, Int(setting.radius.rounded()), &failure) else { throw failure! }
                }
                if native && !nativeBaseline {
                    panel.displayIfNeeded()
                    // AppKit material 하위 레이어 생성 뒤 시험 필터를 설치함. 전환 중 지연이 아님.
                    try await Task.sleep(for: .milliseconds(150))
                    guard PBTuneNative(view, setting.radius, mask, &failure) else { throw failure! }
                }
                if swipeBits != 0 {
                    panel.displayIfNeeded()
                    guard PBSwipeTag(panel, swipeBits, &failure) else { throw failure! }
                }
                print("PANEL", panel.windowNumber, panel.isVisible, panel.frame)
                }
            }
            guard !panels.isEmpty else {
                throw NSError(domain: "PrivacyBlurLab", code: 2, userInfo: [NSLocalizedDescriptionKey: "No matching display for cover"])
            }
        } catch { stop(); throw error }
    }
    func compensate() throws {
        for (panel, width) in rebased {
            var failure: NSError?
            guard PBRebaseDiagnosticWindow(panel, width, width + 64, &failure) else { throw failure! }
        }
        for (panel, layer, period) in compensated {
            var failure: NSError?
            guard PBPositionBackdrop(panel, layer, period, &failure) else { throw failure! }
        }
    }
    func trace() throws {
        try compensate()
        for panel in productCover?.outputWindows ?? panels {
            var failure: NSError?
            guard PBTraceWindow(panel, &failure) else { throw failure! }
        }
    }
    private func makeMaskData(frame: CGRect, width: Double, periodic: Bool, partial: Bool, setting: RenderSettings) -> Data {
        let period = width + 64
        let maskWidth = periodic ? 1536 : 256
        var bytes = [UInt8](repeating: 255, count: maskWidth * 4)
        for x in 0..<maskWidth {
            var position = Double(x) / Double(maskWidth-1) * frame.width + frame.minX - width
            if periodic { position = ((position+32).truncatingRemainder(dividingBy:period)+period).truncatingRemainder(dividingBy:period)-32 }
            let visibleX = position / width
            let strength = partial ? max(0, min(1, (visibleX - 0.3) / 0.4)) : setting.strength(at: periodic ? max(0, min(1, visibleX)) : Double(x) / Double(maskWidth-1))
            bytes[x * 4 + 3] = UInt8((strength * 255).rounded())
        }
        return Data(bytes)
    }
    private func makeMaskImage(_ data: Data) -> CGImage {
        let maskWidth = data.count / 4
        return CGImage(width: maskWidth, height: 1, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: maskWidth * 4,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue),
            provider: CGDataProvider(data: data as CFData)!, decode: nil, shouldInterpolate: true, intent: .defaultIntent)!
    }
    func update(settings: [CGDirectDisplayID: RenderSettings]) throws {
        if let productCover {
            productCover.update(settings)
            if let productFailure {
                throw NSError(domain: "PrivacyBlurLab", code: 3, userInfo: [NSLocalizedDescriptionKey: productFailure])
            }
            return
        }
        for (layer, frame, width, displayID, repeating) in masks {
            guard let setting = settings[displayID], latest[displayID] != setting else { continue }
            let data = makeMaskData(frame: frame, width: width, periodic: repeating, partial: false, setting: setting)
            let key = ObjectIdentifier(layer)
            // 각도를 근사하지 않음. 실제 제출할 픽셀과 반경이 모두 같을 때만 생략함.
            if let previous = submittedMasks[key], previous.0 == data, previous.1 == setting.radius { continue }
            let image = makeMaskImage(data)
            var failure: NSError?
            guard PBUpdateMask(layer, image, setting.radius, &failure) else { throw failure! }
            submittedMasks[key] = (data, setting.radius)
            researchMaskUpdateCount += 1
        }
        latest = settings
    }
    func stop() {
        for panel in panels { panel.orderOut(nil); panel.close() }
        productCover?.stop(); productCover = nil; productFailure = nil
        submittedMasks.removeAll(); researchMaskUpdateCount = 0
        panels.removeAll(); rebased.removeAll(); compensated.removeAll(); masks.removeAll(); latest.removeAll(); diagnosticBackdrops.removeAll()
    }
    /// 검출기 양성 대조군 전용. 표면을 재생성하지 않고 의도적인 노출을 만듦.
    func setDiagnosticHidden(_ hidden: Bool) {
        CATransaction.begin(); CATransaction.setDisableActions(true)
        for panel in productCover?.outputWindows ?? [] { panel.contentView?.layer?.opacity = hidden ? 0 : 1 }
        for layer in diagnosticBackdrops { layer.opacity = hidden ? 0 : 1 }
        CATransaction.commit()
    }
}
