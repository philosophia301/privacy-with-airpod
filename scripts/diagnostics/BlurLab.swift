import AppKit
import PrivacyCore

/// 제품 상태·보정·설정을 저장하지 않는 단일 화면 렌더 실험 도구임.
@MainActor final class BlurLab: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private var window: NSWindow!
    private var item: NSStatusItem!
    private let angle = NSSlider(value: 45, minValue: -90, maxValue: 90, target: nil, action: nil)
    private let radius = NSSlider(value: 20, minValue: 0, maxValue: 80, target: nil, action: nil)
    private let status = NSTextField(wrappingLabelWithString: "수동 각도로 실험 준비됨")
    private let sensor = NSButton(checkboxWithTitle: "AirPods 입력 사용", target: nil, action: nil)
    private let motion = MotionService()
    private var sample: HeadSample?
    private var reference: Double?
    private var cover: PrivateCover?
    private var traceTask: Task<Void, Never>?
    private var freshnessTask: Task<Void, Never>?
    private var sampleUpdateTask: Task<Void, Never>?
    private var generation = 0
    private var starting = false
    private var screenObserver: NSObjectProtocol?
    private var spaceObserver: NSObjectProtocol?
    private let tracing = ProcessInfo.processInfo.arguments.contains("--trace-transitions")
    private var traceUntil = 0.0
    private let builtInOnly = ProcessInfo.processInfo.arguments.contains("--built-in-only")
    private var testScreen: NSScreen? {
        if builtInOnly { return NSScreen.screens.first { CGDisplayIsBuiltin($0.displayID) != 0 } }
        return NSScreen.screens.count == 1 ? NSScreen.screens.first : nil
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.title = "Blur Lab"
        let menu = NSMenu()
        for (title, action) in [("실험 창 열기", #selector(show)), ("블러 해제", #selector(stop)), ("실험 종료", #selector(quit))] {
            let entry = NSMenuItem(title: title, action: action, keyEquivalent: "")
            entry.target = self; menu.addItem(entry)
        }
        item.menu = menu
        window = NSWindow(contentRect: NSRect(x: 100, y: 120, width: 440, height: 380),
                          styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.title = "Privacy AirPods · Blur Lab"
        window.delegate = self; window.level = NSWindow.Level(rawValue: 27)
        let stack = NSStackView(); stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 12
        stack.edgeInsets = NSEdgeInsets(top: 18, left: 18, bottom: 18, right: 18)
        angle.target = self; angle.action = #selector(sliderChanged(_:)); angle.isContinuous = true
        radius.target = self; radius.action = #selector(sliderChanged(_:)); radius.isContinuous = true
        stack.addArrangedSubview(NSTextField(labelWithString: "단일 화면 렌더 실험 · 기존 앱 보호는 꺼두고 사용"))
        stack.addArrangedSubview(NSTextField(labelWithString: "수동 고개 각도 (−90° ~ +90°)"))
        stack.addArrangedSubview(angle)
        stack.addArrangedSubview(NSTextField(labelWithString: "블러 강도")); stack.addArrangedSubview(radius)
        sensor.target = self; sensor.action = #selector(sensorChanged); stack.addArrangedSubview(sensor)
        let buttons = NSStackView()
        for (title, action) in [("정면 맞추기", #selector(calibrate)), ("블러 켜기", #selector(start)), ("해제", #selector(stop))] {
            buttons.addArrangedSubview(NSButton(title: title, target: self, action: action))
        }
        stack.addArrangedSubview(buttons); stack.addArrangedSubview(status)
        for view in [angle, radius, status] { view.widthAnchor.constraint(equalToConstant: 395).isActive = true }
        window.contentView = stack
        motion.onSample = { [weak self] value in
            guard value.yaw.isFinite else { self?.inputLost("유효하지 않은 AirPods 입력"); return }
            self?.sample = value; self?.scheduleSampleUpdate()
        }
        motion.onError = { [weak self] message in self?.inputLost(message) }
        screenObserver = NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
            object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.stop(); self?.status.stringValue = "화면 구성이 바뀌어 실험을 해제함" }
            }
        spaceObserver = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.traceEvent("space-changed") }
            }
        show()
        if ProcessInfo.processInfo.arguments.contains("--smoke-test") {
            Task { @MainActor in
                start()
                guard await smokeSleep(.seconds(2)) else { quit(); return }
                let started = cover != nil
                print("LAB STATUS", status.stringValue)
                let updatesBefore = cover?.maskUpdateCount ?? -1
                angle.doubleValue += 0.000000001; sliderChanged(angle)
                let samePixels = cover?.maskUpdateCount == updatesBefore
                radius.doubleValue = 21; sliderChanged(radius)
                let radiusUpdated = cover?.maskUpdateCount == updatesBefore + 1
                angle.doubleValue = -45; sliderChanged(angle)
                let angleUpdated = cover?.maskUpdateCount == updatesBefore + 2
                radius.doubleValue = 12; sliderChanged(radius)
                guard await smokeSleep(.seconds(1)) else { quit(); return }
                let updatesAfter = cover?.maskUpdateCount ?? -1
                let updated = cover != nil && radiusUpdated && angleUpdated && updatesAfter == updatesBefore + 3
                sensor.state = .on; reference = 0
                let old = ProcessInfo.processInfo.systemUptime - 1
                sample = HeadSample(timestamp: old, receivedAt: old, yaw: 0, acceleration: .zero, gravity: SIMD3(0,0,-1), source: 0)
                update()
                print("LAB LOSS", cover == nil, reference == nil)
                print("LAB UPDATE", updated, updatesBefore, updatesAfter)
                print("LAB PIXEL OPT", samePixels, radiusUpdated, angleUpdated)
                print("LAB LAYOUT", stack.arrangedSubviews.filter { !stack.bounds.contains($0.frame) }.count)
                stop(); print("LAB SMOKE", started, cover == nil)
                sensor.state = .off
                start(); stop()
                guard await smokeSleep(.milliseconds(300)) else { quit(); return }
                print("LAB CANCEL START", cover == nil, !starting)
                for cycle in 0..<3 {
                    start()
                    guard await smokeSleep(.milliseconds(300)) else { quit(); return }
                    let running = cover != nil
                    stop(); stop()
                    print("LAB RESTART", cycle, running, cover == nil)
                }
                sensor.state = .on; reference = 0
                let fresh = ProcessInfo.processInfo.systemUptime
                sample = HeadSample(timestamp: fresh, receivedAt: fresh, yaw: 0,
                                    acceleration: .zero, gravity: SIMD3(0, 0, -1), source: 0)
                start()
                guard await smokeSleep(.milliseconds(100)) else { quit(); return }
                let timerStarted = cover != nil
                guard await smokeSleep(.milliseconds(850)) else { quit(); return }
                print("LAB TIMER LOSS", timerStarted, cover == nil, reference == nil)
                reference = 0
                let renewedStart = ProcessInfo.processInfo.systemUptime
                sample = HeadSample(timestamp: renewedStart, receivedAt: renewedStart, yaw: 0,
                                    acceleration: .zero, gravity: SIMD3(0, 0, -1), source: 0)
                start()
                guard await smokeSleep(.milliseconds(450)) else { quit(); return }
                let burstBefore = cover?.maskUpdateCount ?? -1
                for index in 0..<100 {
                    let now = ProcessInfo.processInfo.systemUptime
                    motion.onSample?(HeadSample(timestamp: now, receivedAt: now, yaw: -Double(index) * 45 / 99,
                        acceleration: .zero, gravity: SIMD3(0, 0, -1), source: 0))
                }
                guard await smokeSleep(.milliseconds(400)) else { quit(); return }
                print("LAB RENEWAL", cover != nil, reference != nil)
                print("LAB COALESCED", cover?.maskUpdateCount == burstBefore + 1)
                guard await smokeSleep(.milliseconds(400)) else { quit(); return }
                print("LAB RENEWED LOSS", cover == nil, reference == nil)
                sensor.state = .off; motion.stop(); sample = nil; reference = nil
                let empty = PrivateCover()
                do {
                    try await empty.start(settings: [:], host: true, independent: true)
                    print("LAB EMPTY REJECTED", false); empty.stop()
                } catch { print("LAB EMPTY REJECTED", true, error.localizedDescription) }
                fflush(stdout)
                quit()
            }
        }
    }

    private func smokeSleep(_ duration: Duration) async -> Bool {
        do {
            try await Task.sleep(for: duration)
            return true
        } catch {
            print("LAB SMOKE ERROR", error.localizedDescription)
            fflush(stdout)
            return false
        }
    }

    private func scheduleSampleUpdate() {
        guard cover != nil, sampleUpdateTask == nil else { return }
        let attempt = generation
        sampleUpdateTask = Task { @MainActor [weak self] in
            await Task.yield()
            guard let self, !Task.isCancelled else { return }
            self.sampleUpdateTask = nil
            guard self.generation == attempt else { return }
            self.update()
        }
    }

    private func beginTracing() {
        guard tracing else { return }
        traceTask?.cancel()
        let attempt = generation
        traceTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                guard let self, self.generation == attempt, self.cover != nil,
                      ProcessInfo.processInfo.systemUptime < self.traceUntil else { return }
                self.update()
                do { try await Task.sleep(for: .milliseconds(8)) } catch { return }
            }
        }
    }

    private func beginFreshnessMonitoring() {
        freshnessTask?.cancel()
        guard sensor.state == .on else { return }
        let attempt = generation
        freshnessTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                guard let self, self.generation == attempt, self.cover != nil,
                      self.sensor.state == .on else { return }
                let now = ProcessInfo.processInfo.systemUptime
                guard let current = self.sample else {
                    self.inputLost("AirPods 입력이 끊겨 블러를 해제함"); return
                }
                let remaining = current.freshnessRemaining(at: now)
                guard remaining > 0 else {
                    self.inputLost("AirPods 입력이 끊겨 블러를 해제함"); return
                }
                do { try await Task.sleep(for: .seconds(remaining)) } catch { return }
                guard self.generation == attempt, self.cover != nil,
                      self.sensor.state == .on else { return }
                let reevaluated = self.sample?.freshnessRemaining(
                    at: ProcessInfo.processInfo.systemUptime) ?? 0
                guard reevaluated > 0 else {
                    self.inputLost("AirPods 입력이 끊겨 블러를 해제함"); return
                }
            }
        }
    }

    private func settings() -> [CGDirectDisplayID: RenderSettings] {
        guard let screen = testScreen else { return [:] }
        let degrees: Double
        if sensor.state == .on, let sample, let reference {
            degrees = -BlurProfile.relativeDegrees(current: sample.yaw, reference: reference)
        } else { degrees = angle.doubleValue }
        return [screen.displayID: RenderSettings(angle: degrees, start: 35, full: 55, radius: radius.doubleValue)]
    }

    @objc private func start() {
        guard cover == nil, !starting else { return }
        guard testScreen != nil else {
            status.stringValue = builtInOnly ? "테스트할 내장 화면이 없음" : "현재 후보는 화면 1대에서만 실험 가능함"
            return
        }
        if sensor.state == .on {
            guard let sample, sample.isFresh(at: ProcessInfo.processInfo.systemUptime), reference != nil else {
                status.stringValue = "AirPods 착용 후 정면을 먼저 맞춰 주세요"; return
            }
        }
        sampleUpdateTask?.cancel(); sampleUpdateTask = nil
        starting = true; generation += 1
        let attempt = generation, candidate = PrivateCover(), input = settings()
        Task { @MainActor in
            guard generation == attempt else { return }
            do {
                try await candidate.start(settings: input, host: true, independent: true)
                guard generation == attempt else { candidate.stop(); return }
                if sensor.state == .on,
                   sample?.isFresh(at: ProcessInfo.processInfo.systemUptime) != true {
                    candidate.stop(); starting = false
                    inputLost("AirPods 입력이 끊겨 블러를 해제함")
                    return
                }
                cover = candidate; starting = false
                update()
                guard cover != nil else { return }
                traceUntil = ProcessInfo.processInfo.systemUptime + 90
                traceEvent("started")
                beginFreshnessMonitoring(); beginTracing()
                status.stringValue = "실험 블러 적용 중 · 메뉴에서 해제 가능"
            } catch {
                candidate.stop()
                if generation == attempt { starting = false; status.stringValue = error.localizedDescription }
            }
        }
    }

    private func update() {
        guard let cover else { return }
        guard testScreen != nil else { stop(); status.stringValue = "화면 구성이 바뀌어 실험을 해제함"; return }
        if sensor.state == .on, sample?.isFresh(at: ProcessInfo.processInfo.systemUptime) != true {
            inputLost("AirPods 입력이 끊겨 블러를 해제함"); return
        }
        do {
            try cover.update(settings: settings())
            if tracing && ProcessInfo.processInfo.systemUptime < traceUntil {
                try cover.trace()
            }
        }
        catch { traceEvent("output-error: \(error.localizedDescription)"); stop(); status.stringValue = error.localizedDescription }
    }

    @objc private func sensorChanged() {
        stop(); reference = nil; sample = nil; angle.isEnabled = sensor.state == .off
        if sensor.state == .on { motion.start(); status.stringValue = "AirPods 착용 후 정면 맞추기를 눌러 주세요" }
        else { motion.stop(); status.stringValue = "수동 각도로 실험 준비됨" }
    }
    @objc private func calibrate() {
        guard sensor.state == .on, let sample, sample.isFresh(at: ProcessInfo.processInfo.systemUptime) else {
            status.stringValue = "현재 AirPods 입력이 없음"; return
        }
        reference = sample.yaw; update(); status.stringValue = "정면 기준을 맞췄음"
    }
    @objc private func sliderChanged(_ sender: NSSlider) { update() }
    private func traceEvent(_ event: String) {
        guard tracing else { return }
        // 화면 픽셀·앱 제목·머리 각도 없이 출력 수명과 OS 전환만 대조함.
        print("LAB EVENT", mach_absolute_time(), event, "active", cover != nil, "sensor", sensor.state == .on)
        fflush(stdout)
    }
    private func inputLost(_ message: String) { traceEvent("input-lost"); stop(); reference = nil; sample = nil; status.stringValue = message }
    @objc private func stop() {
        traceEvent("stop"); generation += 1; starting = false
        traceTask?.cancel(); traceTask = nil
        freshnessTask?.cancel(); freshnessTask = nil
        sampleUpdateTask?.cancel(); sampleUpdateTask = nil
        cover?.stop(); cover = nil; status.stringValue = "실험 블러 해제됨"
    }
    @objc private func show() {
        if builtInOnly {
            guard let screen = testScreen else { return }
            window.setFrameOrigin(NSPoint(x: screen.frame.minX + 100, y: screen.frame.minY + 120))
            window.orderFrontRegardless()
        } else { window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true) }
    }
    @objc private func quit() { NSApp.terminate(nil) }
    func windowWillClose(_ notification: Notification) { quit() }
    func applicationWillTerminate(_ notification: Notification) {
        stop(); motion.stop()
        if let screenObserver { NotificationCenter.default.removeObserver(screenObserver) }
        if let spaceObserver { NSWorkspace.shared.notificationCenter.removeObserver(spaceObserver) }
        NSStatusBar.system.removeStatusItem(item)
    }
}

@main struct BlurLabMain {
    static func main() {
        let app = NSApplication.shared, delegate = BlurLab()
        app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
    }
}
