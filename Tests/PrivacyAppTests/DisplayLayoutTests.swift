import CoreGraphics
import Testing
import PrivacyCore
@testable import PrivacyAirPods

struct DisplayLayoutTests {
    @Test func primaryDisplayOnRightDoesNotBecomeLeftCalibration() {
        let left = DisplayLayout.Screen(id: 55, name: "BK550Y", frame: CGRect(x: -1920, y: 0, width: 1920, height: 1080))
        let right = DisplayLayout.Screen(id: 27, name: "27MB35", frame: CGRect(x: 0, y: 0, width: 1920, height: 1080))
        for input in [[right, left], [left, right]] {
            let result = DisplayLayout.calibrations(for: input)
            #expect(result.map(\.id) == [55, 27])
            #expect(result.map(\.name) == ["왼쪽 · BK550Y", "오른쪽 · 27MB35"])
        }
    }

}

@Test func spatialLayoutPreservesTopAlignmentAcrossDifferentScales() {
    let left = DisplayCalibration(id: 1, name: "left", frame: CGRect(x: -1920, y: 0, width: 1920, height: 1080), widthCM: 60, heightCM: 34)
    let right = DisplayCalibration(id: 2, name: "portrait", frame: CGRect(x: 0, y: -840, width: 1080, height: 1920), widthCM: 30, heightCM: 54)
    let poses = DisplayLayout.spatialPoses(displays: [right, left], gap: 4, viewingDistance: 60)
    #expect(poses.map(\.id) == [2, 1])
    #expect(abs(poses[0].y + 27 - (poses[1].y + 17)) < 0.0001)
    #expect(abs((poses[0].x - 15) - (poses[1].x + 30) - 4) < 0.0001)
    #expect(poses.allSatisfy { $0.z == 60 && $0.yawDegrees == 0 && $0.compiled() != nil })
}

@Test func spatialLayoutPlacesBuiltinBelowExternalAndIgnoresGlobalOrigin() {
    let external = DisplayCalibration(id: 8, name: "external", frame: CGRect(x: -200, y: 1000, width: 2000, height: 1200), widthCM: 60, heightCM: 36)
    let builtin = DisplayCalibration(id: 1, name: "builtin", frame: CGRect(x: 0, y: 0, width: 1600, height: 1000), widthCM: 36, heightCM: 22, builtin: true)
    let inputs = [builtin, external]
    let first = DisplayLayout.spatialPoses(displays: inputs, gap: 2, viewingDistance: 60)
    #expect(first[0].x == first[1].x)
    #expect(first[0].y + 11 == first[1].y - 18 - 2)
    let shifted = inputs.map { display in
        var copy = display
        copy.frame = display.frame.offsetBy(dx: 5000, dy: -2300)
        return copy
    }
    #expect(DisplayLayout.spatialPoses(displays: shifted, gap: 2, viewingDistance: 60) == first)
    #expect(DisplayLayout.spatialPoses(displays: [], gap: 2, viewingDistance: 60).isEmpty)
}
