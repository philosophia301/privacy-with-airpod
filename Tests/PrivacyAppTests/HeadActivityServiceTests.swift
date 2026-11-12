import CoreMotion
import Testing
@testable import PrivacyAirPods

@Test func walkingWithMediumConfidenceIsMoving() {
    let activity = HeadActivity.classify(walking: true, running: false, stationary: false, confidence: .medium)
    #expect(activity == .moving)
}

@Test func walkingWithLowConfidenceIsUnknown() {
    let activity = HeadActivity.classify(walking: true, running: false, stationary: false, confidence: .low)
    #expect(activity == .unknown)
}

@Test func runningWithHighConfidenceIsMoving() {
    let activity = HeadActivity.classify(walking: false, running: true, stationary: false, confidence: .high)
    #expect(activity == .moving)
}

@Test func stationaryWithHighConfidenceIsStationary() {
    let activity = HeadActivity.classify(walking: false, running: false, stationary: true, confidence: .high)
    #expect(activity == .stationary)
}

@Test func stationaryWithLowConfidenceIsUnknown() {
    let activity = HeadActivity.classify(walking: false, running: false, stationary: true, confidence: .low)
    #expect(activity == .unknown)
}

@Test func noFlagsWithHighConfidenceIsUnknown() {
    let activity = HeadActivity.classify(walking: false, running: false, stationary: false, confidence: .high)
    #expect(activity == .unknown)
}
