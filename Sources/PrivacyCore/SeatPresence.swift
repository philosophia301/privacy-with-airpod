import Foundation

/// AirPods 머리 움직임으로 일어섬과 앉음을 판정하는 순수 상태 기계임. 높이 추정은 임시값이며 실측 전 Tuning으로 조정함.
public struct SeatPresence: Sendable {
    public enum Posture: Sendable, Equatable {
        case seated
        case standing
    }

    public enum Event: Sendable, Equatable {
        case stoodUp
        case satDown
    }

    /// 판정 기준 값. 단위는 각 항목 설명을 따르며 실측 전 임시값임.
    public struct Tuning: Sendable, Equatable {
        /// 사용자 가속도 벡터 크기의 정지 기준임. m/s² 단위임.
        public var stillAcceleration = 0.4
        /// 정지로 인정하기 위해 가속도 크기가 기준 아래로 이어져야 하는 시간임. 초 단위임.
        public var stillDuration = 0.25
        /// 한 움직임 구간의 최대 길이임. 초 단위이며 넘으면 높이 변화를 버림.
        public var maximumSegment = 4.0
        /// 연속 표본 사이 허용 간격임. 초 단위이며 넘거나 0 이하이면 구간과 정지 판정을 버림.
        public var maximumGap = 0.25
        /// seated 상태에서 이 높이 이상이면 일어섬으로 봄. 앉은 자세 기준 m 단위임.
        public var standLevel = 0.25
        /// standing 상태에서 이 높이 이하이면 앉음으로 봄. 앉은 자세 기준 m 단위임.
        public var sitLevel = 0.12
        /// 정지가 이어져도 구간을 끝내려면 속도 추정이 이 값 이하여야 함. m/s 단위임.
        /// 완만한 일어섬은 속도 최고점에서 가속도가 0을 지나 짧은 정지처럼 보이므로 그 지점에서 끊지 않으려고 둠.
        public var settledVelocity = 0.15
        /// 속도 추정과 무관하게 이 시간 이상 정지가 이어지면 구간을 끝냄. 초 단위이며 가속도 편향으로 속도가 쌓인 경우를 위함.
        public var forcedStillDuration = 1.0
        /// 정지 중 level이 기준값으로 되돌아가는 시간 상수임. 초 단위임.
        public var relaxTime = 20.0

        public init() {}
    }

    /// 현재 추정된 자세임. 앉은 상태에서도 level은 0으로 자르지 않음.
    public private(set) var posture: Posture = .seated
    /// 앉은 자세 기준 머리 높이 추정치임. m 단위이며 위쪽 양수임.
    public private(set) var level: Double = 0

    private struct Sample {
        var time: Double
        /// 위쪽 양수 수직 가속도임. m/s² 단위임.
        var vertical: Double
        var still: Bool
    }

    private struct Segment {
        var startTime: Double
        var lastTime: Double
        var lastVertical: Double
        var velocity: Double = 0
        var displacement: Double = 0
        /// 구간 안에서 현재 이어지는 정지의 시작 시각임. 구간 끝 판정에 씀.
        var stillStart: Double?
    }

    private let tuning: Tuning
    private var previous: Sample?
    /// 구간 밖에서 현재 이어지는 정지의 시작 시각임.
    private var stillStart: Double?
    private var segment: Segment?
    /// 서 있는 동안 정지 중 level이 되돌아가는 높이임. 일어선 시점의 level이며 사용자의 실제 일어섬 높이를 따름.
    private var standingReference = 0.0

    public init(tuning: Tuning = Tuning()) {
        self.tuning = tuning
    }

    /// 자세를 강제로 맞추고 진행 중이던 구간과 정지 판정을 버림. 기준 높이는 자세에 맞춰 다시 잡음.
    public mutating func reset(to posture: Posture) {
        self.posture = posture
        // 서 있는 높이를 모를 때는 일어섬으로 인정되는 가장 낮은 높이로 둠. 더 큰 하강도 앉음으로 잡히게 함.
        standingReference = tuning.standLevel
        level = restingLevel
        forgetMotion()
    }

    /// 머리 움직임 표본 하나를 넣고 자세가 바뀌면 이벤트를 돌려줌.
    /// acceleration은 g 단위 사용자 가속도, gravity는 g 단위 아래 방향 벡터이며 둘 다 Core Motion 관례를 따름.
    public mutating func ingest(timestamp: Double, acceleration: SIMD3<Double>, gravity: SIMD3<Double>) -> Event? {
        guard timestamp.isFinite,
              let vertical = Self.verticalAcceleration(acceleration, gravity: gravity) else {
            // 값이 깨진 표본은 구간의 높이 변화를 신뢰할 수 없게 하므로 구간과 정지 판정을 모두 버림.
            forgetMotion()
            return nil
        }
        let sample = Sample(time: timestamp,
                            vertical: vertical,
                            still: Self.magnitude(acceleration) < tuning.stillAcceleration)
        guard let last = previous else {
            startStillRun(at: sample)
            return nil
        }
        let dt = sample.time - last.time
        guard dt > 0, dt <= tuning.maximumGap else {
            forgetMotion()
            startStillRun(at: sample)
            return nil
        }
        return advance(from: last, to: sample)
    }

