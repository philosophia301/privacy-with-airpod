import Foundation

/// AirPods 머리 움직임의 전환 모양으로 일어섬과 앉음을 판정하는 순수 상태 기계임.
/// 위쪽 속도 추정, 반대 방향 최고점과의 짝 판정, 걸음 착지 감지로 구성되며 기억 상태는 표본 수와 무관하게 일정함.
/// 기준값은 오프라인 실측 두 기록에서 고른 값이며 Tuning에 모음.
public struct SeatPresence: Sendable {
    public enum Posture: Sendable, Equatable {
        case seated
        case standing
    }

    public enum Event: Sendable, Equatable {
        case stoodUp
        case satDown
    }

    /// 판정 기준 값임. 속도는 m/s, 가속도는 m/s², 시간은 초, 개수는 걸음 수 단위임.
    public struct Tuning: Sendable, Equatable {
        /// 위쪽 속도 추정이 잊히는 시간 상수임.
        /// 가속도 편향이 속도로 끝없이 쌓이지 않게 함. 실측 앉은 자세 편향은 10초 평균 0.0033 g 이하라 쌓여도 0.1 m/s 이하임.
        public var velocityMemory = 3.0
        /// 일어섬으로 볼 위쪽 속도 기준임.
        /// 실측 두 기록에서 앉아 움직일 때 판정값 최대는 0.27 m/s였고, 잡힌 일어섬 중 가장 약한 것은 0.37 m/s였음.
        public var standSpeed = 0.33
        /// 앉음 후보로 볼 아래쪽 속도 기준임. 실측 두 기록에서 고른 값이며 확인 시간이 오인을 한 번 더 거름.
        public var sitSpeed = 0.22
        /// 반대 방향 최고점에서 빼는 몫임. 숙였다 펴는 동작의 짝 엽을 전환으로 잡지 않게 함.
        public var pairing = 0.8
        /// 반대 방향 최고점을 기억하는 시간 상수임.
        public var pairingMemory = 4.0
        /// 전환 뒤 같은 판정을 막는 시간임. 한 번의 움직임이 두 번 잡히지 않게 함.
        public var refractory = 1.5
        /// 앉음 후보가 확인을 기다리는 시간임. 걸음과 흔들림이 앉음으로 잡히는 것을 거르는 데 씀.
        public var sitConfirmation = 1.0
        /// 확인 기간에 허용하는 걸음 착지 수임. 넘으면 걷는 중이므로 후보를 버림.
        public var confirmationSteps = 1
        /// 걸음 착지로 볼 위쪽 가속도 피크 크기임. m/s² 단위임.
        public var stepAcceleration = 3.0
        /// 같은 착지의 떨림을 하나로 묶는 최소 간격임.
        public var stepDebounce = 0.25
        /// 걸음 사이 간격으로 인정하는 최소 값임. 같은 걸음 흐름으로 이어지는지 볼 때 씀.
        public var stepIntervalMin = 0.3
        /// 걸음 사이 간격으로 인정하는 최대 값임. 넘으면 걸음 흐름을 끊음.
        public var stepIntervalMax = 0.9
        /// 걸음이 이 수 이상 이어지면 걷는 중으로 봄.
        public var walkingSteps = 3
        /// 걷기 직후 앉음 기준을 올리는 시간 창임.
        public var afterWalkingWindow = 1.5
        /// 걷기 직후 앉음 기준에 곱하는 배율임. 걷다 멈춘 뒤 머리 흔들림이 앉음으로 오인되는 것을 막음.
        public var afterWalkingFactor = 1.6
        /// 연속 표본 사이 허용 최대 간격임. 넘으면 속도를 0으로 두고 앉음 후보를 버림.
        public var maximumGap = 0.5

        public init() {}
    }

    /// 현재 추정된 자세임.
    public private(set) var posture: Posture = .seated
    /// 머리 위쪽 속도 추정치임. m/s 단위이며 위쪽 양수임. 진단용으로 노출함.
    public private(set) var velocity: Double = 0

    /// 앉음 후보가 확인을 기다리는 중이면 true임. AppModel은 이 동안 3초 자리 비움 타이머를 붙잡음.
    public var isConfirmingSit: Bool {
        pendingSit != nil
    }

    private struct Sample {
        var time: Double
        /// 위쪽 양수 수직 가속도임. m/s² 단위임.
        var vertical: Double
    }

    private struct PendingSit {
        var deadline: Double
        var steps: Int
    }

    private let tuning: Tuning
    private var previous: Sample?
    /// 최근 아래 방향 속도 최고점의 크기임. 양수로 저장함.
    private var downMemory = 0.0
    /// 최근 위 방향 속도 최고점임.
    private var upMemory = 0.0
    private var refractoryUntil = -Double.infinity
    /// 초기화 뒤 첫 판정 표본에서 불응기를 시작하라는 표시임.
    private var refractoryPending = true
    private var pendingSit: PendingSit?
    private var stepRun = 0
    private var lastStep = -Double.infinity
    private var lastWalking = -Double.infinity

    public init(tuning: Tuning = Tuning()) {
        self.tuning = tuning
    }

    /// 자세를 강제로 맞추고 기억 값, 불응기, 앉음 후보를 버림.
    /// 직전 표본과 걸음 기록은 버리지 않음. 걸음 흐름은 자세와 무관하게 이어져야 하기 때문임.
    public mutating func reset(to posture: Posture) {
        self.posture = posture
        clearMemories()
        refractoryUntil = -.infinity
        refractoryPending = true
        pendingSit = nil
    }

