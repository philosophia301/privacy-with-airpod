import Foundation
import CoreGraphics
import PrivacyCore

/// 배치 수정 시트의 지도와 옆 그림이 공유하는 편집 상태. SwiftUI에 의존하지 않음.
/// 좌표 변환, 집기, 끌기, 키보드 조절, 표시값을 여기서만 맡고 뷰는 그리기와 이벤트 전달만 함.
struct LayoutEditor: Equatable {
    /// 지도 캔버스 크기와 1cm당 pt. 지도 좌표는 왼쪽 위가 원점이고 아래로 y가 커짐.
    static let mapSize = CGSize(width: 556, height: 356)
    static let mapScale: CGFloat = 1.85
    /// 머리(관측점)가 지도에서 놓이는 위치임.
    static let mapOrigin = CGPoint(x: 278, y: 328)
    static let sideSize = CGSize(width: 140, height: 110)
    static let sideScale: CGFloat = 0.8
    /// 옆 그림에서 눈 위치임. 가로는 거리, 세로는 높이를 나타냄.
    static let sideOrigin = CGPoint(x: 16, y: 55)
    /// 지도 가로 절반(약 150cm) 안에 화면 끝과 손잡이(바깥 12cm)가 들도록 폭별로 좁힌 x 한계임.
    static func xLimit(width: Double) -> Double {
        max(0, mapSize.width / 2 / Double(mapScale) - 2 - width / 2 - 12)
    }
    static let yRange = -60.0...60.0
    static let zRange = 25.0...150.0
    static let yawRange = -65.0...65.0

    /// 지도에 그릴 한 화면의 도형. body와 face는 지도 점 네 개로 된 사각형임.
    struct MapMonitor: Equatable {
        let id: UInt32
        let left: CGPoint
        let right: CGPoint
        let body: [CGPoint]
        let face: [CGPoint]
        let badge: CGPoint
        let handle: CGPoint
    }

    enum Grip: Equatable {
        case body(UInt32)
        case handle(UInt32)
    }

    /// 진행 중인 끌기. 시작 시점 값만 저장하고 갱신마다 시작점 대비 이동량으로 새 값을 계산함.
    enum Drag: Equatable {
        case move(id: UInt32, start: CGPoint, x: Double, z: Double)
        case twist(id: UInt32)
        case lift(id: UInt32, start: CGPoint, y: Double)
    }

    var poses: [DisplayPose]
    var selected: UInt32
    private(set) var drag: Drag?

    /// selected가 없거나 poses에 없으면 첫 화면을 선택함.
    init(poses: [DisplayPose], selected: UInt32? = nil) {
        self.poses = poses
        if let selected, poses.contains(where: { $0.id == selected }) {
            self.selected = selected
        } else {
            self.selected = poses.first?.id ?? 0
        }
    }

    var selectedPose: DisplayPose? { poses.first { $0.id == selected } }

    var isValid: Bool { !poses.isEmpty && poses.allSatisfy { $0.compiled() != nil } }

    // MARK: 좌표 변환

    static func mapPoint(x: Double, z: Double) -> CGPoint {
        CGPoint(x: mapOrigin.x + CGFloat(x) * mapScale, y: mapOrigin.y - CGFloat(z) * mapScale)
    }

    static func mapWorld(_ point: CGPoint) -> (x: Double, z: Double) {
        (x: Double((point.x - mapOrigin.x) / mapScale), z: Double((mapOrigin.y - point.y) / mapScale))
    }

    static func sidePoint(distance: Double, y: Double) -> CGPoint {
        CGPoint(x: sideOrigin.x + CGFloat(distance) * sideScale, y: sideOrigin.y - CGFloat(y) * sideScale)
    }

    // MARK: 지도 모양

