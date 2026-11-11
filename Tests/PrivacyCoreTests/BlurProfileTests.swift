import Testing
@testable import PrivacyCore

@Test func noBlurBeforeOrAtConfiguredStartAngle() {
    let profile = BlurProfile(startDegrees: 20, fullDegrees: 60)
    for angle in [-20.0, -19, 0, 19, 20] {
        for x in [0.0, 0.5, 1] { #expect(profile.strength(angle: angle, horizontalPosition: x) == 0) }
    }
}

@Test func rightTurnBlursLeftEdgeFirstAndLeftTurnMirrorsIt() {
    let profile = BlurProfile(startDegrees: 20, fullDegrees: 60)
    #expect(profile.strength(angle: 40, horizontalPosition: 0) == 1)
    #expect(profile.strength(angle: 40, horizontalPosition: 0.5) == 0.5)
    #expect(profile.strength(angle: 40, horizontalPosition: 1) == 0)
    for x in [0.0, 0.25, 0.5, 0.75, 1] {
        #expect(profile.strength(angle: -40, horizontalPosition: 1-x) == profile.strength(angle: 40, horizontalPosition: x))
    }
}

@Test func fullTurnCoversBothEdgesAndIncreasingAngleNeverRevealsContent() {
    let profile = BlurProfile(startDegrees: 15, fullDegrees: 55)
    for x in [0.0, 0.2, 0.5, 0.9, 1] {
        var previous = 0.0
        for angle in stride(from: 0.0, through: 90.0, by: 0.5) {
            let strength = profile.strength(angle: angle, horizontalPosition: x)
            #expect(strength >= previous)
            #expect(strength <= 1)
            previous = strength
        }
        #expect(profile.strength(angle: 55, horizontalPosition: x) == 1)
    }
}

@Test func headingWrapDoesNotBecomeFullTurn() {
    #expect(BlurProfile.relativeDegrees(current: -179, reference: 179) == 2)
    #expect(BlurProfile.relativeDegrees(current: 179, reference: -179) == -2)
}

@Test func invalidInputsDoNotRevealTheScreen() {
    #expect(BlurProfile().strength(angle: .nan, horizontalPosition: 0.5) == 1)
    #expect(BlurProfile(startDegrees: 60, fullDegrees: 20).strength(angle: 10, horizontalPosition: 0.5) == 1)
}

@Test func smoothingAcrossHeadingWrapNeverPassesThroughClearFront() {
    for fraction in [0.0, 0.25, 0.5, 0.75, 1] {
        let angle = BlurProfile.interpolatedDegrees(from: 179, to: -179, fraction: fraction)
        #expect(abs(angle) >= 179)
        #expect(BlurProfile().strength(angle: angle, horizontalPosition: 0.5) == 1)
    }
    #expect(BlurProfile.interpolatedDegrees(from: 10, to: 30, fraction: 0.5) == 20)
}
