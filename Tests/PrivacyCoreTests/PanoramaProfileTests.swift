import Testing
@testable import PrivacyCore

private func panorama(gap: Double = 0, transition: Double = 0.25) throws -> PanoramaProfile {
    try #require(PanoramaProfile(leftWidth: 40, rightWidth: 80, gap: gap, viewingDistance: 60,
                                frontPosition: 40 + gap / 2, startDegrees: 35, transitionFraction: transition))
}

@Test func touchingScreensAreSlicesOfExactlyTheSameField() throws {
    let profile = try panorama()
    for gaze in stride(from: -90.0, through: 120.0, by: 5) {
        let left = PanoramaSlice(profile: profile, origin: 0, width: 40, gaze: gaze)
        let right = PanoramaSlice(profile: profile, origin: 40, width: 80, gaze: gaze)
        #expect(left.strength(at: 1) == right.strength(at: 0))
        #expect(abs(profile.strength(at: 40 - 0.001, gaze: gaze) - profile.strength(at: 40 + 0.001, gaze: gaze)) < 0.001)
    }
}

@Test func deskFrontDistanceAndPhysicalPositionsDefineAngles() throws {
    let profile = try panorama(gap: 20)
    #expect(profile.angle(at: 50) == 0)
    #expect(profile.angle(at: 110) == 45)
    #expect(profile.angle(at: -10) == -45)
    let left = PanoramaSlice(profile: profile, origin: 0, width: 40, gaze: 60)
    let right = PanoramaSlice(profile: profile, origin: 60, width: 80, gaze: 60)
    #expect(left.strength(at: 0.5) == profile.strength(at: 20, gaze: 60))
    #expect(right.strength(at: 0.5) == profile.strength(at: 100, gaze: 60))
    #expect(profile.strength(at: 50, gaze: 0) == 0)
}

@Test func gapContainsContinuousUnrenderedPositionsRatherThanRestartingBlur() throws {
    let profile = try panorama(gap: 20)
    #expect(profile.angle(at: 50) == 0)
    let samples = stride(from: 0.0, through: 140.0, by: 1).map { profile.strength(at: $0, gaze: 100) }
    for (earlier, later) in zip(samples, samples.dropFirst()) { #expect(earlier >= later) }
    #expect(profile.strength(at: 40, gaze: 45) > profile.strength(at: 60, gaze: 45))
}

@Test func widerTransitionSoftensTheSameBoundaryAndZeroMakesAHardEdge() throws {
    let hard = try panorama(transition: 0)
    let narrow = try panorama(transition: 0.1)
    let wide = try panorama(transition: 0.5)
    #expect(hard.strength(at: 40, gaze: 35) == 0)
    #expect(hard.strength(at: 40, gaze: 36) == 1)
    #expect(narrow.strength(at: 40, gaze: 45) > wide.strength(at: 40, gaze: 45))
    #expect(wide.strength(at: 40, gaze: 0) == 0)
    #expect(wide.strength(at: 40, gaze: .nan) == 1)
}

@Test func invalidGeometryCannotProduceAPanorama() {
    for widths in [(0.0, 80.0), (-1, 80), (.nan, 80), (40, .infinity)] {
        #expect(PanoramaProfile(leftWidth: widths.0, rightWidth: widths.1, gap: 0, viewingDistance: 60,
                               frontPosition: 40, startDegrees: 35, transitionFraction: 0.25) == nil)
    }
    #expect(PanoramaProfile(leftWidth: 40, rightWidth: 80, gap: -1, viewingDistance: 60,
                           frontPosition: 40, startDegrees: 35, transitionFraction: 0.25) == nil)
}

@Test func turningRightSweepsLeftToRightAcrossThePanoramaAndReverseIsSymmetric() throws {
    let profile = try #require(PanoramaProfile(leftWidth: 60, rightWidth: 60, gap: 10, viewingDistance: 60,
                                              frontPosition: 65, startDegrees: 35, transitionFraction: 0.25))
    for x in stride(from: 0.0, through: 130.0, by: 1) {
        #expect(abs(profile.strength(at: x, gaze: 60) - profile.strength(at: 130 - x, gaze: -60)) < 0.000001)
    }
    #expect(profile.strength(at: 0, gaze: 60) > profile.strength(at: 130, gaze: 60))
    #expect(profile.strength(at: 65, gaze: 60) == profile.strength(at: 65, gaze: -60))
}
