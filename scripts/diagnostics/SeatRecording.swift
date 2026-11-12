import Foundation
import PrivacyCore

// 자리 이탈 실측 기록의 형식, 앱 규칙 재현, 단계별 보고, 합성 기록을 둠. CoreMotion을 쓰지 않아 AirPods 없이 시험할 수 있음.

// MARK: - 기록 형식

/// 단계가 끝났을 때 앱이 보여야 할 상태임. 기록 파일의 단계 행에 함께 적어 보고가 단계 이름에 기대지 않게 함.
enum StepExpectation: String, Codable {
    /// 평가하지 않는 준비 구간임.
    case none
    /// 앉은 채 움직임. 자리 비움이 생기면 잘못 가림임.
    case stay
    /// 일어서거나 걸어 나감. 단계 안에 자리 비움이 되어야 함.
    case leave
    /// 다시 앉음. 단계 끝에 자리 비움이 풀려 있어야 함.
    case back
    /// 걸어 나갔다가 멈추지 않고 앉음. 단계 안에 자리 비움이 되고 끝에는 풀려 있어야 함.
    case leaveThenBack = "leave-back"

    var label: String {
        switch self {
        case .none: "평가 안 함"
        case .stay: "앉은 채 유지"
        case .leave: "자리 비움"
        case .back: "다시 앉음"
        case .leaveThenBack: "비움 뒤 앉음"
        }
    }
}

enum RecordedRow: Equatable {
    /// rx는 앱이 표본을 받은 시각(systemUptime), t는 센서 시각임. 앱 규칙은 rx, 자세 판정은 t를 씀.
    case motion(rx: Double, t: Double, acceleration: SIMD3<Double>, gravity: SIMD3<Double>, source: Int)
    /// kinds는 CMMotionActivity의 참인 항목 이름, confidence는 0(낮음)~2(높음)임.
    case activity(rx: Double, t: Double, kinds: [String], confidence: Int)
    /// 단계 시작 표시임. 다음 단계 행이 앞 단계의 끝임.
    case step(rx: Double, id: String, expectation: StepExpectation)

    var rx: Double {
        switch self {
        case .motion(let rx, _, _, _, _), .activity(let rx, _, _, _), .step(let rx, _, _): rx
        }
    }
}

struct ToolError: Error {
    let message: String
    /// sysexits 관례를 따름. 64 인자, 65 기록 형식, 69 입력 없음, 77 권한, 73 파일 생성 실패임.
    let code: Int32
}

enum RecordFormat {
    static let magic = "# seat-recorder 1"
    static let columns = "kind,rx,t,ax,ay,az,gx,gy,gz,src,activity,confidence,step,expect"

    static func line(_ row: RecordedRow) -> String {
        switch row {
        case let .motion(rx, t, a, g, source):
            return "m,\(rx),\(t),\(a.x),\(a.y),\(a.z),\(g.x),\(g.y),\(g.z),\(source),,,,"
        case let .activity(rx, t, kinds, confidence):
            let joined = kinds.isEmpty ? "none" : kinds.joined(separator: "+")
            return "a,\(rx),\(t),,,,,,,,\(joined),\(confidence),,"
        case let .step(rx, id, expectation):
            return "s,\(rx),,,,,,,,,,,\(id),\(expectation.rawValue)"
        }
    }

    static func parse(_ text: String) throws -> [RecordedRow] {
        var lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        if lines.last == "" { lines.removeLast() }
        guard lines.count >= 2, lines[0] == magic, lines[1] == columns else {
            throw ToolError(message: "seat-recorder 기록 파일이 아님. 첫 두 줄이 형식 표시와 열 이름이어야 함", code: 65)
        }
        var rows: [RecordedRow] = []
        var lastRx = -Double.infinity
        for (index, line) in lines.enumerated().dropFirst(2) {
            let row = try parseRow(line, lineNumber: index + 1)
            guard row.rx >= lastRx else {
                throw ToolError(message: "\(index + 1)번째 줄: rx가 앞 줄보다 이름", code: 65)
            }
            lastRx = row.rx
            rows.append(row)
        }
        return rows
    }

