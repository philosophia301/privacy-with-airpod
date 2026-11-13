import Foundation
@preconcurrency import CoreMotion
import PrivacyCore

// 자리 이탈 판정 기준을 실측하는 명령행 도구임. 제품 앱과 별도이며 제품 설정을 읽거나 쓰지 않음.
// record는 안내 음성에 따라 정해진 동작을 하는 동안 AirPods 움직임과 걷기 판정을 사용자가 지정한 새 파일에만 씀.
// replay는 기록을 SeatPresence와 앱의 자리 비움 규칙으로 다시 돌리고, synth는 AirPods 없이 쓰는 합성 기록을 만듦.

@main
struct SeatRecorderTool {
    static let usage = """
    seat-recorder record --out 새파일.csv [--quick] [--repeat N] [--no-voice] [--wait 초] [--simulate]
    seat-recorder replay 기록.csv [--json] [기준값 인자]
    seat-recorder synth --out 새파일.csv [--quick] [--repeat N]

    기준값 인자: \(TuningFlag.all.map(\.flag).joined(separator: " ")) --standing-delay --return-settle
    """

    @MainActor static func main() {
        do {
            exit(try run(Array(CommandLine.arguments.dropFirst())))
        } catch let error as ToolError {
            FileHandle.standardError.write(Data((error.message + "\n").utf8))
            exit(error.code)
        } catch {
            FileHandle.standardError.write(Data("\(error.localizedDescription)\n".utf8))
            exit(1)
        }
    }

    @MainActor static func run(_ raw: [String]) throws -> Int32 {
        var arguments = Arguments(raw)
        switch arguments.command() {
        case "record": return try Recorder.run(&arguments)
        case "replay": return try replay(&arguments)
        case "synth": return try synth(&arguments)
        case "help", "--help", "-h":
            print(usage)
            return 0
        default:
            throw ToolError(message: usage, code: 64)
        }
    }

    static func replay(_ arguments: inout Arguments) throws -> Int32 {
        var tuning = SeatPresence.Tuning()
        for flag in TuningFlag.all {
            if let value = try arguments.number(flag.flag) { tuning[keyPath: flag.path] = value }
        }
        // sitLevel만 음수를 허용함. 앉은 자세 기준보다 낮은 높이를 앉음 기준으로 잡는 실험이 가능해야 함.
        for flag in TuningFlag.all where flag.name != "sitLevel" && tuning[keyPath: flag.path] <= 0 {
            throw ToolError(message: "\(flag.flag)는 0보다 커야 함", code: 64)
        }
        guard tuning.standLevel > tuning.sitLevel else {
            throw ToolError(message: "--stand-level은 --sit-level보다 커야 함", code: 64)
        }
        var timing = AwayRule.Timing()
        if let value = try arguments.number("--standing-delay") { timing.standingDelay = value }
        if let value = try arguments.number("--return-settle") { timing.returnSettle = value }
        guard timing.standingDelay >= 0, timing.returnSettle >= 0 else {
            throw ToolError(message: "--standing-delay와 --return-settle은 0 이상이어야 함", code: 64)
        }
        let json = arguments.flag("--json")
        guard let path = arguments.positional() else { throw ToolError(message: usage, code: 64) }
        try arguments.finish()
        let text: String
        do {
            text = try String(contentsOfFile: path, encoding: .utf8)
        } catch {
            throw ToolError(message: "기록 파일을 읽을 수 없음: \(path)", code: 66)
        }
        let rows = try RecordFormat.parse(text)
        guard let last = rows.last else { throw ToolError(message: "기록 행이 없음: \(path)", code: 65) }
        var analyzer = SeatAnalyzer(tuning: tuning, timing: timing)
        for row in rows { _ = analyzer.handle(row) }
        let report = analyzer.finish(at: last.rx)
        if json {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            print(String(decoding: try encoder.encode(report), as: UTF8.self))
        } else {
            print(ReportText.render(report, source: path))
        }
        return 0
    }

