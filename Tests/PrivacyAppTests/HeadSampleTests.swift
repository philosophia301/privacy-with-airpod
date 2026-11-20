import Testing
@testable import PrivacyAirPods

struct HeadSampleTests {
    @Test func freshnessDeadlineUsesOlderMeasurementOrDelivery() {
        let measuredFirst = HeadSample(timestamp: 10, receivedAt: 10.1, yaw: 0, acceleration: .zero, gravity: .zero, source: 0)
        let deliveredFirst = HeadSample(timestamp: 10.1, receivedAt: 10, yaw: 0, acceleration: .zero, gravity: .zero, source: 0)
        for sample in [measuredFirst, deliveredFirst] {
            #expect(abs(sample.freshnessRemaining(at: 10.5) - 0.25) < 0.000001)
            #expect(sample.freshnessRemaining(at: 10.75) == 0)
            #expect(sample.freshnessRemaining(at: 11) == 0)
            #expect(sample.freshnessRemaining(at: 9) == 0)
            #expect(sample.freshnessRemaining(at: .infinity) == 0)
        }
    }
    @Test func delayedMeasurementCannotBecomeFreshOnDelivery() {
        let sample = HeadSample(timestamp: 10, receivedAt: 12, yaw: 0, acceleration: .zero, gravity: SIMD3(0, 0, -1), source: 0)
        #expect(!sample.isFresh(at: 12))
        #expect(sample.isAlive(at: 12))
    }

    @Test func freshnessChecksBothClocksAndBoundary() {
        let sample = HeadSample(timestamp: 10, receivedAt: 10.1, yaw: 0, acceleration: .zero, gravity: SIMD3(0, 0, -1), source: 0)
        #expect(sample.isFresh(at: 10.1))
        #expect(sample.isFresh(at: 10.749))
        #expect(!sample.isFresh(at: 10.75))
        #expect(!sample.isFresh(at: 9))
        #expect(!sample.isFresh(at: .nan))
    }

    /// 늦은 입력은 끊김 기준(2.5초) 전까지 살아 있음. 실측 2차의 최대 지연 1.71초는 살아 있는 쪽임.
    @Test func lateSampleStaysAliveUntilTheLossAge() {
        let sample = HeadSample(timestamp: 10, receivedAt: 10.1, yaw: 0, acceleration: .zero, gravity: SIMD3(0, 0, -1), source: 0)
        #expect(sample.isAlive(at: 10.1))
        #expect(sample.isAlive(at: 11.71))
        #expect(sample.isAlive(at: 12.499))
        #expect(!sample.isAlive(at: 12.5))
        #expect(!sample.isAlive(at: 9))
        #expect(!sample.isAlive(at: .nan))
        #expect(sample.age(at: 11) == 1)
        #expect(sample.age(at: 9) == nil)
    }

    /// 실측 2차에서 센서 시각이 받은 시각보다 최대 0.01초 앞섰음. 0.1초 안은 제때 온 입력으로 받고, 더 앞서면 깨진 시각으로 봄.
    @Test func sensorClockSlightlyAheadOfTheMacIsStillOnTime() {
        let ahead = HeadSample(timestamp: 10.01, receivedAt: 10, yaw: 0, acceleration: .zero, gravity: SIMD3(0, 0, -1), source: 0)
        #expect(ahead.age(at: 10) == 0)
        #expect(ahead.isFresh(at: 10) && ahead.isAlive(at: 10))
        let broken = HeadSample(timestamp: 10.2, receivedAt: 10, yaw: 0, acceleration: .zero, gravity: SIMD3(0, 0, -1), source: 0)
        #expect(broken.age(at: 10) == nil)
        #expect(!broken.isAlive(at: 10))
    }
}
