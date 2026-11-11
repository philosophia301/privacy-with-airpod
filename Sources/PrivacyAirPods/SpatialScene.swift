import SwiftUI
import SceneKit
import PrivacyCore
import CoreImage

@MainActor
final class MonitorSceneView: SCNView {
    var onMonitorSelection: ((UInt32) -> Void)?
    var monitorIDForNode: ((SCNNode) -> UInt32?)?

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if !selectMonitor(at: point) { super.mouseDown(with: event) }
    }

    @discardableResult
    func selectMonitor(at point: CGPoint) -> Bool {
        guard let hit = hitTest(point, options: [.ignoreHiddenNodes: true]).first,
              let id = monitorIDForNode?(hit.node) else {
            return false
        }
        onMonitorSelection?(id)
        return true
    }
}

/// 설정 창에만 존재함. 실제 보호는 이 뷰나 SceneKit에 의존하지 않음.
struct SpatialScene: NSViewRepresentable {
    let poses: [DisplayPose]
    @Binding var selected: UInt32
    let gaze: Double
    let start: Double
    /// 전체 시야 폭에 대한 전환 폭 비율(0~1). 실제 보호와 같은 규칙으로 각도로 바꿈.
    let transitionFraction: Double
    let radius: Double
    let armLength: Double
    let avatar: HumanGuide
    let camera: Int

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> SCNView {
        let view = MonitorSceneView()
        configureSelection(on: view, coordinator: context.coordinator)
        view.scene = context.coordinator.scene
        view.pointOfView = context.coordinator.camera
        view.allowsCameraControl = false
        view.backgroundColor = NSColor(calibratedRed: 0.055, green: 0.075, blue: 0.12, alpha: 1)
        view.antialiasingMode = .multisampling4X
        view.rendersContinuously = false
        view.isPlaying = false
        view.preferredFramesPerSecond = 20
        return view
    }

    func updateNSView(_ view: SCNView, context: Context) {
        configureSelection(on: view, coordinator: context.coordinator)
        context.coordinator.update(self, in: view)
        view.needsDisplay = true
    }

    static func dismantleNSView(_ view: SCNView, coordinator: Coordinator) {
        (view as? MonitorSceneView)?.onMonitorSelection = nil
        (view as? MonitorSceneView)?.monitorIDForNode = nil
        view.isPlaying = false
        view.scene = nil
    }

    private func configureSelection(on view: SCNView, coordinator: Coordinator) {
        guard let view = view as? MonitorSceneView else { return }
        view.monitorIDForNode = coordinator.monitorID(from:)
        let selection = _selected
        view.onMonitorSelection = { id in selection.wrappedValue = id }
    }

    @MainActor final class Coordinator {
        let scene = SCNScene()
        let camera = SCNNode()
        private let screens = SCNNode()
        private let person = SCNNode()
        private let ray = SCNNode()
        private let renderer = BlurRenderer()
        private let example = ExampleScreen.make().transformed(by: CGAffineTransform(scaleX: 0.4, y: 0.4))
        private var previousPoses: [DisplayPose] = []
        private var previousTextureKey: [Double] = []
        private var previousPersonKey = ""
        private var previousCamera = -1
        private var surfaces: [UInt32: SCNNode] = [:]
        private var frames: [UInt32: SCNNode] = [:]

        init() {
            camera.camera = SCNCamera()
            camera.camera?.zFar = 2000
            camera.camera?.zNear = 0.5
            scene.rootNode.addChildNode(camera)
            let ambient = SCNNode()
            ambient.light = SCNLight(); ambient.light?.type = .ambient
            ambient.light?.intensity = 650
            scene.rootNode.addChildNode(ambient)
            let light = SCNNode()
            light.light = SCNLight(); light.light?.type = .omni
            light.light?.intensity = 1100; light.position = SCNVector3(-80, 140, 80)
            scene.rootNode.addChildNode(light)
            let desk = box(width: 210, height: 3, depth: 110, color: NSColor(calibratedRed: 0.2, green: 0.24, blue: 0.31, alpha: 1))
            desk.position = SCNVector3(0, -38, -45)
            scene.rootNode.addChildNode(desk)
            scene.rootNode.addChildNode(screens)
            scene.rootNode.addChildNode(person)
            scene.rootNode.addChildNode(ray)
        }

        func selectCamera(_ preset: Int, in view: SCNView) {
            guard previousCamera != preset else { return }
            previousCamera = preset
            view.defaultCameraController.stopInertia()
            camera.position = preset == 1 ? SCNVector3(0, 155, -44)
                : preset == 2 ? SCNVector3(0, 0, 0) : SCNVector3(85, 75, 95)
            camera.camera?.fieldOfView = preset == 2 ? 75 : 45
            camera.look(at: preset == 2 ? SCNVector3(0, 0, -60) : SCNVector3(0, -10, -45),
                        up: preset == 1 ? SCNVector3(0, 0, -1) : SCNVector3(0, 1, 0),
                        localFront: SCNVector3(0, 0, -1))
            // 자유 회전 시 SceneKit이 별도 카메라를 사용하므로 실제 표시 시점도 되돌림.
            view.defaultCameraController.pointOfView = camera
            view.defaultCameraController.target = SCNVector3(0, -10, -45)
            view.pointOfView = camera
        }

        func monitorID(from node: SCNNode) -> UInt32? {
            var candidate: SCNNode? = node
            while let node = candidate {
                if let name = node.name, name.hasPrefix("monitor:") {
                    return UInt32(name.dropFirst("monitor:".count))
                }
                candidate = node.parent
            }
            return nil
        }

