import SceneKit
import Testing
@testable import PrivacyAirPods

@MainActor
@Test func cameraPresetsRestoreLevelViewsAndPlaceFrontAtEyes() {
    let coordinator = SpatialScene.Coordinator()
    let view = SCNView()
    view.scene = coordinator.scene
    view.allowsCameraControl = true
    coordinator.selectCamera(0, in: view)
    let orbitCamera = SCNNode()
    orbitCamera.camera = SCNCamera()
    view.pointOfView = orbitCamera
    coordinator.camera.eulerAngles.z = 1.2
    coordinator.selectCamera(1, in: view)
    #expect(view.pointOfView === coordinator.camera)
    #expect(view.defaultCameraController.pointOfView === coordinator.camera)
    #expect(coordinator.camera.position.y == 155)
    #expect(coordinator.camera.simdWorldUp.z < -0.99)
    view.pointOfView = orbitCamera
    coordinator.selectCamera(1, in: view)
    #expect(view.pointOfView === orbitCamera)
    coordinator.selectCamera(2, in: view)
    #expect(view.pointOfView === coordinator.camera)
    #expect(coordinator.camera.position.z == 0)
    #expect(coordinator.camera.position.x == 0)
    #expect(coordinator.camera.position.y == 0)
    #expect(coordinator.camera.simdWorldFront.z < -0.99)
    #expect(coordinator.camera.simdWorldUp.y > 0.98)
    view.scene = nil
}
