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

/// 걷기 활동 대역. 실제 CMHeadphoneActivityManager는 시작하지 않고, 시작된 동안에만 활동을 전달함.
@MainActor
final class FakeHeadActivity: HeadActivitySource {
    var onActivity: ((HeadActivity) -> Void)?
    private(set) var running = false

    func start() { running = true }
    func stop() { running = false }

    func send(_ activity: HeadActivity) {
        guard running else { return }
        onActivity?(activity)
    }

    /// 멈추기 전에 이미 대기 중이던 callback이 늦게 도착한 경우. 모델의 가드만으로 걸러지는지 볼 때 씀.
    func sendLate(_ activity: HeadActivity) {
        onActivity?(activity)
    }
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

/// 연결된 화면 목록. AppModel 대역과 공유해 테스트가 꽂기·뽑기 상태를 바꿀 수 있게 함.
@MainActor
final class ScreenList {
    var displays: [DisplayCalibration]

    init(_ displays: [DisplayCalibration]) {
        self.displays = displays
    }
}

/// 실제 AppModel, ScreenCover, WindowServer 가림 창을 주 화면 하나에서 실행함.
/// 대역은 AirPods 입력, AirPods 걷기 활동, 시계, 시스템 알림, 화면 목록, 테스트 전용 기억 suite뿐임.
/// 기억 suite는 하네스마다 따로 만들고 tearDown에서 지워 다른 테스트나 UserDefaults.standard와 섞이지 않게 함.
@MainActor
final class ProtectionHarness {
    let motion = FakeHeadMotion()
    let activity = FakeHeadActivity()
    let clock = ManualClock()
    let screens: ScreenList
    let display: DisplayCalibration
    let defaults: UserDefaults
    let memory: SettingsMemory
    private let suiteName: String
    private(set) var notifications = NotificationCenter()
    private(set) var workspace = NotificationCenter()
    private(set) var model: AppModel

    /// 화면 크기와 무관하게 결과가 정해지도록 40cm 폭 화면을 눈앞 60cm 정면에 둔 배치.
    /// 화면 양 끝은 시선 정면에서 약 ±18.4°임.
    var frontLayout: [DisplayPose] {
        [DisplayPose(id: display.id, width: 40, height: 25, x: 0, y: 0, z: 60, yawDegrees: 0)]
    }

    init() throws {
        let screen = try #require(NSScreen.screens.first)
        let real = try #require(DisplayLayout.connected(builtInOnly: false).first { $0.id == screen.displayID })
        // 기억 흐름은 실제 화면의 UUID에 기대므로 비어 있으면 그 결과부터 틀린 것임.
        #expect(!real.uuid.isEmpty)
        display = real
        suiteName = "PrivacyAppTests.settings.\(UUID().uuidString)"
        defaults = try #require(UserDefaults(suiteName: suiteName))
        memory = SettingsMemory(defaults: defaults)
        screens = ScreenList([real])
        model = Self.makeModel(motion: motion, clock: clock, screens: screens, activity: activity,
                               notifications: notifications, workspace: workspace, memory: memory)
    }

    /// 같은 기억 저장소와 화면 목록으로 앱을 다시 연 것처럼 새 AppModel을 만듦.
    /// 이전 모델은 보호와 입력을 멈추고, 새 알림 중심을 써서 이전 모델이 다음 알림에 반응하지 않게 함.
    /// displays를 주면 다시 열기 전에 화면 목록을 그 값으로 바꿈. 재부팅 뒤 화면 ID가 바뀌는 상황을 모사함.
    @discardableResult
    func relaunch(with displays: [DisplayCalibration]? = nil) -> AppModel {
        model.stopProtection()
        motion.stop()
        if let displays { screens.displays = displays }
        notifications = NotificationCenter()
        workspace = NotificationCenter()
        model = Self.makeModel(motion: motion, clock: clock, screens: screens, activity: activity,
                               notifications: notifications, workspace: workspace, memory: memory)
        return model
    }