        func update(_ state: SpatialScene, in view: SCNView) {
            SCNTransaction.begin(); SCNTransaction.animationDuration = 0
            defer { SCNTransaction.commit() }
            selectCamera(state.camera, in: view)
            if previousPoses != state.poses {
                previousPoses = state.poses
                screens.childNodes.forEach { $0.removeFromParentNode() }
                surfaces = [:]
                frames = [:]
                for pose in state.poses where pose.compiled() != nil {
                    let group = SCNNode()
                    group.name = "monitor:\(pose.id)"
                    group.position = SCNVector3(pose.x, pose.y, -pose.z)
                    group.eulerAngles.y = CGFloat(-pose.yawDegrees * .pi / 180)
                    let frame = box(width: pose.width + 1.8, height: pose.height + 1.8, depth: 1.5, color: .darkGray)
                    group.addChildNode(frame)
                    let plane = SCNPlane(width: pose.width, height: pose.height)
                    plane.firstMaterial?.lightingModel = .constant
                    plane.firstMaterial?.isDoubleSided = true
                    let surface = SCNNode(geometry: plane)
                    surface.position.z = 0.85
                    group.addChildNode(surface)
                    screens.addChildNode(group)
                    surfaces[pose.id] = surface
                    frames[pose.id] = frame
                    let stand = box(width: 3, height: max(3, pose.y + 38 - pose.height / 2), depth: 3, color: .darkGray)
                    stand.position = SCNVector3(pose.x, (-38 + pose.y - pose.height / 2) / 2, -pose.z)
                    screens.addChildNode(stand)
                }
                previousTextureKey = []
            }
            for (id, frame) in frames {
                frame.geometry?.firstMaterial?.diffuse.contents = id == state.selected ? NSColor.systemYellow : NSColor.darkGray
            }
            let personKey = "\(state.armLength)-\(state.avatar)"
            if previousPersonKey != personKey {
                previousPersonKey = personKey
                person.childNodes.forEach { $0.removeFromParentNode() }
                let tint: NSColor = switch state.avatar {
                case .female: .systemPurple
                case .male: .systemTeal
                }
                let head = SCNNode(geometry: SCNSphere(radius: 8))
                head.geometry?.firstMaterial?.diffuse.contents = NSColor(calibratedRed: 0.86, green: 0.73, blue: 0.61, alpha: 1)
                head.name = "head"
                person.addChildNode(head)
                let torso = box(width: 26, height: 33, depth: 15, color: tint)
                torso.position = SCNVector3(0, -25, 4); person.addChildNode(torso)
                for x in [-14.0, 14.0] {
                    person.addChildNode(segment(from: SCNVector3(x, -14, 0), to: SCNVector3(x, -14, -state.armLength), radius: 3, color: tint))
                    let hand = SCNNode(geometry: SCNSphere(radius: 3.6))
                    hand.geometry?.firstMaterial?.diffuse.contents = NSColor.systemOrange
                    hand.position = SCNVector3(x, -14, -state.armLength); person.addChildNode(hand)
                }
            }
            person.eulerAngles.y = CGFloat(-state.gaze * .pi / 180)
            ray.isHidden = state.camera == 2
            person.childNode(withName: "head", recursively: false)?.isHidden = state.camera == 2
            if state.camera == 2 {
                camera.eulerAngles = SCNVector3(0, -state.gaze * .pi / 180, 0)
            }
            let key = [state.gaze.rounded(), state.start, state.transitionFraction, state.radius]
            if key != previousTextureKey {
                previousTextureKey = key
                let layout = CompiledLayout(tables: state.poses.compactMap { $0.compiled() })
                for table in layout.displays.values {
                    let setting = RenderSettings.spatial(table, in: layout, gaze: key[0], start: state.start,
                                                         transitionFraction: state.transitionFraction,
                                                         radius: state.radius)
                    surfaces[table.id]?.geometry?.firstMaterial?.diffuse.contents = renderer.render(example, settings: setting)
                }
                ray.childNodes.forEach { $0.removeFromParentNode() }
                let angle = key[0] * .pi / 180
                ray.addChildNode(segment(from: SCNVector3(0, 0, -9), to: SCNVector3(sin(angle) * 135, 0, -cos(angle) * 135), radius: 0.55, color: .systemMint))
            }
        }

        private func box(width: Double, height: Double, depth: Double, color: NSColor) -> SCNNode {
            let box = SCNBox(width: width, height: height, length: depth, chamferRadius: min(1.2, depth / 3))
            box.firstMaterial?.diffuse.contents = color
            box.firstMaterial?.roughness.contents = 0.7
            return SCNNode(geometry: box)
        }

        private func segment(from: SCNVector3, to: SCNVector3, radius: Double, color: NSColor) -> SCNNode {
            let a = SIMD3<Float>(Float(from.x), Float(from.y), Float(from.z))
            let b = SIMD3<Float>(Float(to.x), Float(to.y), Float(to.z))
            let delta = b - a
            let node = SCNNode(geometry: SCNCylinder(radius: radius, height: CGFloat(simd_length(delta))))
            node.geometry?.firstMaterial?.diffuse.contents = color
            node.simdPosition = (a + b) / 2
            node.simdOrientation = simd_quatf(from: SIMD3<Float>(0, 1, 0), to: simd_normalize(delta))
            return node
        }
    }
}
