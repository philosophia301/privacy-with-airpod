import Foundation

// 기록 도구의 측정 순서와, 그 순서를 AirPods 없이 흉내 내는 합성 기록을 둠.

// MARK: - 측정 순서

struct ProtocolStep {
    let id: String
    let expectation: StepExpectation
    let seconds: Double
    let instruction: String

    /// 일어서기와 앉기는 반복해 표본을 늘림. 단계 시간은 안내 음성이 끝난 뒤부터 셈.
    /// 1차 실측(2026-11-13)에서 움직임이 끝나기까지 음성 뒤 3~4초가 걸려, 3초 대기까지 담도록 15초로 잡음.
    static func standard(repeats: Int) -> [ProtocolStep] {
        var steps = [
            ProtocolStep(id: "settle", expectation: .stay, seconds: 15, instruction: "앉은 채 정면을 보고 가만히 계세요"),
            ProtocolStep(id: "typing", expectation: .stay, seconds: 20, instruction: "앉은 채 평소처럼 타자를 치거나 마우스를 쓰세요"),
        ]
        steps += standSit(repeats: repeats)
        steps += [
            ProtocolStep(id: "shift", expectation: .stay, seconds: 12, instruction: "앉은 채 엉덩이를 들썩여 자세를 고쳐 앉으세요"),
            ProtocolStep(id: "lean", expectation: .stay, seconds: 12, instruction: "앉은 채 바닥의 물건을 줍듯 숙였다가 올라오세요"),
            ProtocolStep(id: "walk-away", expectation: .leave, seconds: 25, instruction: "일어나서 몇 걸음 걸어갔다가 의자 옆으로 돌아와 서 계세요"),
            ProtocolStep(id: "sit-after-walk", expectation: .back, seconds: 15, instruction: "다시 앉아서 정면을 보세요"),
            walkSit(id: "walk-sit"),
        ]
        return steps
    }

    /// 앉은 채 유지, 일어서기와 앉기, 걸어갔다 와서 바로 앉기만 하는 짧은 순서임.
    /// 앉은 채 하는 다른 동작은 standard 기록으로 보고, 일어섬과 앉음, 걷다 바로 앉음 표본을 빨리 모으는 용도임.
    static func quick(repeats: Int) -> [ProtocolStep] {
        [ProtocolStep(id: "settle", expectation: .stay, seconds: 10, instruction: "앉은 채 정면을 보고 가만히 계세요")]
            + standSit(repeats: repeats)
            + [walkSit(id: "walk-sit-1"), walkSit(id: "walk-sit-2")]
    }

    private static func standSit(repeats: Int) -> [ProtocolStep] {
        (1...repeats).flatMap { index in
            [ProtocolStep(id: "stand-\(index)", expectation: .leave, seconds: 15, instruction: "일어서서 가만히 서 계세요"),
             ProtocolStep(id: "sit-\(index)", expectation: .back, seconds: 15, instruction: "다시 앉아서 정면을 보세요")]
        }
    }

    private static func walkSit(id: String) -> ProtocolStep {
        ProtocolStep(id: id, expectation: .leaveThenBack, seconds: 25, instruction: "일어나서 몇 걸음 걸었다가 돌아와 멈추지 말고 바로 앉으세요")
    }
}

// MARK: - 합성 기록

/// 측정 순서를 이상적인 움직임으로 흉내 낸 기록임. 형식과 보고를 AirPods 없이 확인하는 용도이며 실제 사람 움직임을 대신하지 않음.
struct SyntheticRecording {
    private(set) var rows: [RecordedRow] = []
    private var time = 1000.0
    private var seed: UInt64 = 0x9E37_79B9_7F4A_7C15
    private let interval = 1.0 / 25
    /// 앱이 표본을 받는 지연을 흉내 냄.
    private let delivery = 0.02

    static func make(steps: [ProtocolStep]) -> [RecordedRow] {
        var recording = SyntheticRecording()
        recording.mark("ready", .none)
        recording.still(3)
        for step in steps {
            let start = recording.time
            recording.mark(step.id, step.expectation)
            recording.perform(step.id)
            recording.still(start + step.seconds - recording.time)
        }
        recording.mark("end", .none)
        return recording.rows
    }

    private mutating func perform(_ id: String) {
        switch id {
        case _ where id.hasPrefix("stand-"):
            still(1.5); move(0.45, over: 1.2)
        case _ where id.hasPrefix("sit-"):
            still(1.5); move(-0.45, over: 1.0)
        case "shift":
            still(1.5); move(0.08, over: 0.5); still(1.0); move(-0.08, over: 0.5)
        case "lean":
            still(1.5); move(-0.30, over: 1.0); still(1.5); move(0.30, over: 1.0)
        case "walk-away":
            still(1.5); move(0.45, over: 1.2); still(0.8)
            activity(["walking"]); walk(9); activity(["stationary"])
        case _ where id.hasPrefix("walk-sit"):
            // 걷던 흔들림이 이어진 채 앉아 정지 구간 없이 내려감. 알려진 놓침 경우임.
            still(1.5); move(0.45, over: 1.2); still(0.8)
            activity(["walking"]); walk(6); move(-0.45, over: 1.0, bobbing: true); still(1.0); activity(["stationary"])
        default:
            break
        }
    }

    private mutating func mark(_ id: String, _ expectation: StepExpectation) {
        rows.append(.step(rx: time + delivery, id: id, expectation: expectation))
    }

    private mutating func activity(_ kinds: [String]) {
        rows.append(.activity(rx: time + delivery, t: time, kinds: kinds, confidence: 2))
    }

    private mutating func still(_ seconds: Double) {
        for _ in 0..<max(0, Int((seconds / interval).rounded())) { sample(upward: 0) }
    }

    /// 높이가 0.5·h·(1-cos)로 바뀌는 움직임의 가속도를 냄. bobbing이면 걷는 흔들림을 더함.
    private mutating func move(_ meters: Double, over seconds: Double, bobbing: Bool = false) {
        let omega = Double.pi / seconds
        let count = Int((seconds / interval).rounded())
        for index in 0..<count {
            let elapsed = Double(index) * interval
            let upward = 0.5 * meters * omega * omega * cos(omega * elapsed)
            sample(upward: upward + (bobbing ? bob(elapsed) : 0))
        }
    }

    private mutating func walk(_ seconds: Double) {
        let count = Int((seconds / interval).rounded())
        for index in 0..<count { sample(upward: bob(Double(index) * interval)) }
    }

    /// 걸음마다 오르내리는 머리 흔들림임. 정지 기준(0.4m/s²)보다 커서 걷는 동안 정지가 생기지 않음.
    private func bob(_ elapsed: Double) -> Double {
        1.2 * sin(2 * .pi * 2 * elapsed) + 0.8 * cos(2 * .pi * 1 * elapsed)
    }

    private mutating func sample(upward: Double) {
        let noise = SIMD3(jitter(), jitter(), jitter())
        // Core Motion 관례대로 위로 가속하면 사용자 가속도가 중력과 같은 쪽(-z)을 가리킴.
        rows.append(.motion(rx: time + delivery, t: time,
                            acceleration: SIMD3(0, 0, -upward / 9.80665) + noise,
                            gravity: SIMD3(0, 0, -1), source: 1))
        time += interval
    }

    /// 정지 기준보다 충분히 작은 센서 잡음임. 결과가 실행마다 같도록 고정 seed를 씀.
    private mutating func jitter() -> Double {
        seed = seed &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
        return (Double(seed >> 11) / Double(1 << 53) - 0.5) * 0.012
    }
}