    static func synth(_ arguments: inout Arguments) throws -> Int32 {
        let path = try arguments.requiredValue("--out")
        let steps = try arguments.steps()
        try arguments.finish()
        let writer = try RowWriter.create(path: path)
        for row in SyntheticRecording.make(steps: steps) { writer.append(row) }
        try writer.close()
        print(path)
        return 0
    }
}

// MARK: - 명령행 인자

struct Arguments {
    private var items: [String]

    init(_ items: [String]) {
        self.items = items
    }

    mutating func command() -> String? {
        items.isEmpty ? nil : items.removeFirst()
    }

    mutating func flag(_ name: String) -> Bool {
        guard let index = items.firstIndex(of: name) else { return false }
        items.remove(at: index)
        return true
    }

    mutating func value(_ name: String) throws -> String? {
        guard let index = items.firstIndex(of: name) else { return nil }
        guard index + 1 < items.count else { throw ToolError(message: "\(name) 뒤에 값이 필요함", code: 64) }
        let value = items[index + 1]
        items.removeSubrange(index...(index + 1))
        return value
    }

    mutating func requiredValue(_ name: String) throws -> String {
        guard let value = try value(name) else { throw ToolError(message: "\(name)가 필요함", code: 64) }
        return value
    }

    mutating func number(_ name: String) throws -> Double? {
        guard let text = try value(name) else { return nil }
        guard let number = Double(text), number.isFinite else { throw ToolError(message: "\(name) 값이 수가 아님: \(text)", code: 64) }
        return number
    }

    mutating func repeats() throws -> Int {
        guard let value = try number("--repeat") else { return 3 }
        guard value == value.rounded(), (1...10).contains(value) else {
            throw ToolError(message: "--repeat는 1~10 정수여야 함", code: 64)
        }
        return Int(value)
    }

    /// --quick이면 앉은 채 유지, 일어서기와 앉기, 걷다 바로 앉기만 하는 짧은 순서를 씀.
    mutating func steps() throws -> [ProtocolStep] {
        let quick = flag("--quick")
        let repeats = try repeats()
        return quick ? ProtocolStep.quick(repeats: repeats) : ProtocolStep.standard(repeats: repeats)
    }

    mutating func positional() -> String? {
        guard let index = items.firstIndex(where: { !$0.hasPrefix("--") }) else { return nil }
        return items.remove(at: index)
    }

    func finish() throws {
        guard items.isEmpty else { throw ToolError(message: "알 수 없는 인자: \(items.joined(separator: " "))", code: 64) }
    }
}

// MARK: - 기록 파일

/// 새 파일만 만들어 씀. 이미 있는 파일을 덮어쓰지 않고, 머리 움직임 원시값이라 소유자만 읽게 함.
final class RowWriter {
    private let handle: FileHandle
    private var buffer: String

    private init(handle: FileHandle) {
        self.handle = handle
        buffer = RecordFormat.magic + "\n" + RecordFormat.columns + "\n"
    }

    static func create(path: String) throws -> RowWriter {
        let descriptor = Darwin.open(path, O_WRONLY | O_CREAT | O_EXCL, 0o600)
        guard descriptor >= 0 else {
            let reason = errno == EEXIST ? "이미 있는 파일은 덮어쓰지 않음" : String(cString: strerror(errno))
            throw ToolError(message: "기록 파일을 만들 수 없음: \(path) (\(reason))", code: 73)
        }
        return RowWriter(handle: FileHandle(fileDescriptor: descriptor, closeOnDealloc: true))
    }

    func append(_ row: RecordedRow) {
        buffer += RecordFormat.line(row) + "\n"
    }

    func flush() throws {
        try handle.write(contentsOf: Data(buffer.utf8))
        buffer = ""
    }

    func close() throws {
        try flush()
        try handle.close()
    }
}

// MARK: - 기록

@MainActor
final class Recorder {
    private static let leadIn = 3.0
    private static let silenceNotice = 1.0
    /// 이 간격마다 파일에 씀. 창을 닫거나 강제 종료해도 그때까지의 기록이 남게 함.
    private static let flushInterval = 1.0
    /// 안내 음성이 이 시간 안에 끝나지 않으면 기다리지 않고 단계를 시작함.
    private static let speechLimit = 10.0

