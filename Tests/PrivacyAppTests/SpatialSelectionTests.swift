import AppKit
import SceneKit
import Testing
@testable import PrivacyAirPods

@MainActor
@Test func monitorHitTestSelectsAncestorIDAndLeavesSelectionForOtherNodes() {
    let coordinator = SpatialScene.Coordinator()
    let scene = SCNScene()
    let camera = SCNNode()
    camera.camera = SCNCamera()
    camera.camera?.usesOrthographicProjection = true
    camera.camera?.orthographicScale = 200
    camera.position = SCNVector3(0, 0, 100)
    camera.look(at: SCNVector3(0, 0, 0), up: SCNVector3(0, 1, 0), localFront: SCNVector3(0, 0, -1))
    scene.rootNode.addChildNode(camera)

    let monitor = SCNNode()
    monitor.name = "monitor:42"
    let bezel = SCNNode()
    bezel.addChildNode(SCNNode(geometry: SCNPlane(width: 50, height: 50)))
    monitor.addChildNode(bezel)
    scene.rootNode.addChildNode(monitor)

    let otherNode = SCNNode(geometry: SCNBox(width: 12, height: 12, length: 12, chamferRadius: 0))
    otherNode.position = SCNVector3(70, 0, 0)
    scene.rootNode.addChildNode(otherNode)

    let view = MonitorSceneView(frame: CGRect(x: 0, y: 0, width: 200, height: 200))
    view.scene = scene
    view.pointOfView = camera
    view.monitorIDForNode = coordinator.monitorID(from:)
    var selected: UInt32 = 7
    view.onMonitorSelection = { selected = $0 }

    let monitorProjection = view.projectPoint(SCNVector3(0, 0, 0))
    let monitorPoint = CGPoint(x: CGFloat(monitorProjection.x), y: CGFloat(monitorProjection.y))
    #expect(view.selectMonitor(at: monitorPoint))
    #expect(selected == 42)

    let otherProjection = view.projectPoint(otherNode.position)
    let otherPoint = CGPoint(x: CGFloat(otherProjection.x), y: CGFloat(otherProjection.y))
    #expect(!view.selectMonitor(at: otherPoint))
    #expect(selected == 42)
    #expect(!view.selectMonitor(at: CGPoint(x: 10, y: 190)))
    #expect(selected == 42)
}
