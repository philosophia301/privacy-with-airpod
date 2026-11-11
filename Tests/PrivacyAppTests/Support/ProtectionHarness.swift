import AppKit
import Testing
import PrivacyCore
@testable import PrivacyAirPods

/// AirPods 대역. 제품 판정 규칙은 갖지 않고 sample과 오류 전달만 함.
/// 실제 MotionService처럼 중지된 뒤의 sample은 전달하지 않음.
@MainActor
final class FakeHeadMotion: HeadMotionSource {
    var onSample: ((HeadSample) -> Void)?
    var onError: ((String) -> Void)?
    private(set) var running = false

    func start() { running = true }
    func stop() { running = false }

    func send(_ sample: HeadSample) {
        guard running else { return }
        onSample?(sample)
    }

    func fail(_ message: String) { onError?(message) }
}

/// 테스트가 직접 진행하는 시계. advance 한 번이 실제 앱의 갱신 주기 한 번에 해당함.
@MainActor
final class ManualClock: FrameClock {
    var now: TimeInterval = 1_000
    private var tick: (@MainActor @Sendable () -> Void)?
    var running: Bool { tick != nil }

    func start(_ tick: @escaping @MainActor @Sendable () -> Void) { self.tick = tick }
    func stop() { tick = nil }

    func advance(_ seconds: TimeInterval = 0.05) {
        now += seconds
        tick?()
    }
}

/// 실제 AppModel, ScreenCover, WindowServer 가림 창을 주 화면 하나에서 실행함.
/// 대역은 AirPods 입력, 시계, 시스템 알림뿐임.
@MainActor
final class ProtectionHarness {
    let motion = FakeHeadMotion()
    let clock = ManualClock()
    let notifications = NotificationCenter()
    let workspace = NotificationCenter()
    let display: DisplayCalibration
    let model: AppModel

    /// 화면 크기와 무관하게 결과가 정해지도록 40cm 폭 화면을 눈앞 60cm 정면에 둔 배치.
    /// 화면 양 끝은 시선 정면에서 약 ±18.4°임.
    var frontLayout: [DisplayPose] {
        [DisplayPose(id: display.id, width: 40, height: 25, x: 0, y: 0, z: 60, yawDegrees: 0)]
    }

    init() throws {
        let screen = try #require(NSScreen.screens.first)
        display = try #require(DisplayLayout.connected(builtInOnly: false).first { $0.id == screen.displayID })
        let only = display
        model = AppModel(motion: motion, clock: clock, connectedDisplays: { [only] },
                         notifications: notifications, workspaceNotifications: workspace)
    }

    /// 사용자 기준 오른쪽으로 degrees만큼 돌린 머리 방향의 sample 하나를 보냄.
    /// CoreMotion yaw는 위에서 볼 때 왼쪽 회전이 양수이므로 부호를 바꿔 보냄.
    func look(right degrees: Double, source: Int = 1, measuredAgo age: TimeInterval = 0) {
        motion.send(HeadSample(timestamp: clock.now - age, receivedAt: clock.now, yaw: -degrees,
                               acceleration: .zero, gravity: SIMD3(0, 0, -1), source: source))
    }

    /// 같은 방향을 유지하며 갱신 주기마다 sample을 받음. 2초면 기본 전환 시간(0.18초) 평활화가 수렴함.
    func hold(right degrees: Double, for seconds: TimeInterval = 2) {
        for _ in 0..<Int((seconds / 0.05).rounded()) {
            look(right: degrees)
            clock.advance()
        }
    }

    /// 입력 시작, 정면 보정, 배치 적용, 보호 시작까지 사용자가 거치는 순서를 그대로 실행함.
    /// 끝나면 한 주기가 지나 다음 sample이 새 측정 시각을 가짐.
    @discardableResult
    func protect(layout: [DisplayPose]? = nil) async throws -> NSPanel {
        model.startMotion()
        look(right: 0)
        model.calibrateDesk()
        #expect(model.applyLayout(layout ?? frontLayout))
        #expect(model.canProtect)
        await model.startProtection()
        #expect(model.protected)
        clock.advance()
        return try #require(model.protectionWindows.first)
    }

    /// 실제 가림 창이 WindowServer에 제출한 마스크의 알파(0 선명, 255 최대 블러). 위치는 왼쪽 0, 가운데 128, 오른쪽 255.
    func maskAlpha(_ panel: NSPanel) throws -> [UInt8] {
        let backdrop = try #require(panel.contentView as? SpaceTransitionBackdrop)
        let data = try #require(backdrop.maskImage.dataProvider?.data) as Data
        return [0, 128, 255].map { data[$0 * 4 + 3] }
    }
}