    private let path: String
    private let steps: [ProtocolStep]
    private let voice: String?
    private let waitLimit: Double
    /// AirPods 대신 합성 기록을 실제 시간에 맞춰 넣음. 기록 경로를 AirPods 없이 점검하는 용도임.
    private let simulation: [RecordedRow]?
    private var simulationStart: Double?
    private var simulationCursor = 0
    private let motion = CMHeadphoneMotionManager()
    private let activity = CMHeadphoneActivityManager()
    private let queue: OperationQueue = {
        let queue = OperationQueue()
        queue.name = "Seat recorder input"
        queue.maxConcurrentOperationCount = 1
        return queue
    }()
    private var writer: RowWriter?
    private var analyzer = SeatAnalyzer()
    /// 입력 대기 시작 시각임. 처음 실행의 동작 접근 허용 창이 떠 있는 동안은 대기 시간에 넣지 않음.
    private var waitingSince = ProcessInfo.processInfo.systemUptime
    private var lastFlush = 0.0
    /// -1은 시작 전 준비 구간임.
    private var stepIndex = -1
    private var stepEndsAt = Double.infinity
    private var lastMotion: Double?
    private var silent = false
    private var timer: Timer?
    private var interruptions: [DispatchSourceSignal] = []
    private var speaker: Process?
    /// 끝난 음성이 지금 음성인지 가리는 번호임. 앞 음성을 끊을 때 온 종료 알림을 무시함.
    private var speechToken = 0
    /// 안내 음성이 끝나기를 기다리기 시작한 시각임. 단계 행과 단계 시간은 음성이 끝난 뒤부터임.
    private var speechWaitSince: Double?
    private var exitCode: Int32?

    private init(path: String, steps: [ProtocolStep], voice: String?, waitLimit: Double, simulation: [RecordedRow]?) {
        self.path = path
        self.steps = steps
        self.voice = voice
        self.waitLimit = waitLimit
        self.simulation = simulation
    }