    private mutating func advance(from last: Sample, to sample: Sample) -> Event? {
        guard var current = segment else {
            return stepOutsideSegment(from: last, to: sample)
        }
        guard sample.time - current.startTime <= tuning.maximumSegment else {
            // 구간이 너무 길면 적분 오차가 커지므로 높이 변화를 반영하지 않음.
            segment = nil
            startStillRun(at: sample)
            return nil
        }
        Self.integrate(&current, time: sample.time, vertical: sample.vertical)
        guard current.velocity.isFinite, current.displacement.isFinite else {
            forgetMotion()
            return nil
        }
        current.stillStart = sample.still ? (current.stillStart ?? sample.time) : nil
        if let since = current.stillStart {
            let held = sample.time - since
            let settled = abs(current.velocity) <= tuning.settledVelocity
            if (held >= tuning.stillDuration && settled) || held >= tuning.forcedStillDuration {
                return finish(current, at: sample)
            }
        }
        segment = current
        previous = sample
        return nil
    }

    private mutating func stepOutsideSegment(from last: Sample, to sample: Sample) -> Event? {
        if sample.still {
            stillStart = stillStart ?? sample.time
            relax(over: sample.time - last.time)
            previous = sample
            return nil
        }
        // 구간 시작 기준점은 정지가 확정된 마지막 표본이어야 하므로 직전 표본을 씀.
        let established = stillStart.map { last.time - $0 >= tuning.stillDuration } ?? false
        previous = sample
        guard established else {
            stillStart = nil
            return nil
        }
        var current = Segment(startTime: last.time, lastTime: last.time, lastVertical: last.vertical)
        Self.integrate(&current, time: sample.time, vertical: sample.vertical)
        guard current.velocity.isFinite, current.displacement.isFinite else {
            forgetMotion()
            return nil
        }
        stillStart = nil
        segment = current
        return nil
    }

    /// 구간 끝의 선형 속도 오차를 보정해 높이 변화를 반영하고 자세 전환을 판정함.
    private mutating func finish(_ current: Segment, at sample: Sample) -> Event? {
        segment = nil
        let length = sample.time - current.startTime
        // 구간 끝 속도는 0이어야 하므로 속도가 시간에 따라 선형으로 쌓였다고 보고 그 몫을 뺌.
        let delta = current.displacement - current.velocity * length / 2
        guard delta.isFinite else {
            forgetMotion()
            return nil
        }
        level = min(max(level + delta, -0.6), 0.9)
        // 정지 확인 구간이 그대로 다음 구간의 정지 기준이 되어 연속 움직임을 바로 이어 잡음.
        stillStart = current.stillStart
        previous = sample
        return updatePosture()
    }

    private mutating func updatePosture() -> Event? {
        switch posture {
        case .seated where level >= tuning.standLevel:
            posture = .standing
            standingReference = level
            return .stoodUp
        case .standing where level <= tuning.sitLevel:
            posture = .seated
            return .satDown
        default:
            return nil
        }
    }

    private mutating func relax(over dt: Double) {
        level += (restingLevel - level) * (1 - exp(-dt / tuning.relaxTime))
    }

    private var restingLevel: Double {
        switch posture {
        case .seated: 0
        case .standing: standingReference
        }
    }

    private mutating func startStillRun(at sample: Sample) {
        previous = sample
        stillStart = sample.still ? sample.time : nil
    }

    private mutating func forgetMotion() {
        segment = nil
        previous = nil
        stillStart = nil
    }

    private static func integrate(_ current: inout Segment, time: Double, vertical: Double) {
        let dt = time - current.lastTime
        let velocity = current.velocity + (current.lastVertical + vertical) / 2 * dt
        current.displacement += (current.velocity + velocity) / 2 * dt
        current.velocity = velocity
        current.lastTime = time
        current.lastVertical = vertical
    }

    /// InertialProbe과 같은 투영이며 위쪽 양수 m/s²를 돌려줌. 계산할 수 없으면 nil임.
    private static func verticalAcceleration(_ acceleration: SIMD3<Double>, gravity: SIMD3<Double>) -> Double? {
        guard acceleration.x.isFinite, acceleration.y.isFinite, acceleration.z.isFinite,
              gravity.x.isFinite, gravity.y.isFinite, gravity.z.isFinite else {
            return nil
        }
        // 크기를 먼저 나눠 정규화 과정의 overflow/underflow를 피함.
        let scale = max(abs(gravity.x), max(abs(gravity.y), abs(gravity.z)))
        guard scale > 0 else { return nil }
        let scaled = gravity / scale
        let norm = (scaled.x * scaled.x + scaled.y * scaled.y + scaled.z * scaled.z).squareRoot()
        let down = scaled / norm
        // Core Motion의 userAcceleration은 머리가 위로 가속할 때 gravity와 같은 쪽을 가리킴.
        // 2026-11-13 실측에서 반대 부호로 두었더니 일어섬이 내려감으로 계산됐음.
        let upward = (acceleration.x * down.x + acceleration.y * down.y + acceleration.z * down.z) * 9.80665
        return upward.isFinite ? upward : nil
    }

    /// 사용자 가속도 벡터 크기를 m/s² 단위로 돌려줌. 정지 판정에만 쓰며 저장하지 않음.
    private static func magnitude(_ acceleration: SIMD3<Double>) -> Double {
        (acceleration.x * acceleration.x + acceleration.y * acceleration.y + acceleration.z * acceleration.z).squareRoot() * 9.80665
    }
}
