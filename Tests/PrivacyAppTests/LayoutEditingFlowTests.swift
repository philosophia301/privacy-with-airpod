import AppKit
import Testing
import PrivacyCore
@testable import PrivacyAirPods

/// 배치 편집기 흐름. 지도 끌기 결과가 실제 AppModel 적용과 WindowServer 가림 마스크까지 이어지는지 확인함.
/// 끌기 좌표는 지도 상수에서 만들고, 기대 각도와 범위는 화면 끝의 독립 기하로 정함.
@MainActor
@Suite(.serialized)
struct LayoutEditingFlowTests {
    @Test func mapDragToSideAppliesAndMasksLikeTheSameLayout() async throws {
        let h = try ProtectionHarness()
        defer { h.tearDown() }
        var editor = LayoutEditor(poses: h.frontLayout)
        let center = LayoutEditor.mapPoint(x: 0, z: 60)
        let grabbedBody = editor.beginMapDrag(at: center)
        #expect(grabbedBody)
        editor.updateDrag(to: CGPoint(x: center.x + 60 * LayoutEditor.mapScale, y: center.y))
        editor.endDrag()
        let pose = try #require(editor.selectedPose)
        #expect(pose.x == 60 && pose.z == 60)

        // 40cm 화면의 왼쪽 끝은 atan2(40, 60) 약 33.7°, 가운데는 45°, 오른쪽 끝은 atan2(80, 60) 약 53.1°임.
        // 시작 각도 35°와 전환 폭 25% 기준에서 왼쪽 끝만 선명하고 나머지는 가려짐.
        let strengths = editor.faceStrengths(gaze: 0, start: h.model.startAngle,
                                             transitionFraction: h.model.connectionWidth / 100)
        let values = try #require(strengths[h.display.id])
        #expect(values.count == 9)
        #expect(values[0] < 0.001)
        #expect(values[4] > 0.999)
        #expect(values[8] > 0.999)

        let panel = try await h.protect(layout: editor.poses)
        #expect(try h.maskAlpha(panel) == [0, 255, 255])
        h.hold(right: 45)
        #expect(try h.maskAlpha(panel) == [0, 0, 0])
    }

    @Test func handleTwistClampsToLimitAndFaceUserYieldsAppliableLayout() throws {
        let h = try ProtectionHarness()
        defer { h.tearDown() }
        let start = DisplayPose(id: h.display.id, width: 40, height: 25, x: 60, y: 0, z: 60, yawDegrees: 0)
        var editor = LayoutEditor(poses: [start])
        // 오른쪽 끝 x 80에서 바깥으로 12cm 떨어진 손잡이를 잡음.
        let grabbedHandle = editor.beginMapDrag(at: LayoutEditor.mapPoint(x: 92, z: 60))
        #expect(grabbedHandle)
        // 화면 중심 바로 앞쪽(z 증가)으로 끌면 방향각이 -90°가 되어 -65°로 잘림.
        editor.updateDrag(to: LayoutEditor.mapPoint(x: 60, z: 120))
        #expect(editor.selectedPose?.yawDegrees == -65)
        editor.endDrag()

        // 사용자 위치를 향하는 방향은 atan2(60, 60) = 45°임.
        editor.faceUser()
        let pose = try #require(editor.selectedPose)
        #expect(pose.x == 60 && pose.z == 60 && pose.yawDegrees == 45)
        #expect(h.model.applyLayout(editor.poses))
        #expect(h.model.appliedPoses == editor.poses)
    }

    @Test func emptyMapPointKeepsSelectionAndOtherScreenBadgeSelectsIt() throws {
        let h = try ProtectionHarness()
        defer { h.tearDown() }
        let otherID = h.display.id &+ 1
        let front = try #require(h.frontLayout.first)
        let other = DisplayPose(id: otherID, width: 40, height: 25, x: 120, y: 0, z: 60, yawDegrees: 0)
        var editor = LayoutEditor(poses: [front, other], selected: otherID)

        // 두 화면에서 멀리 떨어진 지도 점은 집히지 않음.
        let grabbedEmpty = editor.beginMapDrag(at: LayoutEditor.mapPoint(x: -100, z: 100))
        #expect(!grabbedEmpty)
        #expect(editor.selected == otherID)
        #expect(editor.drag == nil)

        // 정면 화면의 badge는 화면 가운데에서 뒤쪽 13cm 위치임.
        let grabbedBadge = editor.beginMapDrag(at: LayoutEditor.mapPoint(x: 0, z: 73))
        #expect(grabbedBadge)
        #expect(editor.selected == h.display.id)
        editor.endDrag()
    }

    @Test func keyboardAndButtonsClampToRangesAndTouchOnlySelectedScreen() throws {
        let h = try ProtectionHarness()
        defer { h.tearDown() }
        let selectedPose = DisplayPose(id: h.display.id, width: 40, height: 25, x: 0, y: 0, z: 60, yawDegrees: 0)
        let other = DisplayPose(id: h.display.id &+ 1, width: 30, height: 20, x: 10, y: 5, z: 80, yawDegrees: 10)
        var editor = LayoutEditor(poses: [selectedPose, other])

        editor.nudge(dx: 200, dz: -100)
        // 화면 끝과 손잡이가 지도 캔버스 안에 남아야 마우스로 집을 수 있음.
        let handle = LayoutEditor.mapShape(of: editor.selectedPose!).handle
        #expect(handle.x <= LayoutEditor.mapSize.width && handle.x > LayoutEditor.mapSize.width - 10)
        #expect(editor.selectedPose?.z == 25)

        editor.setHeight(100)
        #expect(editor.selectedPose?.y == 60)
        editor.rotate(by: 100)
        #expect(editor.selectedPose?.yawDegrees == 65)

        editor.flipOrientation()
        #expect(editor.selectedPose?.width == 25)
        #expect(editor.selectedPose?.height == 40)
        #expect(editor.poses[1] == other)

        // 옆 그림에서 16pt 위로 끌면 0.8pt/cm 기준으로 20cm 오름.
        editor.setHeight(0)
        let start = LayoutEditor.sidePoint(distance: 50, y: 0)
        let grabbedSide = editor.beginSideDrag(at: start)
        #expect(grabbedSide)
        editor.updateDrag(to: CGPoint(x: start.x, y: start.y - 16))
        editor.endDrag()
        #expect(editor.selectedPose?.y == 20)
        #expect(editor.poses[1] == other)
    }
}
