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
    }

    @Test func freshnessChecksBothClocksAndBoundary() {
        let sample = HeadSample(timestamp: 10, receivedAt: 10.1, yaw: 0, acceleration: .zero, gravity: SIMD3(0, 0, -1), source: 0)
        #expect(sample.isFresh(at: 10.1))
        #expect(sample.isFresh(at: 10.749))
        #expect(!sample.isFresh(at: 10.75))
        #expect(!sample.isFresh(at: 9))
        #expect(!sample.isFresh(at: .nan))
    }
}
