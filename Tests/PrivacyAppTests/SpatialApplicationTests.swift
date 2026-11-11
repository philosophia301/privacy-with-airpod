import Testing
import PrivacyCore
@testable import PrivacyAirPods

@MainActor
@Test func draftEditsDoNotChangeAppliedAnglesAndInvalidApplyPreservesPreviousLayout() throws {
    let model = AppModel()
    model.displays = [DisplayCalibration(id: 11, name: "left"), DisplayCalibration(id: 12, name: "right")]
    var poses = [DisplayPose(id: 11, width: 60, height: 34, x: -30, y: 0, z: 60, yawDegrees: 0),
                 DisplayPose(id: 12, width: 60, height: 34, x: 30, y: 0, z: 60, yawDegrees: 0)]
    #expect(model.applyLayout(poses))
    let before = model.settingsByDisplay(previewAngle: 60)
    #expect(try #require(before[11]).strength(at: 0) > #require(before[12]).strength(at: 1))
    poses[0].yawDegrees = 30
    #expect(model.settingsByDisplay(previewAngle: 60) == before)
    #expect(model.applyLayout(poses))
    #expect(model.settingsByDisplay(previewAngle: 60) != before)
    let applied = model.appliedPoses
    poses[0].z = 0
    #expect(!model.applyLayout(poses))
    #expect(model.appliedPoses == applied)
    #expect(!model.applyLayout([applied[0], applied[0]]))
    model.protected = true
    #expect(!model.applyLayout(applied))
    model.protected = false
    model.stopMotion()
}
