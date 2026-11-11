import AppKit
import Combine
import PrivacyCore
import CoreImage

@MainActor
final class AppModel: ObservableObject {
    @Published var displays: [DisplayCalibration] = []
    @Published var selectedDisplay: CGDirectDisplayID = 0
    @Published var motionStatus = "AirPods 연결 확인 전"
    @Published var captureStatus = "보호 꺼짐"
    @Published var sample: HeadSample?
    @Published var sampleCount = 0
    @Published var receiving = false
    @Published var protected = false
    @Published var startingProtection = false
    @Published var suspended = false
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
    @Published var gapCM = 0.0
    @Published var viewingDistanceCM = 60.0
    @Published var frontOffsetCM = 0.0
    @Published var startAngle = 35.0
    @Published var deskReference: Double?
    @Published var appliedPoses: [DisplayPose] = []
    private var appliedAngles: [CGDirectDisplayID: CompiledDisplayAngles] = [:]
    private var appliedSpan = 0.0
    @Published var previewImage: CGImage?
    @Published var probe = InertialProbe()
    @Published var probing = false
    @Published var trialLabel = "앉은 채 정지"

    private let motion = MotionService()
    private let cover = ScreenCover()
    private let previewRenderer: PreviewRenderer
    private let exampleImage: CIImage
    private var timer: Timer?
    private var timerGeneration = 0
    private var filteredYaw: Double?
    private var lastTick = ProcessInfo.processInfo.systemUptime
    private var probeStartedAt: TimeInterval?
    private var request = 0
    private var retainingForInputLoss = false
    private var previewWindowVisible = false

    private var shouldRunTimer: Bool {
        previewWindowVisible || receiving || protected || startingProtection || probing
    }