    private static func parseRow(_ line: String, lineNumber: Int) throws -> RecordedRow {
        let fields = line.split(separator: ",", omittingEmptySubsequences: false).map(String.init)
        func fail(_ reason: String) -> ToolError {
            ToolError(message: "\(lineNumber)번째 줄: \(reason)", code: 65)
        }
        guard fields.count == 14 else { throw fail("열이 14개가 아님") }
        func number(_ index: Int) throws -> Double {
            guard let value = Double(fields[index]), value.isFinite else { throw fail("\(index + 1)번째 열이 유한한 수가 아님") }
            return value
        }
        let rx = try number(1)
        switch fields[0] {
        case "m":
            guard let source = Int(fields[9]) else { throw fail("src가 정수가 아님") }
            return .motion(rx: rx, t: try number(2),
                           acceleration: SIMD3(try number(3), try number(4), try number(5)),
                           gravity: SIMD3(try number(6), try number(7), try number(8)), source: source)
        case "a":
            guard let confidence = Int(fields[11]), (0...2).contains(confidence) else { throw fail("confidence가 0~2가 아님") }
            let kinds = fields[10] == "none" ? [] : fields[10].split(separator: "+").map(String.init)
            return .activity(rx: rx, t: try number(2), kinds: kinds, confidence: confidence)
        case "s":
            guard isStepID(fields[12]) else { throw fail("단계 이름은 소문자, 숫자, -만 씀") }
            guard let expectation = StepExpectation(rawValue: fields[13]) else { throw fail("알 수 없는 기대값") }
            return .step(rx: rx, id: fields[12], expectation: expectation)
        default:
            throw fail("알 수 없는 행 종류")
        }
    }

    static func isStepID(_ id: String) -> Bool {
        !id.isEmpty && id.unicodeScalars.allSatisfy { ("a"..."z").contains($0) || ("0"..."9").contains($0) || $0 == "-" }
    }
}

// MARK: - 앱 규칙 재현

/// AppModel의 자리 비움 규칙(receiveActivity, trackPosture, advanceAway, resumeProtection)을 시간 입력만 바꿔 옮긴 것임.
/// AppModel의 규칙이나 AwayTiming 값이 바뀌면 여기도 맞춰야 함. 보호, 입력 중단, 스위치 상태는 기록 중 늘 켜진 것으로 봄.
struct AwayRule {
    struct Timing: Equatable, Codable {
        var standingDelay = 3.0
        var returnSettle = 3.0
    }

    enum Change: Equatable {
        case stoodUp
        case satDown
        case away(walking: Bool)
        case back
    }

    private(set) var presence: SeatPresence
    private(set) var away = false
    /// 마지막 움직임 표본을 넣은 직후의 level임. 앉아서 돌아올 때 앱 규칙이 level을 0으로 되돌리기 전 값이라 실제 높이 변화를 잴 때 씀.
    private(set) var measuredLevel = 0.0
    let timing: Timing
    private var standingSince: Double?
    private var movingIgnoredUntil = -Double.infinity

    init(tuning: SeatPresence.Tuning, timing: Timing) {
        presence = SeatPresence(tuning: tuning)
        presence.reset(to: .seated)
        self.timing = timing
    }

    /// 앱의 매 주기 확인에 해당함. 기록 행마다 부르므로 판정 시각 오차는 표본 간격 이내임.
    mutating func advance(to now: Double) -> Change? {
        guard !away, let since = standingSince, now - since >= timing.standingDelay else { return nil }
        enterAway()
        return .away(walking: false)
    }

    mutating func motion(now: Double, timestamp: Double, acceleration: SIMD3<Double>, gravity: SIMD3<Double>) -> [Change] {
        var changes = advance(to: now).map { [$0] } ?? []
        let event = presence.ingest(timestamp: timestamp, acceleration: acceleration, gravity: gravity)
        measuredLevel = presence.level
        switch event {
        case .stoodUp:
            changes.append(.stoodUp)
            if !away { standingSince = now }
        case .satDown:
            changes.append(.satDown)
            standingSince = nil
            if away {
                away = false
                movingIgnoredUntil = now + timing.returnSettle
                presence.reset(to: .seated)
                changes.append(.back)
            }
        case nil:
            break
        }
        return changes
    }

    mutating func activity(now: Double, moving: Bool) -> [Change] {
        var changes = advance(to: now).map { [$0] } ?? []
        guard moving, !away, now >= movingIgnoredUntil else { return changes }
        presence.reset(to: .standing)
        enterAway()
        changes.append(.away(walking: true))
        return changes
    }

    private mutating func enterAway() {
        away = true
        standingSince = nil
    }

    /// HeadActivity.classify와 같은 기준임. 중간 신뢰도 이상의 걷기나 달리기만 움직임으로 봄.
    static func isMoving(kinds: [String], confidence: Int) -> Bool {
        confidence >= 1 && (kinds.contains("walking") || kinds.contains("running"))
    }
}

// MARK: - 단계별 분석

enum StepVerdict: String, Codable {
    case ok
    case missed
    case falseCover = "false-cover"
    case stuck
    case notApplicable = "not-applicable"
    case unchecked

