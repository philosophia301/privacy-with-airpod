import AppKit
import PrivacyBackdrop

/// 화면 픽셀을 재표시하지 않고 WindowServer의 현재 배경에 마스크만 적용함.
@MainActor
final class ScreenCover: NSObject {
    private var panels: [CGDirectDisplayID: NSPanel] = [:]
    private var space: PBIndependentSpace?
    private var outputFailed = false
    var outputWindows: [NSPanel] { Array(panels.values) }
    var maskUpdateCount: Int { panels.values.reduce(0) { $0 + (($1.contentView as? SpaceTransitionBackdrop)?.submissionCount ?? 0) } }
    var onFailure: ((String) -> Void)?

    func start(settings: [CGDirectDisplayID: RenderSettings]) async throws {
        stop()
        try Task.checkCancellation()
        guard !settings.isEmpty else { throw CoverError.noDisplays }
        // 일부 화면만 보호된 채 시작 성공을 알리지 않도록 전체 구성을 먼저 확인함.
        var screens: [CGDirectDisplayID: NSScreen] = [:]
        for id in settings.keys {
            guard let screen = NSScreen.screens.first(where: { $0.displayID == id }) else {
                throw CoverError.displayUnavailable
            }
            screens[id] = screen
        }
        do {
            space = try PBIndependentSpace(error: ())
            for (id, setting) in settings {
                try Task.checkCancellation()
                guard let screen = screens[id] else { throw CoverError.displayUnavailable }
                let panel = try makePanel(screen: screen, settings: setting)
                panels[id] = panel
                var failure: NSError?
                guard PBConfigureWindow(panel, &failure) else {
                    throw failure ?? SpaceTransitionBackdrop.OutputError.unavailable
                }
                panel.orderFrontRegardless()
                try space?.attach(panel)
            }
        } catch { stop(); throw error }
    }

    func update(_ settings: [CGDirectDisplayID: RenderSettings]) {
        guard !outputFailed else { return }
        do {
            for (id, panel) in panels {
                guard let setting = settings[id] else { throw CoverError.displayUnavailable }
                try (panel.contentView as? SpaceTransitionBackdrop)?.update(setting)
            }
        } catch {
            // 일부 화면만 갱신된 채 실패하면 모든 기존 창을 비상 가림으로 유지함.
            outputFailed = true
            for panel in panels.values { (panel.contentView as? SpaceTransitionBackdrop)?.coverForOutputFailure() }
            onFailure?(error.localizedDescription)
        }
    }

    func stop() {
        for panel in panels.values { panel.orderOut(nil); panel.close() }
        panels.removeAll()
        space?.close(); space = nil
        outputFailed = false
    }

    func makePanel(screen: NSScreen, settings: RenderSettings = .covered()) throws -> NSPanel {
        let frame = screen.frame
        let panel = NSPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isReleasedWhenClosed = false
        panel.isFloatingPanel = true
        panel.level = WindowLevels.cover
        panel.collectionBehavior = [.stationary, .ignoresCycle, .fullScreenNone]
        panel.animationBehavior = .none
        panel.hidesOnDeactivate = false
        panel.ignoresMouseEvents = true
        panel.hasShadow = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        let view = try SpaceTransitionBackdrop(frame: CGRect(origin: .zero, size: frame.size), settings: settings)
        view.wantsLayer = true
        view.layer?.contentsScale = screen.backingScaleFactor
        view.layer?.contentsGravity = .resize
        // 노치 좌우와 메뉴 막대도 덮음. 클릭은 통과하고 펼친 메뉴는 더 높은 레벨에 표시됨.
        panel.contentView = view
        return panel
    }

    enum CoverError: LocalizedError {
        case noDisplays, displayUnavailable
        var errorDescription: String? {
            switch self {
            case .noDisplays: "보호할 화면이 없습니다."
            case .displayUnavailable: "화면 구성이 달라졌습니다. 다시 기준을 맞춰 주세요."
            }
        }
    }
}

/// 가림 창과 설정 창의 상하 관계. 설정 창은 보호 중에도 가림 위에서 조작 가능해야 함.
enum WindowLevels {
    /// 메뉴 막대와 노치 좌우까지 덮되 펼친 메뉴(popUpMenu)보다는 낮음.
    static let cover = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.mainMenuWindow)) + 1)
    static let settingsAboveCover = NSWindow.Level(rawValue: cover.rawValue + 1)
}

extension NSScreen {
    var displayID: CGDirectDisplayID {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
    }
}
