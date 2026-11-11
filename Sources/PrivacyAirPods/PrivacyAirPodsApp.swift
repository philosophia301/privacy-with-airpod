import SwiftUI
import AppKit

@main
struct PrivacyAirPodsApp: App {
    @StateObject private var model = AppModel()

    private var experimentScene: some Scene {
        Window("Privacy AirPods · 실험", id: "experiment") {
            ExperimentView(model: model)
                .background(WindowLevel(aboveCover: model.protected || model.startingProtection))
                .background(PreviewWindowLifecycle(model: model))
        }
        .defaultSize(width: 880, height: 760)
        .windowResizability(.contentMinSize)

    }

    var body: some Scene {
        experimentScene.defaultLaunchBehavior(.presented)
        MenuBarExtra("Privacy AirPods", systemImage: model.protected ? "eye.slash.fill" : "eye") {
            MenuContent(model: model)
        }
    }
}

private struct MenuContent: View {
    @ObservedObject var model: AppModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Text(model.captureStatus)
        Text(model.motionStatus)
        Divider()
        Button(model.protected || model.startingProtection ? "보호 끄기" : "회전 블러 켜기") { model.toggleProtection() }
            .disabled(!model.protected && !model.startingProtection && !model.canProtect)
        Button("기준 맞추기 · 설정 · 실험") {
            openWindow(id: "experiment")
            NSApp.activate(ignoringOtherApps: true)
        }
        Button("AirPods 입력 시작") { model.startMotion() }
        Divider()
        Button("종료") { model.quit() }
    }
}

private struct WindowLevel: NSViewRepresentable {
    var aboveCover: Bool
    func makeNSView(context: Context) -> NSView { NSView() }
    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            nsView.window?.hidesOnDeactivate = false
            nsView.window?.level = aboveCover
                ? NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.mainMenuWindow)) + 2)
                : .normal
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
            if CommandLine.arguments.contains("--built-in-only"),
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