    var label: String {
        switch self {
        case .ok: "맞음"
        case .missed: "놓침"
        case .falseCover: "잘못 가림"
        case .stuck: "못 돌아옴"
        case .notApplicable: "해당 없음"
        case .unchecked: "평가 안 함"
        }
    }
}

struct StepEvent: Codable, Equatable {
    let kind: String
    /// 단계 시작부터 지난 초임. 안내를 듣고 움직이기까지의 반응 시간을 포함함.
    let at: Double
}

struct StepReport: Codable {
    let id: String
    let expectation: StepExpectation
    let seconds: Double
    let verdict: StepVerdict
    /// 단계 시작부터 자리 비움이 되기까지의 초임.
    let awayAfter: Double?
    /// 단계 시작부터 자리 비움이 풀리기까지의 초임.
    let backAfter: Double?
    /// 앉은 자세 기준 머리 높이 추정치의 단계 안 최고, 최저임. m 단위임.
    let maxLevel: Double?
    let minLevel: Double?
    /// 움직임 구간이 끝날 때 반영된 높이 변화임. m 단위이며 0.5cm 미만은 뺌.
    let heightChanges: [Double]
    let events: [StepEvent]
    let motionSamples: Int
}

struct DataQuality: Codable {
    let motionSamples: Int
    let seconds: Double
    let rate: Double
    /// SeatPresence가 구간을 버리는 간격(maximumGap)을 넘은 표본 간격 수임.
    let gaps: Int
    let longestGap: Double
    let activityRows: Int
    /// 센서 시각이 앞 표본보다 앞서지 않아 버린 표본 수임. AppModel.receive도 판정에 넣지 않음.
    let droppedSamples: Int
    /// 표본의 이어버드가 바뀐 횟수임. 앱은 이때 입력 중단으로 보고 보정을 다시 요구하지만 replay는 판정을 이어감.
    let sourceChanges: Int
    /// 받은 시각이 센서 시각보다 0.75초 넘게 늦거나 앞선 표본 수임. 앱은 이런 표본을 입력 중단으로 봄.
    let lateSamples: Int
}

struct ReplayReport: Codable {
    let tuning: [String: Double]
    let timing: AwayRule.Timing
    let data: DataQuality
    let steps: [StepReport]
    let counts: [String: Int]
}

/// 기록 행을 차례로 받아 앱 규칙을 돌리고 단계별 결과를 모음. 기록 중 실시간 표시와 replay가 같은 경로를 씀.
struct SeatAnalyzer {
    struct Note {
        let step: String
        let at: Double
        let text: String
    }

    private struct OpenStep {
        let id: String
        let expectation: StepExpectation
        let start: Double
        let awayAtStart: Bool
        var firstAway: Double?
        var firstBack: Double?
        var maxLevel: Double?
        var minLevel: Double?
        var heightChanges: [Double] = []
        var events: [StepEvent] = []
        var motionSamples = 0
    }

    private var rule: AwayRule
    private let tuning: SeatPresence.Tuning
    private var open: OpenStep?
    private var reports: [StepReport] = []
    private var motionSamples = 0
    private var firstMotion: Double?
    private var lastMotion: Double?
    private var gaps = 0
    private var longestGap = 0.0
    private var activityRows = 0
    private var lastTimestamp: Double?
    private var lastSource: Int?
    private var droppedSamples = 0
    private var sourceChanges = 0
    private var lateSamples = 0

    init(tuning: SeatPresence.Tuning = .init(), timing: AwayRule.Timing = .init()) {
        self.tuning = tuning
        rule = AwayRule(tuning: tuning, timing: timing)
    }

    var away: Bool { rule.away }
    /// 마지막 움직임 표본 직후의 높이 추정치임. 앱 규칙이 되돌리기 전 값임.
    var measuredLevel: Double { rule.measuredLevel }