    static func run(_ arguments: inout Arguments) throws -> Int32 {
        let path = try arguments.requiredValue("--out")
        let steps = try arguments.steps()
        let quiet = arguments.flag("--no-voice")
        let waitLimit = try arguments.number("--wait") ?? 20
        let simulate = arguments.flag("--simulate")
        try arguments.finish()
        guard waitLimit > 0 else { throw ToolError(message: "--wait는 0보다 커야 함", code: 64) }
        // AirPods를 켜기 전에 파일 조건을 먼저 확인해 덮어쓰기와 잘못된 경로를 바로 알림.
        let url = URL(fileURLWithPath: path)
        guard !FileManager.default.fileExists(atPath: url.path) else {
            throw ToolError(message: "이미 있는 파일은 덮어쓰지 않음: \(path)", code: 64)
        }
        var directory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.deletingLastPathComponent().path, isDirectory: &directory),
              directory.boolValue else {
            throw ToolError(message: "기록 파일의 폴더가 없음: \(url.deletingLastPathComponent().path)", code: 64)
        }
        let recorder = Recorder(path: path, steps: steps,
                                voice: quiet ? nil : koreanVoice(), waitLimit: waitLimit,
                                simulation: simulate ? SyntheticRecording.make(steps: steps) : nil)
        try recorder.start()
        while recorder.exitCode == nil {
            RunLoop.main.run(mode: .default, before: .distantFuture)
        }
        return recorder.exitCode ?? 1
    }

    private func start() throws {
        if simulation == nil {
            let status = CMHeadphoneMotionManager.authorizationStatus()
            guard status != .denied && status != .restricted else {
                throw ToolError(message: "동작 접근이 거절됨. 시스템 설정의 개인정보 보호에서 이 터미널의 동작 및 피트니스 접근을 확인해 주세요.", code: 77)
            }
            guard motion.isDeviceMotionAvailable else {
                throw ToolError(message: "이 Mac에서 AirPods 동작 입력을 쓸 수 없음", code: 69)
            }
        }
        let total = steps.reduce(Self.leadIn) { $0 + $1.seconds }
        print("단계 \(steps.count)개, 안내 음성을 빼고 약 \(Int(total.rounded()))초. AirPods를 끼고 의자에 앉아 화면 정면을 보세요.")
        print("안내 음성에 따라 움직이세요. Ctrl+C로 멈추면 그때까지의 기록과 결과를 남김.")
        print("AirPods 동작 입력을 기다림. 최대 \(Int(waitLimit))초")
        if simulation == nil, CMHeadphoneMotionManager.authorizationStatus() == .notDetermined {
            print("처음 실행이면 동작 접근 허용 창이 뜸. 허용한 뒤부터 대기 시간을 셈")
        }
        if simulation == nil {
            motion.startDeviceMotionUpdates(to: queue, withHandler: Self.motionHandler(self))
        } else {
            print("합성 입력으로 기록 경로를 점검함. 실제 AirPods 측정이 아님")
        }
        let timer = Timer(timeInterval: 0.05, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        RunLoop.main.add(timer, forMode: .default)
        self.timer = timer
        // Ctrl+C, 터미널 창 닫기, kill 모두 그때까지의 기록을 닫고 보고를 냄.
        for number in [SIGINT, SIGHUP, SIGTERM] {
            signal(number, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: number, queue: .main)
            source.setEventHandler { [weak self] in
                MainActor.assumeIsolated { self?.interrupt() }
            }
            source.resume()
            interruptions.append(source)
        }
    }

    /// Core Motion은 별도 큐에서 부름. 값만 꺼내 main queue 순서대로 넘겨 기록 행 순서와 처리 순서를 같게 함.
    nonisolated private static func motionHandler(_ recorder: Recorder) -> @Sendable (CMDeviceMotion?, (any Error)?) -> Void {
        { @Sendable motion, error in
            if let error {
                let message = error.localizedDescription
                DispatchQueue.main.async { MainActor.assumeIsolated { recorder.inputFailed(message) } }
                return
            }
            guard let motion else { return }
            let timestamp = motion.timestamp
            let acceleration = SIMD3(motion.userAcceleration.x, motion.userAcceleration.y, motion.userAcceleration.z)
            let gravity = SIMD3(motion.gravity.x, motion.gravity.y, motion.gravity.z)
            let source = motion.sensorLocation.rawValue
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    recorder.receiveMotion(timestamp: timestamp, acceleration: acceleration, gravity: gravity, source: source)
                }
            }
        }
    }

    nonisolated private static func activityHandler(_ recorder: Recorder) -> @Sendable (CMMotionActivity?, (any Error)?) -> Void {
        { @Sendable activity, error in
            guard error == nil, let activity else { return }
            let named: [(String, Bool)] = [("walking", activity.walking), ("running", activity.running),
                                           ("stationary", activity.stationary), ("automotive", activity.automotive),
                                           ("unknown", activity.unknown)]
            let kinds = named.filter(\.1).map(\.0)
            let confidence = activity.confidence.rawValue
            let timestamp = activity.timestamp
            DispatchQueue.main.async {
                MainActor.assumeIsolated { recorder.receiveActivity(timestamp: timestamp, kinds: kinds, confidence: confidence) }
            }
        }
    }

    private func receiveMotion(timestamp: Double, acceleration: SIMD3<Double>, gravity: SIMD3<Double>, source: Int) {
        guard exitCode == nil else { return }
        let now = ProcessInfo.processInfo.systemUptime
        if writer == nil {
            do {
                writer = try RowWriter.create(path: path)
            } catch let error as ToolError {
                print(error.message)
                stop(code: error.code)
                return
            } catch {
                stop(code: 73)
                return
            }
            print("입력 확인. \(Int(Self.leadIn))초 뒤 시작함. 기록 파일: \(path)")
            append { .step(rx: $0, id: "ready", expectation: .none) }
            stepEndsAt = now + Self.leadIn
            startActivity()
            speak("\(Int(Self.leadIn))초 뒤 시작합니다")
        }
        if silent {
            silent = false
            print("    입력 다시 들어옴")
        }
        lastMotion = now
        append { .motion(rx: $0, t: timestamp, acceleration: acceleration, gravity: gravity, source: source) }
    }

    private func receiveActivity(timestamp: Double, kinds: [String], confidence: Int) {
        guard exitCode == nil, writer != nil else { return }
        append { .activity(rx: $0, t: timestamp, kinds: kinds, confidence: confidence) }
    }

    /// 걷기 판정은 보조 입력이라 쓸 수 없어도 움직임 기록은 이어감.
    private func startActivity() {
        guard simulation == nil else { return }
        let status = CMHeadphoneActivityManager.authorizationStatus()
        guard status != .denied && status != .restricted, activity.isActivityAvailable else {
            print("걷기 판정을 쓸 수 없어 움직임만 기록함")
            return
        }
        activity.startActivityUpdates(to: queue, withHandler: Self.activityHandler(self))
    }

    private func inputFailed(_ message: String) {
        guard exitCode == nil else { return }
        guard writer != nil else {
            print("AirPods 동작 입력 오류: \(message). 파일은 만들지 않음")
            stop(code: 69)
            return
        }
        print("    입력 오류: \(message)")
    }

    private func tick() {
        guard exitCode == nil else { return }
        let now = ProcessInfo.processInfo.systemUptime
        if simulation != nil { feedSimulation(until: now) }
        guard writer != nil else {
            if simulation == nil {
                switch CMHeadphoneMotionManager.authorizationStatus() {
                case .notDetermined:
                    waitingSince = now
                    return
                case .denied, .restricted:
                    print("동작 접근이 거절됨. 시스템 설정의 개인정보 보호에서 이 터미널의 동작 및 피트니스 접근을 확인해 주세요. 파일은 만들지 않음")
                    stop(code: 77)
                    return
                default:
                    break
                }
            }
            if now - waitingSince > waitLimit {
                print("AirPods 동작 입력이 \(Int(waitLimit))초 동안 오지 않음. AirPods를 귀에 끼고 이 Mac에 연결했는지 확인해 주세요. 파일은 만들지 않음")
                stop(code: 69)
            }
            return
        }
        if let lastMotion, now - lastMotion > Self.silenceNotice, !silent {
            silent = true
            print("    입력 끊김. AirPods 착용과 연결을 확인해 주세요")
        }
        if let since = speechWaitSince, now - since > Self.speechLimit { beginStep(at: now) }
        if now >= stepEndsAt { nextStep(at: now) }
        if exitCode == nil, now - lastFlush >= Self.flushInterval {
            lastFlush = now
            do {
                try writer?.flush()
            } catch {
                print("기록 파일에 쓰지 못해 멈춤: \(error.localizedDescription)")
                stop(code: 74)
            }
        }
    }

    /// 합성 기록의 단계 행은 버리고 움직임과 걷기 판정만 원래 간격대로 넣음. 단계는 실제 기록처럼 이 도구의 시계가 정함.
    private func feedSimulation(until now: Double) {
        guard let rows = simulation, let first = rows.first else { return }
        let start = simulationStart ?? now
        simulationStart = start
        let elapsed = now - start
        while let row = simulationCursor < rows.count ? rows[simulationCursor] : nil, row.rx - first.rx <= elapsed {
            simulationCursor += 1
            switch row {
            case let .motion(rx, _, acceleration, gravity, source):
                receiveMotion(timestamp: start + rx - first.rx, acceleration: acceleration, gravity: gravity, source: source)
            case let .activity(rx, _, kinds, confidence):
                receiveActivity(timestamp: start + rx - first.rx, kinds: kinds, confidence: confidence)
            case .step:
                break
            }
        }
    }

    private func nextStep(at now: Double) {
        stepIndex += 1
        guard stepIndex < steps.count else {
            append { .step(rx: $0, id: "end", expectation: .none) }
            complete(code: 0)
            return
        }
        let step = steps[stepIndex]
        print("[\(stepIndex + 1)/\(steps.count)] \(step.id) \(Int(step.seconds))초: \(step.instruction)")
        stepEndsAt = .infinity
        // 1차 실측에서 음성이 나오는 3초 가까이를 단계 시간에 넣어 움직임이 다음 단계로 밀렸음.
        // 합성 입력은 단계 시각이 정해져 있으므로 음성을 기다리지 않음.
        if speak(step.instruction), simulation == nil {
            speechWaitSince = now
        } else {
            beginStep(at: now)
        }
    }

    /// 단계 행을 쓰고 그때부터 단계 시간을 셈. replay의 단계 구간도 이 시각부터임.
    private func beginStep(at now: Double) {
        speechWaitSince = nil
        let step = steps[stepIndex]
        stepEndsAt = now + step.seconds
        append { .step(rx: $0, id: step.id, expectation: step.expectation) }
    }

    private func speechEnded(_ token: Int) {
        guard exitCode == nil, token == speechToken, speechWaitSince != nil else { return }
        beginStep(at: ProcessInfo.processInfo.systemUptime)
    }

    /// 받은 시각(rx)은 쓰는 순간에 읽음. 한 주기 안에서 먼저 읽은 시각으로 늦게 쓰면 파일의 rx가 거꾸로 가 replay가 거부함.
    private func append(_ make: (Double) -> RecordedRow) {
        let row = make(ProcessInfo.processInfo.systemUptime)
        writer?.append(row)
        for note in analyzer.handle(row) {
            let height = note.text == "일어섬" || note.text == "앉음" ? " (높이 \(ReportText.centimeters(analyzer.measuredLevel)))" : ""
            print("    \(ReportText.fixed(note.at, 1))초 \(note.text)\(height)")
        }
    }

    private func interrupt() {
        guard exitCode == nil else { return }
        guard writer != nil else {
            print("기록 전에 멈춤. 파일은 만들지 않음")
            stop(code: 130)
            return
        }
        print("멈춤. 지금 단계는 끝까지 하지 않았으므로 그 판정은 참고만 함")
        append { .step(rx: $0, id: "interrupted", expectation: .none) }
        complete(code: 130)
    }

    private func complete(code: Int32) {
        let end = ProcessInfo.processInfo.systemUptime
        stopInputs()
        do {
            try writer?.close()
        } catch {
            print("기록 파일을 끝까지 쓰지 못함: \(error.localizedDescription)")
            exitCode = 74
            return
        }
        print("")
        print(ReportText.render(analyzer.finish(at: end), source: path))
        print("")
        print("이 파일에는 AirPods 머리 움직임 원시값이 있음. 도구는 파일을 지우지 않으므로 기록 전에 정한 보관 방식대로 처리해 주세요")
        exitCode = code
    }

    private func stop(code: Int32) {
        stopInputs()
        exitCode = code
    }

    private func stopInputs() {
        motion.stopDeviceMotionUpdates()
        activity.stopActivityUpdates()
        timer?.invalidate()
        interruptions.forEach { $0.cancel() }
        speaker?.terminate()
    }

    /// 음성을 시작했으면 true임. 끝나면 speechEnded로 알림.
    @discardableResult
    private func speak(_ text: String) -> Bool {
        guard let voice else { return false }
        speaker?.terminate()
        speechToken += 1
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/say")
        process.arguments = ["-v", voice, text]
        process.terminationHandler = Self.speechHandler(self, token: speechToken)
        guard (try? process.run()) != nil else {
            speaker = nil
            return false
        }
        speaker = process
        return true
    }

    /// say 종료 알림은 별도 스레드에서 옴. main queue로 넘겨 단계 처리와 순서를 맞춤.
    nonisolated private static func speechHandler(_ recorder: Recorder, token: Int) -> @Sendable (Process) -> Void {
        { @Sendable _ in
            DispatchQueue.main.async { MainActor.assumeIsolated { recorder.speechEnded(token) } }
        }
    }

    /// 설치된 한국어 음성을 고름. 없으면 안내를 화면에만 씀.
    private static func koreanVoice() -> String? {
        let process = Process()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/say")
        process.arguments = ["-v", "?"]
        process.standardOutput = output
        guard (try? process.run()) != nil else { return nil }
        let text = String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        process.waitUntilExit()
        let names = text.split(separator: "\n").compactMap { line -> String? in
            guard let range = line.range(of: " ko_KR") else { return nil }
            return line[..<range.lowerBound].trimmingCharacters(in: .whitespaces)
        }
        return names.first { $0.hasPrefix("Yuna") }.map { _ in "Yuna" } ?? names.first
    }
}