    /// 화면 중심과 yaw로 양 끝, 두께, 손잡이 위치를 지도 점으로 바꿈.
    /// 뒤쪽 방향은 (sin yaw, cos yaw)이고 손잡이는 오른쪽 끝에서 바깥으로 12cm 떨어짐.
    static func mapShape(of pose: DisplayPose) -> MapMonitor {
        let yaw = pose.yawDegrees * .pi / 180
        let across = (x: cos(yaw), z: -sin(yaw))
        let behind = (x: sin(yaw), z: cos(yaw))
        let half = pose.width / 2
        let left = (x: pose.x - half * across.x, z: pose.z - half * across.z)
        let right = (x: pose.x + half * across.x, z: pose.z + half * across.z)
        func point(_ end: (x: Double, z: Double), _ offset: Double) -> CGPoint {
            mapPoint(x: end.x + behind.x * offset, z: end.z + behind.z * offset)
        }
        return MapMonitor(
            id: pose.id,
            left: point(left, 0),
            right: point(right, 0),
            body: [point(left, -1), point(right, -1), point(right, 4.2), point(left, 4.2)],
            face: [point(left, -1), point(right, -1), point(right, 1.2), point(left, 1.2)],
            badge: mapPoint(x: pose.x + behind.x * 13, z: pose.z + behind.z * 13),
            handle: mapPoint(x: right.x + across.x * 12, z: right.z + across.z * 12)
        )
    }

    /// 선택한 화면을 맨 뒤에 둬서 그릴 때 위에 보이게 함.
    var mapMonitors: [MapMonitor] {
        let others = poses.filter { $0.id != selected }
        let chosen = poses.filter { $0.id == selected }
        return (others + chosen).map(Self.mapShape(of:))
    }

    // MARK: 집기

    /// 선택 화면의 손잡이를 먼저 보고, 위에 그려진 순서대로 몸체와 badge를 봄.
    func grip(at point: CGPoint) -> Grip? {
        if let pose = selectedPose, Self.pointDistance(point, Self.mapShape(of: pose).handle) <= 14 {
            return .handle(pose.id)
        }
        return mapMonitors.reversed().first { Self.touches(point, $0) }.map { Grip.body($0.id) }
    }

    private static func touches(_ point: CGPoint, _ monitor: MapMonitor) -> Bool {
        polygonDistance(point, monitor.body) <= 6 || pointDistance(point, monitor.badge) <= 13
    }

    // MARK: 끌기

    /// 집은 화면을 선택하고 몸체면 이동, 손잡이면 회전을 시작함. 집을 것이 없으면 선택을 두고 false를 돌려줌.
    mutating func beginMapDrag(at point: CGPoint) -> Bool {
        guard let hit = grip(at: point) else { return false }
        switch hit {
        case let .body(id):
            selected = id
            guard let pose = pose(id: id) else { return false }
            drag = .move(id: id, start: point, x: pose.x, z: pose.z)
        case let .handle(id):
            selected = id
            drag = .twist(id: id)
        }
        return true
    }

    /// 선택 화면이 있으면 옆 그림에서 높이 끌기를 시작함.
    mutating func beginSideDrag(at point: CGPoint) -> Bool {
        guard let pose = selectedPose else { return false }
        drag = .lift(id: pose.id, start: point, y: pose.y)
        return true
    }

    mutating func updateDrag(to point: CGPoint) {
        switch drag {
        case let .move(id: id, start: start, x: x, z: z)?:
            let dx = Double(point.x - start.x) / Double(Self.mapScale)
            let dz = -Double(point.y - start.y) / Double(Self.mapScale)
            edit(id: id) { pose in
                pose.x = Self.clampX((x + dx).rounded(), width: pose.width)
                pose.z = Self.clamp((z + dz).rounded(), Self.zRange)
            }
        case let .twist(id: id)?:
            let world = Self.mapWorld(point)
            edit(id: id) { pose in
                let degrees = atan2(-(world.z - pose.z), world.x - pose.x) * 180 / .pi
                pose.yawDegrees = Self.clamp(degrees.rounded(), Self.yawRange)
            }
        case let .lift(id: id, start: start, y: y)?:
            let dy = Double(start.y - point.y) / Double(Self.sideScale)
            edit(id: id) { pose in
                pose.y = Self.clamp((y + dy).rounded(), Self.yRange)
            }
        case nil:
            break
        }
    }

    mutating func endDrag() {
        drag = nil
    }

    // MARK: 키보드와 버튼

    mutating func nudge(dx: Double, dz: Double) {
        editSelected { pose in
            pose.x = Self.clampX((pose.x + dx).rounded(), width: pose.width)
            pose.z = Self.clamp((pose.z + dz).rounded(), Self.zRange)
        }
    }

