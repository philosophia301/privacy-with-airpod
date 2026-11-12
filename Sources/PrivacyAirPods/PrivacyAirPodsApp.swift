import SwiftUI
import AppKit
import Combine

@main
enum Launch {
    static func main() {
        guard LaunchOptions.smokeTest else {
            PrivacyAirPodsApp.main()
            return
        }
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        Task { @MainActor in exit(await ProtectionSmokeTest.run() ? 0 : 1) }
        app.run()
    }
}

struct PrivacyAirPodsApp: App {
    @StateObject private var model: AppModel
    @StateObject private var updater = SparkleUpdater()
    @StateObject private var icon: MenuBarIconModel

    init() {
        let model = AppModel()
        // 앱 실행 시 AirPods 입력을 한 번 시작함. 테스트는 AppModel을 직접 만들어 이 경로를 거치지 않음.
        model.startMotion()
        _model = StateObject(wrappedValue: model)
        _icon = StateObject(wrappedValue: MenuBarIconModel(
            frames: MenuBarIconModel.bundledFrames,
            protection: model.$protected.eraseToAnyPublisher(),
            clock: SystemMenuBarIconClock(),
            reduceMotion: { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion },
            workspaceNotifications: NSWorkspace.shared.notificationCenter))
    }

    private var settingsScene: some Scene {
        Window("Privacy AirPods 설정", id: "settings") {
            SettingsView(model: model, update: updater.state)
                .background(WindowLevel(aboveCover: model.protected || model.startingProtection))
                .background(PreviewWindowLifecycle(model: model))
        }
        .defaultSize(width: 640, height: 820)
        .windowResizability(.contentMinSize)
    }

    var body: some Scene {
        settingsScene.defaultLaunchBehavior(.presented)
        MenuBarExtra {
            MenuContent(model: model, update: updater.state)
        } label: {
            MenuBarIconLabel(model: icon)
        }
    }
}

private struct MenuContent: View {
    @ObservedObject var model: AppModel
    let update: UpdateState
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Text(MenuBarVersionText.current)
        Divider()
        Text(model.captureStatus)
        Text(model.motionStatus)
        Divider()
        Button(model.protected || model.startingProtection ? "보호 끄기" : "회전 블러 켜기") { model.toggleProtection() }
            .disabled(!model.protected && !model.startingProtection && !model.canProtect)
        Button("설정 열기…") {
            openWindow(id: "settings")
            NSApp.activate(ignoringOtherApps: true)
        }
        Button("AirPods 다시 확인") { model.startMotion() }
        Divider()
        Button("업데이트 확인…") { update.checkForUpdates() }
        Button("종료") { model.quit() }
    }
}

/// 보호 중에도 설정 창을 가림 위에 두어 보호 끄기와 재보정을 조작할 수 있게 함.
struct WindowLevel: NSViewRepresentable {
    var aboveCover: Bool
    func makeNSView(context: Context) -> LevelView { LevelView() }
    func updateNSView(_ view: LevelView, context: Context) {
        view.aboveCover = aboveCover
        view.apply()
    }

    final class LevelView: NSView {
        var aboveCover = false

        // 첫 갱신 때는 아직 창이 없을 수 있으므로 창에 붙는 시점에도 적용함.
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            apply()
        }

        func apply() {
            guard let window else { return }
            let level = aboveCover ? WindowLevels.settingsAboveCover : .normal
            window.hidesOnDeactivate = false
            if window.level != level { window.level = level }
        }
    }
}

private struct PreviewWindowLifecycle: NSViewRepresentable {
    let model: AppModel

    func makeCoordinator() -> Coordinator { Coordinator(model: model) }

    func makeNSView(context: Context) -> LifecycleView {
        let view = LifecycleView()
        view.onWindowChanged = { window in context.coordinator.attach(window) }
        return view
    }

    func updateNSView(_ nsView: LifecycleView, context: Context) {
        context.coordinator.attach(nsView.window)
    }

    static func dismantleNSView(_ nsView: LifecycleView, coordinator: Coordinator) {
        coordinator.detach()
    }

    final class LifecycleView: NSView {
        var onWindowChanged: ((NSWindow?) -> Void)?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            onWindowChanged?(window)
        }
    }

    @MainActor
    final class Coordinator: NSObject {
        private let model: AppModel
        private weak var window: NSWindow?
        private var observers: [NSObjectProtocol] = []

        init(model: AppModel) { self.model = model }

        func attach(_ window: NSWindow?) {
            guard self.window !== window else {
                updateVisibility()
                return
            }
            detach()
            self.window = window
            guard let window else {
                model.setPreviewWindowVisible(false)
                return
            }
            if LaunchOptions.builtInOnly,
               let screen = NSScreen.screens.first(where: { CGDisplayIsBuiltin($0.displayID) != 0 }) {
                let area = screen.visibleFrame
                let size = window.frame.size
                window.setFrameOrigin(NSPoint(x: area.midX - size.width / 2, y: area.midY - size.height / 2))
            }
            let windowNotifications: [Notification.Name] = [
                NSWindow.didChangeOcclusionStateNotification,
                NSWindow.didMiniaturizeNotification,
                NSWindow.didDeminiaturizeNotification,
                NSWindow.didBecomeKeyNotification,
                NSWindow.didBecomeMainNotification,
                NSWindow.didExposeNotification,
                NSWindow.willCloseNotification
            ]
            for name in windowNotifications {
                observers.append(NotificationCenter.default.addObserver(forName: name, object: window, queue: .main) { [weak self] _ in
                    Task { @MainActor [weak self] in
                        guard let self else { return }
                        if name == NSWindow.willCloseNotification {
                            model.setPreviewWindowVisible(false)
                        } else {
                            self.updateVisibility()
                        }
                    }
                })
            }
            for name in [NSApplication.didHideNotification, NSApplication.didUnhideNotification] {
                observers.append(NotificationCenter.default.addObserver(forName: name, object: NSApp, queue: .main) { [weak self] _ in
                    Task { @MainActor [weak self] in self?.updateVisibility() }
                })
            }
            updateVisibility()
        }

        func detach() {
            for observer in observers { NotificationCenter.default.removeObserver(observer) }
            observers.removeAll()
            window = nil
            model.setPreviewWindowVisible(false)
        }

        private func updateVisibility() {
            let visible = window.map {
                $0.isVisible && !$0.isMiniaturized && !NSApp.isHidden && $0.occlusionState.contains(.visible)
            } ?? false
            model.setPreviewWindowVisible(visible)
        }
    }
}
