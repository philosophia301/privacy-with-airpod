import AppKit
import Combine
import PrivacyCore
import CoreImage

/// 보정, 배치, 실제 보호, 입력 중단 정책을 소유함. 화면 표시 상태는 흐름 함수로만 바뀜.
@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var displays: [DisplayCalibration] = []
    @Published var selectedDisplay: CGDirectDisplayID = 0
    @Published private(set) var motionStatus = "AirPods 연결 확인 전"
    @Published private(set) var captureStatus = "보호 꺼짐"
    @Published private(set) var sample: HeadSample?
    @Published private(set) var sampleCount = 0
    @Published private(set) var receiving = false
    @Published private(set) var protected = false
    @Published private(set) var startingProtection = false
    @Published private(set) var suspended = false
    @Published var retainBlurOnInputLoss = false {
        didSet {
            if !retainBlurOnInputLoss && retainingForInputLoss {
                releaseForInputLoss()
            }
        }
    }
    @Published var demo = true
    @Published var demoAngle = 0.0
    @Published var direction = -1.0
    @Published var maximumBlur = 31.25
    @Published var responseTime = 0.18
    @Published var connectionWidth = 25.0
    @Published var startAngle = 35.0
    @Published private(set) var deskReference: Double?
    @Published private(set) var appliedPoses: [DisplayPose] = []
    @Published private(set) var previewImage: CGImage?
    @Published private(set) var probe = InertialProbe()
    @Published private(set) var probing = false
    @Published var trialLabel = "앉은 채 정지"

    private let motion: HeadMotionSource
    private let clock: FrameClock
    private let connectedDisplays: @MainActor () -> [DisplayCalibration]
    private let cover = ScreenCover()
    private let previewRenderer = PreviewRenderer()
    private let exampleImage = ExampleScreen.make()
    private var appliedLayout: CompiledLayout?
    private var ticking = false
    private var filteredYaw: Double?
    private var lastTick: TimeInterval
    private var probeStartedAt: TimeInterval?
    private var request = 0
    private var retainingForInputLoss = false
    private var previewWindowVisible = false

    private var shouldTick: Bool {
        previewWindowVisible || receiving || protected || startingProtection || probing
    }

    /// 실제 앱 구성: AirPods, 시스템 시계, 연결된 화면, 시스템 알림.
    convenience init() {
        self.init(motion: MotionService(), clock: SystemFrameClock(),
                  connectedDisplays: { DisplayLayout.connected() },
                  notifications: .default, workspaceNotifications: NSWorkspace.shared.notificationCenter)
    }

    /// 테스트는 입력, 시계, 화면 목록, 알림 경계만 대역으로 바꾸고 나머지 보호 경로는 실제로 실행함.
    init(motion: HeadMotionSource, clock: FrameClock,
         connectedDisplays: @escaping @MainActor () -> [DisplayCalibration],
         notifications: NotificationCenter, workspaceNotifications: NotificationCenter) {
        self.motion = motion
        self.clock = clock
        self.connectedDisplays = connectedDisplays
        lastTick = clock.now
        previewRenderer.onFrame = { [weak self] frame in self?.previewImage = frame.image }
        previewRenderer.onFailure = { [weak self] in self?.previewImage = nil }
        refreshDisplays()
        motion.onSample = { [weak self] value in self?.receive(value) }
        motion.onError = { [weak self] error in self?.invalidateMotion(error) }
        cover.onFailure = { [weak self] error in
            guard let self else { return }
            self.retainingForInputLoss = false
            self.suspended = true
            self.captureStatus = "화면 처리 중단: \(error) — 보호 끄기 후 다시 시도"
            self.updateCovers()
        }
        notifications.addObserver(self, selector: #selector(screenChanged),
                                  name: NSApplication.didChangeScreenParametersNotification, object: nil)
        workspaceNotifications.addObserver(self, selector: #selector(willSleep),
                                           name: NSWorkspace.willSleepNotification, object: nil)
    }

    var protectionWindows: [NSPanel] { cover.outputWindows }

    var fresh: Bool {
        guard let sample else { return false }
        return receiving && sample.isFresh(at: clock.now)
    }

    var canProtect: Bool {
        fresh && deskReference != nil && appliedLayout != nil && !startingProtection
    }

    var currentAngle: Double {
        guard let sample, let deskReference else { return 0 }
        return BlurProfile.relativeDegrees(current: sample.yaw, reference: deskReference) * direction
    }

    func startMotion() {
        invalidateMotion("AirPods 동작 입력을 기다리는 중")
        motion.start()
    }

    func stopMotion() {
        motion.stop()
        invalidateMotion("AirPods 입력 중지됨")
    }

    func calibrateDesk() {
        guard fresh, let sample, !protected, !startingProtection else { return }
        deskReference = sample.yaw
        filteredYaw = sample.yaw
        demo = false
    }

    func startProbe() {
        guard fresh else { return }
        probe.reset()
        probeStartedAt = clock.now
        probing = true
        reconcileTicking()
    }

    func stopProbe() {
        probing = false
        reconcileTicking()
    }

    func toggleProtection() {
        if protected || startingProtection {
            stopProtection()
        } else {
            Task { await startProtection() }
        }
    }

    /// 보정과 배치가 끝난 상태에서 모든 화면의 가림 창을 엶. 일부 화면만 보호된 채 성공을 알리지 않음.
    func startProtection() async {
        guard !protected, !startingProtection else { return }
        guard canProtect else { captureStatus = "AirPods 입력·화면 폭·정면 보정을 확인해 주세요"; return }
        request += 1
        let attempt = request
        startingProtection = true
        captureStatus = "화면 블러 준비 중"
        suspended = false
        reconcileTicking()
        do {
            try await cover.start(settings: settingsByDisplay())
            guard attempt == request else { return }
            startingProtection = false
            protected = true
            captureStatus = "회전 블러 실험 중 · 이탈 자동 판정은 미연결"
            reconcileTicking()
            if !fresh { invalidateMotion("AirPods 입력 중단") }
        } catch {
            guard attempt == request else { return }
            startingProtection = false
            protected = false
            captureStatus = "시작 실패: \(error.localizedDescription)"
            reconcileTicking()
        }
    }

    func stopProtection() {
        request += 1
        protected = false
        startingProtection = false
        suspended = false
        retainingForInputLoss = false
        captureStatus = "보호 꺼짐"
        reconcileTicking()
        cover.stop()
    }

    func quit() {
        motion.stop()
        previewRenderer.stop()
        stopProtection()
        clock.stop()
        NSApp.terminate(nil)
    }

    /// AppKit 창 상태가 바뀔 때 호출함. SwiftUI의 view 생명주기만으로는 가림·최소화를 모두 알 수 없음.
    func setPreviewWindowVisible(_ visible: Bool) {
        guard previewWindowVisible != visible else { return }
        previewWindowVisible = visible
        previewRenderer.setVisible(visible)
        if visible { renderPreview() }
        reconcileTicking()
    }

    var layoutDraft: [DisplayPose] {
        appliedPoses.isEmpty ? DisplayLayout.spatialPoses(displays: displays) : appliedPoses
    }

    /// 현재 연결된 화면 전체와 정확히 대응하는 유효한 배치만 적용함. 실패하면 이전 배치를 유지함.
    @discardableResult
    func applyLayout(_ poses: [DisplayPose]) -> Bool {
        guard !protected, !startingProtection, poses.count == displays.count,
              Set(poses.map(\.id)) == Set(displays.map(\.id)),
              let layout = CompiledLayout(poses: poses) else { return false }
        appliedLayout = layout
        appliedPoses = poses
        return true
    }

    /// previewAngle이 없으면 실제 보호용 값임. 보정, 배치, 신선한 입력 중 하나라도 없으면 전체를 가림.
    func settingsByDisplay(previewAngle: Double? = nil) -> [CGDirectDisplayID: RenderSettings] {
        let live = previewAngle == nil
        let gaze = previewAngle ?? liveGaze
        return Dictionary(uniqueKeysWithValues: displays.map { display in
            guard let layout = appliedLayout, let table = layout.displays[display.id], let gaze,
                  !(live && (suspended || !fresh)) else {
                return (display.id, RenderSettings.covered(radius: maximumBlur))
            }
            return (display.id, RenderSettings.spatial(table, in: layout, gaze: gaze, start: startAngle,
                                                       transitionFraction: connectionWidth / 100,
                                                       radius: maximumBlur))
        })
    }

    /// 주기 호출 한 번. 입력 만료 판정, 고개 각도 평활화, 미리보기와 가림 갱신을 수행함.
    private func tick() {
        guard shouldTick else {
            reconcileTicking()
            return
        }
        let now = clock.now
        let dt = min(0.2, max(0, now - lastTick))
        lastTick = now
        if probing, let began = probeStartedAt, now - began >= 10 { stopProbe() }
        if receiving && !fresh { invalidateMotion("입력이 끊김 — 연결과 착용을 확인해 주세요") }
        if fresh, let yaw = sample?.yaw {
            let alpha = 1 - exp(-dt / max(0.03, responseTime))
            filteredYaw = BlurProfile.interpolatedDegrees(from: filteredYaw ?? yaw, to: yaw, fraction: alpha)
        }
        if previewWindowVisible { renderPreview() }
        if protected || startingProtection { updateCovers() }
        reconcileTicking()
    }

    private var liveGaze: Double? {
        guard let deskReference, let filteredYaw else { return nil }
        return BlurProfile.relativeDegrees(current: filteredYaw, reference: deskReference) * direction
    }

    private func receive(_ value: HeadSample) {
        guard value.isFresh(at: clock.now) else { invalidateMotion("오래되었거나 유효하지 않은 센서 입력"); return }
        guard value.yaw.isFinite, value.timestamp.isFinite else { invalidateMotion("유효하지 않은 센서 입력"); return }
        if let previous = sample {
            if value.source != previous.source { invalidateMotion("이어버드 입력이 바뀜 — 기준을 다시 맞춰 주세요") }
            else if value.timestamp <= previous.timestamp { return }
        }
        sample = value
        receiving = true
        reconcileTicking()
        sampleCount += 1
        motionStatus = "입력 수신 중 · \(sampleCount) samples · 이어버드 \(value.source)"
        if probing {
            probe.ingest(timestamp: value.timestamp, acceleration: value.acceleration, gravity: value.gravity)
            if probe.duration >= 10 { stopProbe() }
        }
    }

    private func invalidateMotion(_ message: String) {
        receiving = false
        sample = nil
        motionStatus = message
        probing = false
        deskReference = nil
        filteredYaw = nil
        reconcileTicking()
        guard protected || startingProtection else { return }
        if retainBlurOnInputLoss {
            retainingForInputLoss = true
            suspended = true
            captureStatus = "입력 중단 · 전체 블러 유지 · 보호를 끄고 다시 보정해 주세요"
            updateCovers()
        } else {
            releaseForInputLoss()
        }
    }

    private func releaseForInputLoss() {
        stopProtection()
        captureStatus = "입력 중단 · 블러 해제됨 · 재착용 후 정면 보정과 보호 시작이 필요함"
    }

    private func renderPreview() {
        let settings = demo && appliedLayout == nil
            ? RenderSettings.hinge(angle: demoAngle, start: startAngle, full: startAngle + 40, radius: maximumBlur)
            : settingsByDisplay(previewAngle: demo ? demoAngle : nil)[selectedDisplay] ?? .covered(radius: maximumBlur)
        previewRenderer.request(exampleImage, settings: settings)
    }

    private func updateCovers() { cover.update(settingsByDisplay()) }

    private func reconcileTicking() {
        if shouldTick {
            guard !ticking else { return }
            ticking = true
            lastTick = clock.now
            clock.start { [weak self] in self?.tick() }
        } else if ticking {
            ticking = false
            clock.stop()
        }
    }

    private func refreshDisplays() {
        displays = connectedDisplays()
        selectedDisplay = displays.first?.id ?? 0
    }

    @objc private func screenChanged() {
        stopProtection()
        deskReference = nil
        filteredYaw = nil
        appliedPoses = []
        appliedLayout = nil
        refreshDisplays()
        captureStatus = "화면 구성이 달라져 실험을 중지함 — 다시 보정해 주세요"
    }

    @objc private func willSleep() {
        motion.stop()
        invalidateMotion("잠자기 진입 · 복귀 후 입력을 다시 시작해 주세요")
    }
}
