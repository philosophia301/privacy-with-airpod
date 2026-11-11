import Foundation
import Testing
@testable import PrivacyCore

@Test func frontFacingDisplayHasExpectedCenterAndEdgeAngles() throws {
    let display = try #require(DisplayPose(id: 7, width: 40, height: 25, x: 0, y: 0, z: 60,
                                           yawDegrees: 0).compiled(sampleCount: 3))
    #expect(abs(display.angles[0] - (-atan(20 / 60) * 180 / .pi)) < 1e-12)
    #expect(display.angles[1] == 0)
    #expect(abs(display.angles[2] - (atan(20 / 60) * 180 / .pi)) < 1e-12)
    #expect(display.minimumAngle == display.angles[0])
    #expect(display.maximumAngle == display.angles[2])
}

@Test func yawRotatesScreenEndpointsInWorldCoordinates() throws {
    let display = try #require(DisplayPose(id: 1, width: 20, height: 10, x: 0, y: 0, z: 50,
                                           yawDegrees: 30).compiled(sampleCount: 3))
    #expect(abs(display.angles[0] - atan2(-10 * cos(.pi / 6), 50 + 10 * sin(.pi / 6)) * 180 / .pi) < 1e-12)
    #expect(display.angles[1] == 0)
    #expect(abs(display.angles[2] - atan2(10 * cos(.pi / 6), 50 - 10 * sin(.pi / 6)) * 180 / .pi) < 1e-12)
}

@Test func invalidPoseGeometryDoesNotCompile() {
    let valid = DisplayPose(id: 1, width: 20, height: 10, x: 0, y: 0, z: 50, yawDegrees: 0)
    #expect(valid.compiled(sampleCount: 1) == nil)
    #expect(valid.compiled(sampleCount: 4097) == nil)
    #expect(DisplayPose(id: 1, width: 0, height: 10, x: 0, y: 0, z: 50, yawDegrees: 0).compiled() == nil)
    #expect(DisplayPose(id: 1, width: 20, height: .nan, x: 0, y: 0, z: 50, yawDegrees: 0).compiled() == nil)
    #expect(DisplayPose(id: 1, width: 20, height: 10, x: .infinity, y: 0, z: 50, yawDegrees: 0).compiled() == nil)
    #expect(DisplayPose(id: 1, width: 20, height: 10, x: 0, y: 0, z: 0.5, yawDegrees: 0).compiled() == nil)
}

@Test func interpolationUsesShortestWrappedArc() throws {
    let compiled = CompiledDisplayAngles(id: 2, angles: [179, -179])
    #expect(compiled.strength(at: 0.5, gaze: 180, start: 0, transition: 10) == 0)
    #expect(compiled.strength(at: 0.5, gaze: -170, start: 0, transition: 10) == 1)
}

@Test func zeroTransitionIsHardThresholdAndInvalidInputsFailClosed() throws {
    let compiled = try #require(DisplayPose(id: 1, width: 20, height: 10, x: 0, y: 0, z: 50,
                                             yawDegrees: 0).compiled(sampleCount: 3))
    #expect(compiled.strength(at: 0.5, gaze: 0, start: 0, transition: 0) == 0)
    #expect(compiled.strength(at: 0.5, gaze: 1, start: 0, transition: 0) == 1)
    #expect(compiled.strength(at: .nan, gaze: 0, start: 0, transition: 1) == 1)
    #expect(compiled.strength(at: 0.5, gaze: 0, start: -1, transition: 1) == 1)
    #expect(compiled.strength(at: 0.5, gaze: 0, start: 0, transition: .nan) == 1)
}