    mutating func handle(_ row: RecordedRow) -> [Note] {
        switch row {
        case let .step(rx, id, expectation):
            let due = rule.advance(to: rx).map { [$0] } ?? []
            let notes = record(due, at: rx)
            close(at: rx)
            open = OpenStep(id: id, expectation: expectation, start: rx, awayAtStart: rule.away)
            return notes
        case let .motion(rx, t, acceleration, gravity, source):
            trackGap(rx)
            if let lastSource, source != lastSource { sourceChanges += 1 }
            lastSource = source
            if rx - t > 0.75 || rx < t { lateSamples += 1 }
            // AppModel.receive처럼 센서 시각이 앞서지 않는 표본은 판정에 넣지 않음.
            if let lastTimestamp, t <= lastTimestamp {
                droppedSamples += 1
                return []
            }
            lastTimestamp = t
            let before = rule.presence.level
            let changes = rule.motion(now: rx, timestamp: t, acceleration: acceleration, gravity: gravity)
            let measured = rule.measuredLevel
            // 구간 끝에서만 level이 크게 바뀜. 정지 중 되돌림은 표본당 1mm 미만이라 0.5cm 기준으로 가름.
            if var current = open {
                if abs(measured - before) >= 0.005 { current.heightChanges.append(measured - before) }
                current.motionSamples += 1
                current.maxLevel = max(current.maxLevel ?? measured, measured)
                current.minLevel = min(current.minLevel ?? measured, measured)
                open = current
            }
            return record(changes, at: rx)
        case let .activity(rx, _, kinds, confidence):
            activityRows += 1
            let moving = AwayRule.isMoving(kinds: kinds, confidence: confidence)
            // 걷기 판정이 늦게 오는지 보려고 자리 비움과 별개로 남김.
            let seen = moving ? note("걷기 판정", at: rx) : []
            return seen + record(rule.activity(now: rx, moving: moving), at: rx)
        }
    }

    /// 마지막 단계를 끝내고 보고를 만듦. 기록 끝 시각까지 주기 확인을 한 번 더 돌림.
    mutating func finish(at end: Double) -> ReplayReport {
        _ = record(rule.advance(to: end).map { [$0] } ?? [], at: end)
        close(at: end)
        let seconds = (lastMotion ?? 0) - (firstMotion ?? 0)
        let quality = DataQuality(motionSamples: motionSamples, seconds: seconds,
                                  rate: seconds > 0 ? Double(motionSamples - 1) / seconds : 0,
                                  gaps: gaps, longestGap: longestGap, activityRows: activityRows,
                                  droppedSamples: droppedSamples, sourceChanges: sourceChanges, lateSamples: lateSamples)
        var counts: [String: Int] = [:]
        for report in reports where report.verdict != .unchecked { counts[report.verdict.rawValue, default: 0] += 1 }
        return ReplayReport(tuning: Self.describe(tuning), timing: rule.timing, data: quality, steps: reports, counts: counts)
    }

    private mutating func trackGap(_ rx: Double) {
        motionSamples += 1
        if firstMotion == nil { firstMotion = rx }
        if let lastMotion {
            let gap = rx - lastMotion
            longestGap = max(longestGap, gap)
            if gap > tuning.maximumGap { gaps += 1 }
        }
        lastMotion = rx
    }

    private mutating func note(_ kind: String, at rx: Double) -> [Note] {
        guard let current = open else { return [] }
        let at = rx - current.start
        open?.events.append(StepEvent(kind: kind, at: at))
        return [Note(step: current.id, at: at, text: kind)]
    }

    private mutating func record(_ changes: [AwayRule.Change], at rx: Double) -> [Note] {
        guard var current = open else { return [] }
        var notes: [Note] = []
        for change in changes {
            let at = rx - current.start
            let kind: String
            switch change {
            case .stoodUp:
                kind = "일어섬"
            case .satDown:
                kind = "앉음"
            case .away(let walking):
                kind = walking ? "자리 비움(걷기)" : "자리 비움(일어선 뒤)"
                current.firstAway = current.firstAway ?? at
            case .back:
                kind = "돌아옴"
                current.firstBack = current.firstBack ?? at
            }
            current.events.append(StepEvent(kind: kind, at: at))
            notes.append(Note(step: current.id, at: at, text: kind))
        }
        open = current
        return notes
    }

    private mutating func close(at end: Double) {
        guard let step = open else { return }
        open = nil
        let awayAtEnd = rule.away
        let verdict: StepVerdict
        switch step.expectation {
        case .none:
            verdict = .unchecked
        case .stay:
            verdict = step.awayAtStart ? .notApplicable : (step.firstAway == nil ? .ok : .falseCover)
        case .leave:
            verdict = step.awayAtStart ? .notApplicable : (step.firstAway == nil ? .missed : .ok)
        case .back:
            verdict = awayAtEnd ? .stuck : (step.awayAtStart ? .ok : .notApplicable)
        case .leaveThenBack:
            verdict = step.awayAtStart ? .notApplicable
                : step.firstAway == nil ? .missed
                : awayAtEnd ? .stuck : .ok
        }
        reports.append(StepReport(id: step.id, expectation: step.expectation, seconds: end - step.start,
                                  verdict: verdict, awayAfter: step.firstAway, backAfter: step.firstBack,
                                  maxLevel: step.maxLevel, minLevel: step.minLevel,
                                  heightChanges: step.heightChanges, events: step.events,
                                  motionSamples: step.motionSamples))
    }

