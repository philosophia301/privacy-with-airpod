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
}