    init() {
        exampleImage = ExampleScreen.make()
        previewRenderer = PreviewRenderer()
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
        NotificationCenter.default.addObserver(self, selector: #selector(screenChanged), name: NSApplication.didChangeScreenParametersNotification, object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(willSleep), name: NSWorkspace.willSleepNotification, object: nil)
    }

    var protectionWindows: [NSPanel] { cover.outputWindows }

    var fresh: Bool {
        guard let sample else { return false }
        return receiving && sample.isFresh(at: ProcessInfo.processInfo.systemUptime)
    }

    var canProtect: Bool {
        fresh && deskReference != nil && !appliedAngles.isEmpty && !startingProtection
    }

    var selected: DisplayCalibration? { displays.first(where: { $0.id == selectedDisplay }) }
    var currentAngle: Double {
        guard let sample else { return 0 }
        guard let deskReference else { return 0 }
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
        probeStartedAt = ProcessInfo.processInfo.systemUptime
        probing = true
        reconcileTimer()
    }

    func toggleProtection() {
        if protected || startingProtection { stopProtection(); return }
        guard canProtect else { captureStatus = "AirPods 입력·화면 폭·정면 보정을 확인해 주세요"; return }
        request += 1
        let attempt = request
        startingProtection = true
        captureStatus = "화면 블러 준비 중"
        suspended = false
        reconcileTimer()
        Task {
            guard attempt == request else { return }
            do {
                try await cover.start(settings: settingsByDisplay())
                guard attempt == request else { return }
                startingProtection = false
                protected = true
                captureStatus = "회전 블러 실험 중 · 이탈 자동 판정은 미연결"
                reconcileTimer()
                if !fresh { invalidateMotion("AirPods 입력 중단") }
            } catch {
                guard attempt == request else { return }
                startingProtection = false
                protected = false
                captureStatus = "시작 실패: \(error.localizedDescription)"
                reconcileTimer()
            }
        }
    }

    func stopProtection() {
        request += 1
        protected = false
        startingProtection = false
        suspended = false
        retainingForInputLoss = false
        captureStatus = "보호 꺼짐"
        reconcileTimer()
        cover.stop()
    }

    func quit() {
        motion.stop()
        previewRenderer.stop()
        request += 1
        stopTimer()
        let cleanup = cover.stop()
        Task { await cleanup.value; NSApp.terminate(nil) }
    }

    private func receive(_ value: HeadSample) {
        guard value.isFresh(at: ProcessInfo.processInfo.systemUptime) else { invalidateMotion("오래되었거나 유효하지 않은 센서 입력"); return }
        guard value.yaw.isFinite, value.timestamp.isFinite else { invalidateMotion("유효하지 않은 센서 입력"); return }
        if let previous = sample {
            if value.source != previous.source { invalidateMotion("이어버드 입력이 바뀜 — 기준을 다시 맞춰 주세요") }
            else if value.timestamp <= previous.timestamp { return }
        }
        sample = value
        receiving = true
        reconcileTimer()
        sampleCount += 1
        motionStatus = "입력 수신 중 · \(sampleCount) samples · 이어버드 \(value.source)"
        if probing {
            probe.ingest(timestamp: value.timestamp, acceleration: value.acceleration, gravity: value.gravity)
            if probe.duration >= 10 {
                probing = false
                reconcileTimer()
            }
        }
    }

    private func invalidateMotion(_ message: String) {
        receiving = false
        sample = nil
        motionStatus = message
        probing = false
        deskReference = nil
        filteredYaw = nil
        reconcileTimer()
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

    private func tick() {
        guard shouldRunTimer else {
            reconcileTimer()
            return
        }
        let now = ProcessInfo.processInfo.systemUptime
        let dt = min(0.2, max(0, now - lastTick))
        lastTick = now
        if probing, let began = probeStartedAt, now - began >= 10 {
            probing = false
            reconcileTimer()
        }
        if receiving && !fresh { invalidateMotion("입력이 끊김 — 연결과 착용을 확인해 주세요") }
        if fresh, let yaw = sample?.yaw {
            let alpha = 1 - exp(-dt / max(0.03, responseTime))
            filteredYaw = BlurProfile.interpolatedDegrees(from: filteredYaw ?? yaw, to: yaw, fraction: alpha)
        }
        if previewWindowVisible { renderPreview() }
        if protected || startingProtection { updateCovers() }
        reconcileTimer()
    }

    /// AppKit 창 상태가 바뀔 때 호출함. SwiftUI의 view 생명주기만으로는 가림·최소화를 모두 알 수 없음.
    func setPreviewWindowVisible(_ visible: Bool) {
        guard previewWindowVisible != visible else { return }
        previewWindowVisible = visible
        previewRenderer.setVisible(visible)
        if visible { renderPreview() }
        reconcileTimer()
    }

    private func renderPreview() {
        let settings = demo && appliedAngles.isEmpty
            ? RenderSettings(angle: demoAngle, start: startAngle,
                             full: (startAngle) + 40, radius: maximumBlur)
            : settingsByDisplay(previewAngle: demo ? demoAngle : nil)[selectedDisplay] ?? RenderSettings(forceCovered: true)
        previewRenderer.request(exampleImage, settings: settings)
    }

    var layoutDraft: [DisplayPose] {
        if !appliedPoses.isEmpty { return appliedPoses }
        return DisplayLayout.spatialPoses(displays: displays, gap: gapCM,
                                          viewingDistance: viewingDistanceCM, frontOffset: frontOffsetCM)
    }

    @discardableResult
    func applyLayout(_ poses: [DisplayPose]) -> Bool {
        guard !protected, !startingProtection, !poses.isEmpty,
              poses.count == displays.count, Set(poses.map(\.id)) == Set(displays.map(\.id)) else { return false }
        let tables = poses.compactMap { $0.compiled() }
        guard tables.count == poses.count else { return false }
        appliedSpan = (tables.map(\.maximumAngle).max() ?? 0) - (tables.map(\.minimumAngle).min() ?? 0)
        appliedAngles = Dictionary(uniqueKeysWithValues: tables.map { ($0.id, $0) })
        appliedPoses = poses
        return true
    }

    func settingsByDisplay(previewAngle: Double? = nil) -> [CGDirectDisplayID: RenderSettings] {
        let gaze = previewAngle ?? deskReference.flatMap { reference in
            filteredYaw.map { BlurProfile.relativeDegrees(current: $0, reference: reference) * direction }
        }
        return Dictionary(uniqueKeysWithValues: displays.map { display in
            let table = appliedAngles[display.id]
            return (display.id, RenderSettings(radius: maximumBlur,
                forceCovered: table == nil || gaze == nil || (previewAngle == nil && (suspended || !fresh)),
                spatial: table, gaze: gaze ?? 0, spatialStart: startAngle,
                spatialTransition: appliedSpan * connectionWidth / 100))
        })
    }

    private func updateCovers() { cover.update(settingsByDisplay()) }

    private func reconcileTimer() {
        if shouldRunTimer {
            guard timer == nil else { return }
            timerGeneration &+= 1
            let generation = timerGeneration
            lastTick = ProcessInfo.processInfo.systemUptime
            timer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
                Task { @MainActor [weak self] in
                    guard let self,
                          self.timer != nil,
                          self.timerGeneration == generation,
                          self.shouldRunTimer else { return }
                    self.tick()
                }
            }
        } else {
            stopTimer()
        }
    }

    private func stopTimer() {
        guard timer != nil else { return }
        timer?.invalidate()
        timer = nil
        timerGeneration &+= 1
    }

    private func refreshDisplays() {
        let screens = NSScreen.screens.filter { screen in
            !ProcessInfo.processInfo.arguments.contains("--built-in-only") || CGDisplayIsBuiltin(screen.displayID) != 0
        }
        displays = DisplayLayout.calibrations(for: screens.map {
            DisplayLayout.Screen(id: $0.displayID, name: $0.localizedName, frame: $0.frame)
        })
        for index in displays.indices {
            let size = CGDisplayScreenSize(displays[index].id)
            let rotated = Int(CGDisplayRotation(displays[index].id).rounded()) % 180 != 0
            displays[index].widthCM = (rotated ? size.height : size.width) / 10
            displays[index].heightCM = (rotated ? size.width : size.height) / 10
            displays[index].builtin = CGDisplayIsBuiltin(displays[index].id) != 0
        }
        selectedDisplay = displays.first?.id ?? 0
    }

    @objc private func screenChanged() {
        stopProtection()
        deskReference = nil
        filteredYaw = nil
        appliedPoses = []
        appliedAngles = [:]
        refreshDisplays()
        captureStatus = "화면 구성이 달라져 실험을 중지함 — 다시 보정해 주세요"
    }

    @objc private func willSleep() {
        motion.stop()
        invalidateMotion("잠자기 진입 · 복귀 후 입력을 다시 시작해 주세요")
    }
}

enum ExampleScreen {
    @MainActor static func make() -> CIImage {
        let size = NSSize(width: 800, height: 420)
        let image = NSImage(size: size)
        image.lockFocus()
        NSColor(calibratedRed: 0.09, green: 0.12, blue: 0.18, alpha: 1).setFill()
        NSBezierPath(rect: NSRect(origin: .zero, size: size)).fill()
        let heading: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 26, weight: .semibold), .foregroundColor: NSColor.white]
        ("PRIVACY / 미리보기" as NSString).draw(at: NSPoint(x: 28, y: 360), withAttributes: heading)
        for column in 0..<3 {
            let x = CGFloat(28 + column * 254)
            NSColor(calibratedWhite: 0.20 + CGFloat(column) * 0.04, alpha: 1).setFill()
            NSBezierPath(roundedRect: NSRect(x: x, y: 45, width: 235, height: 285), xRadius: 16, yRadius: 16).fill()
            let titles = ["오늘 할 일", "프로젝트 메모", "주간 일정"]
            (titles[column] as NSString).draw(at: NSPoint(x: x + 18, y: 285), withAttributes: [.font: NSFont.systemFont(ofSize: 20, weight: .medium), .foregroundColor: NSColor.white])
            for row in 0..<6 {
                ("\(row + 1). 예제 내용 확인하기" as NSString).draw(at: NSPoint(x: x + 18, y: CGFloat(246 - row * 32)), withAttributes: [.font: NSFont.systemFont(ofSize: 15), .foregroundColor: NSColor(calibratedWhite: 0.9, alpha: 1)])
            }
        }
        image.unlockFocus()
        var rect = NSRect(origin: .zero, size: size)
        return CIImage(cgImage: image.cgImage(forProposedRect: &rect, context: nil, hints: nil)!)
    }
}