    /// 머리 움직임 표본 하나를 넣고 자세가 바뀌면 이벤트를 돌려줌.
    /// acceleration은 g 단위 사용자 가속도, gravity는 g 단위 아래 방향 벡터이며 둘 다 Core Motion 관례를 따름.
    public mutating func ingest(timestamp: Double, acceleration: SIMD3<Double>, gravity: SIMD3<Double>) -> Event? {
        guard timestamp.isFinite,
              let vertical = Self.verticalAcceleration(acceleration, gravity: gravity) else {
            // 값이 깨진 표본 뒤에는 이전 표본과 이어 적분할 수 없으므로 기준점과 앉음 후보를 버림.
            forgetSample()
            return nil
        }
        guard let last = previous else {
            velocity = 0
            previous = Sample(time: timestamp, vertical: vertical)
            return nil
        }
        let dt = timestamp - last.time
        // 시각이 되돌아가거나 같은 표본은 상태에 반영하지 않음.
        guard dt > 0 else { return nil }
        guard dt <= tuning.maximumGap else {
            // 긴 공백의 움직임은 알 수 없으므로 속도를 0으로 두고 앉음 확인을 버림. 기억 값과 걸음 기록은 유지함.
            velocity = 0
            pendingSit = nil
            previous = Sample(time: timestamp, vertical: vertical)
            return nil
        }
        let nextVelocity = velocity * exp(-dt / tuning.velocityMemory) + vertical * dt
        guard nextVelocity.isFinite else {
            forgetSample()
            return nil
        }
        registerHeelStrike(at: timestamp, vertical: vertical, previousVertical: last.vertical)
        previous = Sample(time: timestamp, vertical: vertical)
        if timestamp - lastStep > tuning.stepIntervalMax {
            stepRun = 0
        }
        let walking = stepRun >= tuning.walkingSteps
        if walking {
            lastWalking = timestamp
        }
        velocity = nextVelocity
        if walking {
            // 걸음 착지의 높이 변화는 자세 전환이 아니므로 판정 기억을 모두 버림.
            pendingSit = nil
            clearMemories()
            return nil
        }
        if refractoryPending {
            refractoryUntil = timestamp + tuning.refractory
            refractoryPending = false
        }
        let decay = exp(-dt / tuning.pairingMemory)
        downMemory = max(downMemory * decay, -velocity)
        upMemory = max(upMemory * decay, velocity)
        if let sit = pendingSit {
            return confirmSit(sit, at: timestamp)
        }
        guard timestamp >= refractoryUntil else { return nil }
        switch posture {
        case .seated:
            return tryStand(at: timestamp)
        case .standing:
            beginSitCandidateIfDescending(at: timestamp)
            return nil
        }
    }

    /// 걸음 착지 피크가 새로 올라왔는지 보고 걸음 흐름과 확인 기간의 걸음 수를 갱신함.
    private mutating func registerHeelStrike(at time: Double, vertical: Double, previousVertical: Double) {
        guard vertical >= tuning.stepAcceleration,
              tuning.stepAcceleration > previousVertical,
              time - lastStep >= tuning.stepDebounce else {
            return
        }
        let gap = time - lastStep
        let continuing = gap >= tuning.stepIntervalMin && gap <= tuning.stepIntervalMax
        stepRun = continuing ? stepRun + 1 : 1
        lastStep = time
        pendingSit?.steps += 1
    }

    /// 확인 기간이 끝나기 전에 걸음이나 위쪽 움직임이 오면 후보를 버리고, 시간이 다 되면 앉음으로 바꿈.
    private mutating func confirmSit(_ sit: PendingSit, at time: Double) -> Event? {
        if sit.steps > tuning.confirmationSteps || velocity >= tuning.standSpeed {
            pendingSit = nil
            return nil
        }
        guard time >= sit.deadline else { return nil }
        pendingSit = nil
        posture = .seated
        clearMemories()
        refractoryUntil = time + tuning.refractory
        return .satDown
    }

    private mutating func tryStand(at time: Double) -> Event? {
        guard velocity - tuning.pairing * downMemory >= tuning.standSpeed else { return nil }
        posture = .standing
        clearMemories()
        refractoryUntil = time + tuning.refractory
        return .stoodUp
    }

    /// 서 있는 동안 아래 방향 속도가 기준을 넘으면 앉음 후보를 세움. 걷기 직후에는 기준을 올림.
    private mutating func beginSitCandidateIfDescending(at time: Double) {
        let afterWalking = time - lastWalking < tuning.afterWalkingWindow
        let need = tuning.sitSpeed * (afterWalking ? tuning.afterWalkingFactor : 1)
        guard -velocity - tuning.pairing * upMemory >= need else { return }
        pendingSit = PendingSit(deadline: time + tuning.sitConfirmation, steps: 0)
    }

    private mutating func forgetSample() {
        previous = nil
        velocity = 0
        pendingSit = nil
    }

    private mutating func clearMemories() {
        downMemory = 0
        upMemory = 0
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
        // 반대 부호로 두면 일어섬이 내려감으로 계산됨.
        let upward = (acceleration.x * down.x + acceleration.y * down.y + acceleration.z * down.z) * 9.80665
        return upward.isFinite ? upward : nil
    }
}