    mutating func rotate(by degrees: Double) {
        editSelected { pose in
            pose.yawDegrees = Self.clamp((pose.yawDegrees + degrees).rounded(), Self.yawRange)
        }
    }

    mutating func setHeight(_ y: Double) {
        editSelected { pose in
            pose.y = Self.clamp(y.rounded(), Self.yRange)
        }
    }

    /// 화면 앞면이 사용자를 향하도록 yaw를 맞춤.
    mutating func faceUser() {
        editSelected { pose in
            let degrees = atan2(pose.x, pose.z) * 180 / .pi
            pose.yawDegrees = Self.clamp(degrees.rounded(), Self.yawRange)
        }
    }

    mutating func flipOrientation() {
        editSelected { pose in
            let width = pose.width
            pose.width = pose.height
            pose.height = width
        }
    }

    // MARK: 표시값

    /// 머리에서 화면 중심까지 거리(cm, 정수)임.
    static func distance(of pose: DisplayPose) -> Int {
        Int(hypot(pose.x, pose.z).rounded())
    }

    /// 화면별 9개 표본(왼쪽 끝부터)의 블러 강도. 실제 보호와 같은 RenderSettings 규칙을 그대로 씀.
    func faceStrengths(gaze: Double, start: Double, transitionFraction: Double,
                       samples: Int = 9) -> [UInt32: [Double]] {
        let tables = poses.compactMap { $0.compiled() }
        guard !tables.isEmpty, samples >= 2 else { return [:] }
        let layout = CompiledLayout(tables: tables)
        var result: [UInt32: [Double]] = [:]
        for table in tables {
            let settings = RenderSettings.spatial(table, in: layout, gaze: gaze, start: start,
                                                  transitionFraction: transitionFraction, radius: 0)
            result[table.id] = (0..<samples).map { index in
                settings.strength(at: Double(index) / Double(samples - 1))
            }
        }
        return result
    }

    // MARK: 내부 갱신

    private func pose(id: UInt32) -> DisplayPose? {
        poses.first { $0.id == id }
    }

    private mutating func edit(id: UInt32, _ change: (inout DisplayPose) -> Void) {
        guard let index = poses.firstIndex(where: { $0.id == id }) else { return }
        change(&poses[index])
    }

    private mutating func editSelected(_ change: (inout DisplayPose) -> Void) {
        edit(id: selected, change)
    }

    private static func clampX(_ value: Double, width: Double) -> Double {
        let limit = xLimit(width: width)
        return min(max(value, -limit), limit)
    }

    private static func clamp(_ value: Double, _ range: ClosedRange<Double>) -> Double {
        min(max(value, range.lowerBound), range.upperBound)
    }

    // MARK: 기하 도우미

    private static func pointDistance(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
        hypot(a.x - b.x, a.y - b.y)
    }

    /// 볼록 다각형까지 거리. 다각형 안쪽이면 0임.
    private static func polygonDistance(_ point: CGPoint, _ polygon: [CGPoint]) -> CGFloat {
        guard polygon.count >= 3 else { return .infinity }
        let next = polygon.indices.map { polygon[($0 + 1) % polygon.count] }
        let crosses = zip(polygon, next).map { a, b in
            (b.x - a.x) * (point.y - a.y) - (b.y - a.y) * (point.x - a.x)
        }
        if crosses.allSatisfy({ $0 >= 0 }) || crosses.allSatisfy({ $0 <= 0 }) { return 0 }
        return zip(polygon, next).map { segmentDistance(point, $0, $1) }.min() ?? .infinity
    }

    private static func segmentDistance(_ point: CGPoint, _ a: CGPoint, _ b: CGPoint) -> CGFloat {
        let dx = b.x - a.x
        let dy = b.y - a.y
        let lengthSquared = dx * dx + dy * dy
        guard lengthSquared > 0 else { return pointDistance(point, a) }
        let t = min(1, max(0, ((point.x - a.x) * dx + (point.y - a.y) * dy) / lengthSquared))
        return pointDistance(point, CGPoint(x: a.x + t * dx, y: a.y + t * dy))
    }
}