    static func describe(_ tuning: SeatPresence.Tuning) -> [String: Double] {
        Dictionary(uniqueKeysWithValues: TuningFlag.all.map { ($0.name, tuning[keyPath: $0.path]) })
    }
}

/// replay에서 바꿀 수 있는 SeatPresence 기준값과 명령행 이름임.
struct TuningFlag {
    let flag: String
    let name: String
    let path: WritableKeyPath<SeatPresence.Tuning, Double>

    static var all: [TuningFlag] {
        [TuningFlag(flag: "--still-acceleration", name: "stillAcceleration", path: \.stillAcceleration),
         TuningFlag(flag: "--still-duration", name: "stillDuration", path: \.stillDuration),
         TuningFlag(flag: "--max-segment", name: "maximumSegment", path: \.maximumSegment),
         TuningFlag(flag: "--max-gap", name: "maximumGap", path: \.maximumGap),
         TuningFlag(flag: "--stand-level", name: "standLevel", path: \.standLevel),
         TuningFlag(flag: "--sit-level", name: "sitLevel", path: \.sitLevel),
         TuningFlag(flag: "--settled-velocity", name: "settledVelocity", path: \.settledVelocity),
         TuningFlag(flag: "--forced-still", name: "forcedStillDuration", path: \.forcedStillDuration),
         TuningFlag(flag: "--relax-time", name: "relaxTime", path: \.relaxTime)]
    }
}

// MARK: - 보고 출력

enum ReportText {
    static func render(_ report: ReplayReport, source: String) -> String {
        var lines: [String] = []
        let data = report.data
        lines.append("기록 \(source): 표본 \(data.motionSamples)개, \(fixed(data.rate, 1))Hz, \(fixed(data.seconds, 1))초, "
                     + "\(fixed(report.tuning["maximumGap"] ?? 0, 2))초 넘는 끊김 \(data.gaps)번(최장 \(fixed(data.longestGap, 2))초), 걷기 판정 행 \(data.activityRows)개")
        if data.droppedSamples + data.sourceChanges + data.lateSamples > 0 {
            lines.append("입력 주의: 센서 시각이 앞서지 않아 버린 표본 \(data.droppedSamples)개, 이어버드 바뀜 \(data.sourceChanges)번, "
                         + "0.75초 넘게 늦은 표본 \(data.lateSamples)개. 앱은 이어버드 바뀜과 늦은 표본을 입력 중단으로 보지만 replay는 판정을 이어감")
        }
        let tuning = TuningFlag.all.map { "\($0.flag) \(fixed(report.tuning[$0.name] ?? 0, 3))" }.joined(separator: " ")
        lines.append("기준 \(tuning) --standing-delay \(fixed(report.timing.standingDelay, 2)) --return-settle \(fixed(report.timing.returnSettle, 2))")
        lines.append("")
        for step in report.steps where step.expectation != .none {
            var head = "\(step.id)  \(step.verdict.label)  (기대: \(step.expectation.label)"
            if let away = step.awayAfter { head += ", 비움까지 \(fixed(away, 1))초" }
            if let back = step.backAfter { head += ", 복귀까지 \(fixed(back, 1))초" }
            lines.append(head + ")")
            let level = step.maxLevel.map { "높이 최고 \(centimeters($0)) 최저 \(centimeters(step.minLevel ?? $0))" } ?? "움직임 표본 없음"
            let changes = step.heightChanges.isEmpty ? "" : ", 구간 변화 " + step.heightChanges.map(centimeters).joined(separator: " ")
            let events = step.events.isEmpty ? "" : " | " + step.events.map { "\($0.kind) \(fixed($0.at, 1))초" }.joined(separator: ", ")
            lines.append("    \(level)\(changes)\(events)")
        }
        lines.append("")
        let order: [StepVerdict] = [.ok, .missed, .falseCover, .stuck, .notApplicable]
        let summary = order.map { verdict in
            let ids = report.steps.filter { $0.verdict == verdict }.map(\.id)
            let detail = verdict == .ok || ids.isEmpty ? "" : "(\(ids.joined(separator: ", ")))"
            return "\(verdict.label) \(ids.count)\(detail)"
        }
        lines.append("요약: " + summary.joined(separator: ", "))
        return lines.joined(separator: "\n")
    }

    static func fixed(_ value: Double, _ digits: Int) -> String {
        String(format: "%.\(digits)f", value)
    }

    static func centimeters(_ meters: Double) -> String {
        let value = Int((meters * 100).rounded())
        return value > 0 ? "+\(value)cm" : "\(value)cm"
    }
}