    /// 화면 목록을 바꾸고 시스템이 보내는 화면 구성 변경 알림을 보냄.
    func setScreens(_ displays: [DisplayCalibration]) {
        screens.displays = displays
        notifications.post(name: NSApplication.didChangeScreenParametersNotification, object: nil)
    }

    /// 실제 화면이 아니라 연결 상태만 흉내 낸 화면. 기억과 배치 대응을 검사할 때만 씀.
    /// 이 화면으로는 보호를 시작하지 않음. ScreenCover는 실제 화면이 필요함.
    static func screen(id: CGDirectDisplayID, uuid: String,
                       frame: CGRect = CGRect(x: 0, y: 0, width: 1920, height: 1080)) -> DisplayCalibration {
        DisplayCalibration(id: id, name: "테스트 화면", frame: frame, widthCM: 40, heightCM: 25, uuid: uuid)
    }

    /// 보호를 끄고 테스트 전용 기억 suite를 지움. 각 테스트가 끝날 때 한 번 호출함.
    func tearDown() {
        model.stopProtection()
        defaults.removePersistentDomain(forName: suiteName)
    }

    /// 사용자 기준 오른쪽으로 degrees만큼 돌린 머리 방향의 sample 하나를 보냄.
    /// CoreMotion yaw는 위에서 볼 때 왼쪽 회전이 양수이므로 부호를 바꿔 보냄.
    func look(right degrees: Double, source: Int = 1, measuredAgo age: TimeInterval = 0) {
        motion.send(HeadSample(timestamp: clock.now - age, receivedAt: clock.now, yaw: -degrees,
                               acceleration: .zero, gravity: SIMD3(0, 0, -1), source: source))
    }

    /// 정면을 보는 채 머리 높이를 meters만큼 seconds 동안 바꾸는 동작을 갱신 주기마다 보냄. 음수면 내려감.
    /// 높이 h(1-cos(πt/T))/2의 2차 미분을 사용자 가속도로 보내, 적분한 높이 변화가 실제 경로와 같게 함.
    /// step은 갱신 주기마다 sample을 보내고 시계를 진행한 뒤 호출됨. 주기마다 상태를 기록할 때 씀.
    func rise(by meters: Double, over seconds: Double, after step: (() -> Void)? = nil) {
        let omega = Double.pi / seconds
        for index in 0...Int((seconds / 0.05).rounded()) {
            let t = Double(index) * 0.05
            let upward = 0.5 * meters * omega * omega * cos(omega * t)
            motion.send(HeadSample(timestamp: clock.now, receivedAt: clock.now, yaw: 0,
                                   // Core Motion 관례대로 위로 가속하면 사용자 가속도가 중력과 같은 쪽을 가리킴.
                                   acceleration: SIMD3(0, 0, -upward / 9.80665), gravity: SIMD3(0, 0, -1),
                                   source: 1))
            clock.advance()
            step?()
        }
    }

    /// 걷기 동작을 갱신 주기마다 보냄. 한 걸음은 0.5초이고, 걸음의 4·5번째 sample이 위로 +5m/s²를 보내며
    /// 나머지 여덟 sample은 -1.25m/s²를 보냄. 한 걸음의 평균이 0이라 높이가 남지 않음.
    func walk(for seconds: TimeInterval) {
        for index in 0..<Int((seconds / 0.05).rounded()) {
            let heelStrike = index % 10 == 4 || index % 10 == 5
            let upward = heelStrike ? 5.0 : -1.25
            motion.send(HeadSample(timestamp: clock.now, receivedAt: clock.now, yaw: 0,
                                   acceleration: SIMD3(0, 0, -upward / 9.80665), gravity: SIMD3(0, 0, -1),
                                   source: 1))
            clock.advance()
        }
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

    private static func makeModel(motion: FakeHeadMotion, clock: ManualClock, screens: ScreenList,
                                  activity: FakeHeadActivity,
                                  notifications: NotificationCenter, workspace: NotificationCenter,
                                  memory: SettingsMemory) -> AppModel {
        AppModel(motion: motion, clock: clock, connectedDisplays: { [screens] in screens.displays },
                 notifications: notifications, workspaceNotifications: workspace,
                 activity: activity, memory: memory)
    }
}
