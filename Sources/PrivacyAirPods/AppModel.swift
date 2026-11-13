import AppKit
import Combine
import PrivacyCore
import CoreImage

/// 센서 sample과 미리보기 프레임마다 바뀌는 표시값. 이 값을 쓰는 작은 view만 관찰하게 해
/// 설정 창과 메뉴 전체가 sample마다 다시 계산되지 않게 함. 보호 판정은 이 값을 읽지 않음.
@MainActor
final class LiveReadout: ObservableObject {
    @Published fileprivate(set) var sampleCount = 0
    /// 책상 정면 기준 현재 고개 각도(도). 오른쪽 회전이 양수이며 보정 전에는 0임.
    @Published fileprivate(set) var angle = 0.0
    @Published fileprivate(set) var previewImage: CGImage?
}

/// 보정, 배치, 실제 보호, 입력 중단 정책을 소유함. 화면 표시 상태는 흐름 함수로만 바뀜.
/// 여기의 published 값은 상태가 바뀔 때만 갱신하고, sample마다 바뀌는 값은 `readout`에 둠.
@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var displays: [DisplayCalibration] = []
    @Published var selectedDisplay: CGDirectDisplayID = 0
    @Published private(set) var motionStatus = "AirPods 연결 확인 전"
    @Published private(set) var captureStatus = "보호 꺼짐"
    private(set) var sample: HeadSample?
    @Published private(set) var receiving = false
    @Published private(set) var protected = false
    @Published private(set) var startingProtection = false
    @Published private(set) var suspended = false
    @Published var retainBlurOnInputLoss = false {
        didSet {
            persistSettings()
            if !retainBlurOnInputLoss && retainingForInputLoss && !retainingForLeave {
                releaseForInputLoss()
            }
        }
    }
    /// 자리를 뜨면 가리기 스위치. 끄면 자리 이탈을 보지 않고, 자리 비움 중이었다면 바로 돌아옴.
    @Published var hideWhenAway = true {
        didSet {
            persistSettings()
            guard protected, hideWhenAway != oldValue else { return }
            if hideWhenAway {
                beginAwayWatch()
            } else {
                activity.stop()
                resumeProtection()
            }
        }
    }
    /// 자리 비움으로 가린 상태인지 나타냄. 상태 문구와 '보호 재개' 단추가 이 값만 봄.
    @Published private(set) var away = false
    @Published var demo = true
    @Published var demoAngle = 0.0
    /// CoreMotion yaw는 위에서 볼 때 왼쪽 회전이 양수라서 뒤집어 오른쪽 회전을 양수로 맞춤. 바꾸는 기능은 없음.
    private let direction = -1.0
    @Published var maximumBlur = 31.25 { didSet { persistSettings() } }
    @Published var responseTime = 0.18 { didSet { persistSettings() } }
    @Published var connectionWidth = 25.0 { didSet { persistSettings() } }
    @Published var startAngle = 35.0 { didSet { persistSettings() } }
    /// 배치 시트의 팔 길이와 모형. 시트에서 '이 배치 적용'을 눌러야만 여기에 들어옴.
    @Published var armLengthCM = HumanGuide.female.armLengthCM { didSet { persistSettings() } }
    @Published var armGuide = HumanGuide.female { didSet { persistSettings() } }
    @Published private(set) var deskReference: Double? {
        // AirPods 보기는 정면 기준이 있어야 고를 수 있음. 기준이 사라졌는데 그 보기에 남으면
        // 미리보기는 전체 블러로 멈추고 고개 슬라이더는 잠기므로 직접 돌려보기로 돌려놓음.
        didSet { if deskReference == nil && !demo { demo = true } }
    }
    @Published private(set) var appliedPoses: [DisplayPose] = []
    /// 마지막 입력 오류가 동작 접근 거절인지 나타냄. 거절 문구 비교는 `invalidateMotion` 한 곳에서만 함.
    @Published private(set) var motionAccessDenied = false
    let readout = LiveReadout()

    private let motion: HeadMotionSource
    private let clock: FrameClock
    private let connectedDisplays: @MainActor () -> [DisplayCalibration]
    private let activity: HeadActivitySource
    private let memory: SettingsMemory
    /// 저장된 설정을 적용하는 동안에는 한 항목씩 바뀔 때마다 쓰지 않도록 막음.
    private var restoringSettings = false
    private let cover = ScreenCover()
    private let previewRenderer = PreviewRenderer()
    private let exampleImage = ExampleScreen.make()
    private var appliedLayout: CompiledLayout?
    private var ticking = false
    private var filteredYaw: Double?
    private var lastTick: TimeInterval
    private var request = 0
    private var retainingForInputLoss = false
    /// 자리를 뜨는 중 입력이 끊겨 'AirPods를 벗으면' 설정과 무관하게 전체 블러를 유지하는 중임. 보호를 끌 때만 풀림.
    /// 다시 착용한 뒤 입력이 또 끊겨도 이 값이 남아 있어야 두 번째 중단에서 설정대로 풀리지 않음.
    private var retainingForLeave = false
    private var previewWindowVisible = false
    /// 머리 움직임 모양으로 일어섬과 앉음을 판정함. 보호가 시작될 때마다 앉은 상태에서 다시 시작함.
    private var presence = SeatPresence()
    /// 일어선 시각. 이 시각부터 `AwayTiming.standingDelay`가 지나면 자리 비움으로 봄. 앉거나 자리 비움이면 nil.
    /// 앉는 후보가 확인되는 동안에는 자리 비움을 미뤄, 3초 안에 다시 앉은 사용자를 잠깐이라도 가리지 않음.
    private var standingSince: TimeInterval?
    /// 고개 따라가기(0)와 최대 블러(1) 사이의 가림 정도. 자리 비움 전환을 한 번에 바꾸지 않으려고 씀.
    private var awayCoverage = 0.0
    /// 이 시각 전의 걷기 활동은 무시함. 앉은 직후 늦게 도착한 걷기 callback이 자리 비움을 되살려 앉은 사용자를 가두는 것을 막음.
    private var movingIgnoredUntil: TimeInterval = 0

    private var shouldTick: Bool {
        previewWindowVisible || receiving || protected || startingProtection
    }

    /// 자리 비움 판정의 시간 기준. 3초·0.5초·3초는 승인된 행동값임.
    /// 일어섬과 앉음의 머리 움직임 기준은 `SeatPresence.Tuning`이 실제 기록 두 개로 고른 값이며 여기서 다루지 않음.
    private enum AwayTiming {
        /// 일어선 뒤 다시 앉지 않고 머무는 시간. 초 단위임.
        static let standingDelay: TimeInterval = 3
        /// 가림 정도가 목표 값으로 옮겨 가는 시간. 초 단위이며 전환을 부드럽게 하려고 둠.
        static let fadeDuration: TimeInterval = 0.5
        /// 돌아온 직후 걷기 활동을 무시하는 시간. 초 단위임.
        static let returnSettle: TimeInterval = 3
    }

    /// 실제 앱 구성: AirPods, 시스템 시계, 연결된 화면, 시스템 알림.
    convenience init() {
        self.init(motion: MotionService(), clock: SystemFrameClock(),
                  connectedDisplays: { DisplayLayout.connected() },
                  notifications: .default, workspaceNotifications: NSWorkspace.shared.notificationCenter,
                  activity: HeadActivityService(),
                  memory: SettingsMemory(defaults: .standard))
    }

    /// 테스트는 입력, 시계, 화면 목록, 알림, 활동, 기억 저장소 경계만 대역으로 바꾸고 나머지 보호 경로는 실제로 실행함.
    init(motion: HeadMotionSource, clock: FrameClock,
         connectedDisplays: @escaping @MainActor () -> [DisplayCalibration],
         notifications: NotificationCenter, workspaceNotifications: NotificationCenter,
         activity: HeadActivitySource,
         memory: SettingsMemory) {
        self.motion = motion
        self.clock = clock
        self.connectedDisplays = connectedDisplays
        self.activity = activity
        self.memory = memory
        lastTick = clock.now
        activity.onActivity = { [weak self] value in self?.receiveActivity(value) }
        restoreSettings()
        previewRenderer.onFrame = { [weak self] frame in self?.readout.previewImage = frame.image }
        previewRenderer.onFailure = { [weak self] in self?.readout.previewImage = nil }
        refreshDisplays()
        motion.onSample = { [weak self] value in self?.receive(value) }
        motion.onError = { [weak self] error in self?.invalidateMotion(error) }
        cover.onFailure = { [weak self] error in
            guard let self else { return }
            self.retainingForInputLoss = false
            self.suspended = true
            self.clearAway()
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

    /// 설정 화면 준비 항목. 실제 상태에서 매번 계산하며 저장하지 않음.
    var readinessItems: [ReadinessItem] { Readiness.items(readinessSnapshot) }
    var readinessRemaining: Int { Readiness.remaining(readinessItems) }
    var heroMood: HeroMood { Readiness.mood(readinessSnapshot) }

    private var readinessSnapshot: ReadinessSnapshot {
        ReadinessSnapshot(fresh: fresh, motionAccessDenied: motionAccessDenied,
                          deskCalibrated: deskReference != nil, layoutApplied: appliedLayout != nil,
                          screenCount: displays.count, locked: protected || startingProtection)
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

    /// 실제로 정면을 맞췄을 때만 true를 돌려줌. 화면의 cheer는 이 값으로만 켬.
    @discardableResult
    func calibrateDesk() -> Bool {
        guard fresh, let sample, !protected, !startingProtection else { return false }
        deskReference = sample.yaw
        filteredYaw = sample.yaw
        demo = false
        refreshAngle()
        return true
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
            captureStatus = "보호 중"
            beginAwayWatch()
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
        retainingForLeave = false
        captureStatus = "보호 꺼짐"
        activity.stop()
        away = false
        standingSince = nil
        awayCoverage = 0
        reconcileTicking()
        cover.stop()
    }

    /// 자리 비움으로 가려진 보호를 앉은 것으로 보고 고개 따라가기로 되돌림. 앉기를 놓쳤을 때 직접 쓰는 길임.
    func resumeProtection() {
        guard away else { return }
        away = false
        standingSince = nil
        // 돌아오는 가림은 전환 없이 바로 고개 따라가기로 바꿈.
        awayCoverage = 0
        movingIgnoredUntil = clock.now + AwayTiming.returnSettle
        presence.reset(to: .seated)
        captureStatus = "보호 중"
    }

    /// 가림이 입력 중단으로 전체 블러에 고정되면 자리 비움 기록을 지움. 고정된 가림에 '자리 비움'과 '보호 재개'를 남기면 실제 가림과 문구가 어긋남.
    private func clearAway() {
        away = false
        standingSince = nil
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
        saveLayoutForCurrentDisplays()
        return true
    }

    /// 배치 시트의 '이 배치 적용'. 팔 길이와 모형은 배치가 적용될 때만 함께 바뀜.
    @discardableResult
    func applyLayout(_ poses: [DisplayPose], armLengthCM: Double, armGuide: HumanGuide) -> Bool {
        guard applyLayout(poses) else { return false }
        self.armLengthCM = armLengthCM
        self.armGuide = armGuide
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
            var settings = RenderSettings.spatial(table, in: layout, gaze: gaze, start: startAngle,
                                                  transitionFraction: connectionWidth / 100,
                                                  radius: maximumBlur)
            // 자리 비움 가림은 실제 보호 값에만 씀. 미리보기 각도는 고개 값만 보여 줌.
            if live { settings.coverage = awayCoverage }
            return (display.id, settings)
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
        if receiving && !fresh { invalidateMotion("입력이 끊김 — 연결과 착용을 확인해 주세요") }
        if fresh, let yaw = sample?.yaw {
            let alpha = 1 - exp(-dt / max(0.03, responseTime))
            filteredYaw = BlurProfile.interpolatedDegrees(from: filteredYaw ?? yaw, to: yaw, fraction: alpha)
        }
        advanceAway(dt: dt, now: now)
        if previewWindowVisible { renderPreview() }
        if protected || startingProtection { updateCovers() }
        reconcileTicking()
    }

    private func refreshAngle() {
        let angle = currentAngle
        if readout.angle != angle { readout.angle = angle }
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
        if !receiving { receiving = true }
        trackPosture(value)
        reconcileTicking()
        readout.sampleCount += 1
        refreshAngle()
        let status = "입력 수신 중 · 이어버드 \(value.source)"
        if motionStatus != status { motionStatus = status }
    }

    private func invalidateMotion(_ message: String) {
        receiving = false
        sample = nil
        motionStatus = message
        motionAccessDenied = message == MotionService.accessDeniedMessage
        deskReference = nil
        filteredYaw = nil
        refreshAngle()
        reconcileTicking()
        guard protected || startingProtection else { return }
        // 일어선 뒤나 자리 비움 중의 입력 중단은 AirPods를 빼고 떠나는 경우로 보고 설정과 상관없이 가림을 유지함.
        if isAwayWatching && (away || standingSince != nil) { retainingForLeave = true }
        if retainBlurOnInputLoss || retainingForLeave {
            retainingForInputLoss = true
            suspended = true
            clearAway()
            captureStatus = retainingForLeave
                ? "입력 중단 · 자리를 비운 중이라 전체 블러 유지 · 보호를 끄고 다시 보정해 주세요"
                : "입력 중단 · 전체 블러 유지 · 보호를 끄고 다시 보정해 주세요"
            updateCovers()
        } else {
            releaseForInputLoss()
        }
    }

    private func releaseForInputLoss() {
        stopProtection()
        captureStatus = "입력 중단 · 블러 해제됨 · 재착용 후 정면 보정과 보호 시작이 필요함"
    }

    /// 보호가 실제로 시작됐을 때 자리 이탈 판정을 앉은 상태에서 새로 시작함. 이전 보호의 일어섬 기록은 버림.
    private func beginAwayWatch() {
        presence.reset(to: .seated)
        standingSince = nil
        away = false
        awayCoverage = 0
        movingIgnoredUntil = 0
        if hideWhenAway { activity.start() }
    }

    /// 판정 조건은 보호 중이고 스위치가 켜져 있으며 입력이 살아 있을 때뿐임. 중단된 가림에서는 자리를 보지 않음.
    private var isAwayWatching: Bool {
        protected && hideWhenAway && !suspended
    }

    /// 걷기 감지는 일어섬 판정을 기다리지 않고 바로 자리 비움으로 봄. 다시 앉을 때 돌아오도록 서 있는 자세에서 시작함.
    private func receiveActivity(_ kind: HeadActivity) {
        guard isAwayWatching, kind == .moving, !away, clock.now >= movingIgnoredUntil else { return }
        presence.reset(to: .standing)
        enterAway()
    }

    private func trackPosture(_ value: HeadSample) {
        guard isAwayWatching else { return }
        switch presence.ingest(timestamp: value.timestamp, acceleration: value.acceleration, gravity: value.gravity) {
        case .stoodUp:
            if !away { standingSince = clock.now }
        case .satDown:
            standingSince = nil
            resumeProtection()
        case nil:
            break
        }
    }

    /// 일어선 채 기준 시간이 지나면 자리 비움으로 보고, 가림 정도를 매 주기 목표 쪽으로 조금씩 옮김.
    /// 앉는 후보가 확인 중이면 기준 시간이 지나도 자리 비움으로 보지 않음. 확인이 끝나면 앉음이거나 일어선 상태가 남음.
    private func advanceAway(dt: Double, now: TimeInterval) {
        if isAwayWatching, !away, !presence.isConfirmingSit,
           let since = standingSince, now - since >= AwayTiming.standingDelay {
            enterAway()
        }
        let target = away ? 1.0 : 0.0
        let step = dt / AwayTiming.fadeDuration
        awayCoverage = awayCoverage < target ? min(target, awayCoverage + step) : max(target, awayCoverage - step)
    }

    private func enterAway() {
        away = true
        standingSince = nil
        captureStatus = "자리 비움 · 전체 블러 · 다시 앉으면 돌아옴"
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

    /// 화면 목록을 갱신하고 같은 조합의 저장 배치가 되살아났는지 돌려줌.
    @discardableResult
    private func refreshDisplays() -> Bool {
        displays = connectedDisplays()
        selectedDisplay = displays.first?.id ?? 0
        return restoreLayoutForCurrentDisplays()
    }

    /// 저장 배치가 현재 화면 구성과 맞고 CompiledLayout이 만들어질 때만 적용함. 아니면 배치를 비움.
    private func restoreLayoutForCurrentDisplays() -> Bool {
        appliedPoses = []
        appliedLayout = nil
        guard let key = SettingsMemory.combinationKey(for: displays),
              let stored = memory.loadLayout(for: key),
              let poses = SettingsMemory.restoredPoses(stored, displays: displays),
              let layout = CompiledLayout(poses: poses) else { return false }
        appliedPoses = poses
        appliedLayout = layout
        return true
    }

    private func saveLayoutForCurrentDisplays() {
        guard let key = SettingsMemory.combinationKey(for: displays),
              let stored = SettingsMemory.storedPoses(appliedPoses, displays: displays) else { return }
        memory.saveLayout(stored, for: key)
    }

    private func restoreSettings() {
        guard let stored = memory.loadSettings() else { return }
        restoringSettings = true
        defer { restoringSettings = false }
        startAngle = stored.startAngle
        maximumBlur = stored.maximumBlur
        connectionWidth = stored.connectionWidth
        responseTime = stored.responseTime
        retainBlurOnInputLoss = stored.retainBlurOnInputLoss
        hideWhenAway = stored.hideWhenAway
        armLengthCM = stored.armLengthCM
        armGuide = stored.armGuide.guide
    }

    /// 직접 돌려보기 값, 보호 상태, 정면 기준은 여기 넣지 않음. 다시 열면 기본값에서 시작함.
    private func persistSettings() {
        guard !restoringSettings else { return }
        memory.saveSettings(StoredSettings(startAngle: startAngle, maximumBlur: maximumBlur,
                                           connectionWidth: connectionWidth, responseTime: responseTime,
                                           retainBlurOnInputLoss: retainBlurOnInputLoss,
                                           hideWhenAway: hideWhenAway,
                                           armLengthCM: armLengthCM, armGuide: StoredGuide(armGuide)))
    }

    @objc private func screenChanged() {
        stopProtection()
        deskReference = nil
        filteredYaw = nil
        let restored = refreshDisplays()
        captureStatus = restored
            ? "화면 구성이 바뀜 · 정면을 다시 맞춰 주세요"
            : "화면 구성이 바뀜 · 정면과 배치를 다시 맞춰 주세요"
    }

    @objc private func willSleep() {
        motion.stop()
        invalidateMotion("잠자기 진입 · 복귀 후 입력을 다시 시작해 주세요")
    }
}
