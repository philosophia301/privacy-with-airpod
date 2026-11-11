/// 짧은 구간의 수직 관성 적분 실험임. 초기 속도 0을 가정하며 실제 위치 정확도를 보장하지 않음.
public struct InertialProbe: Sendable {
    /// 미터 단위이며 z는 위쪽 양수임. 수평 기준이 없으므로 x/y는 항상 0임.
    public private(set) var displacement = SIMD3<Double>.zero
    /// m/s 단위 수직 속도임. 정지 감지나 bias 보정 없이 누적함.
    public private(set) var velocity = SIMD3<Double>.zero
    /// 최초 유효 표본부터 마지막 수락 표본까지의 초 단위 시간임. 무효화 시 0으로 폐기함.
    public private(set) var duration: Double = 0
    /// 기준 표본을 포함한 수락 표본 수임. 거부 표본은 제외하며 무효화 시 0으로 폐기함.
    public private(set) var sampleCount: Int = 0
    public private(set) var status = "대기: 초기 속도 0 가정"

    private var startTimestamp: Double?
    private var previousTimestamp: Double?
    private var previousAcceleration: Double = 0
    private var stopped = false

    public init() {}

    public mutating func reset() {
        self = Self()
    }

    public mutating func ingest(timestamp: Double, acceleration: SIMD3<Double>, gravity: SIMD3<Double>) {
        guard !stopped else { return }
        guard timestamp.isFinite,
              acceleration.x.isFinite, acceleration.y.isFinite, acceleration.z.isFinite,
              gravity.x.isFinite, gravity.y.isFinite, gravity.z.isFinite else {
            invalidate("유한하지 않은 입력")
            return
        }
        // 크기를 먼저 나눠 정규화 과정의 overflow/underflow를 피함.
        let scale = max(abs(gravity.x), max(abs(gravity.y), abs(gravity.z)))
        guard scale > 0 else {
            invalidate("중력 방향 없음")
            return
        }
        let scaled = gravity / scale
        let norm = (scaled.x * scaled.x + scaled.y * scaled.y + scaled.z * scaled.z).squareRoot()
        let down = scaled / norm
        let upward = -(acceleration.x * down.x + acceleration.y * down.y + acceleration.z * down.z) * 9.80665
        guard upward.isFinite else {
            invalidate("투영 계산 범위 초과")
            return
        }
        guard let previousTimestamp, let startTimestamp else {
            self.startTimestamp = timestamp
            self.previousTimestamp = timestamp
            previousAcceleration = upward
            sampleCount = 1
            status = "계측 중: 초기 속도 0 가정·수직 추정"
            return
        }
        let dt = timestamp - previousTimestamp
        guard dt > 0, dt <= 0.25 else {
            invalidate(dt <= 0 ? "시간 중복 또는 역행" : "표본 간격 0.25초 초과")
            return
        }
        let elapsed = timestamp - startTimestamp
        guard elapsed <= 10 else {
            invalidate("세션 10초 초과")
            return
        }
        // 표본 사이 가속도를 선형으로 가정한 해석적 적분임. 위치에 평균 속도를
        // 적용하면 선형 가속도에서도 오차가 나므로 가속도 변화의 1/6 항을 사용함.
        let nextPosition = displacement.z + velocity.z * dt
            + (previousAcceleration / 3 + upward / 6) * dt * dt
        let nextVelocity = velocity.z + (previousAcceleration / 2 + upward / 2) * dt
        guard nextPosition.isFinite, nextVelocity.isFinite else {
            invalidate("적분 계산 범위 초과")
            return
        }
        displacement.z = nextPosition
        velocity.z = nextVelocity
        duration = elapsed
        sampleCount += 1
        self.previousTimestamp = timestamp
        previousAcceleration = upward
        if elapsed == 10 {
            stopped = true
            status = "완료: 10초 한도·재설정 필요"
        }
    }

    private mutating func invalidate(_ reason: String) {
        self = Self()
        stopped = true
        status = "무효: \(reason)·재설정 필요"
    }
}
