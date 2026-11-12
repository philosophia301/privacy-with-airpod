import AppKit
import PrivacyCore

struct DisplayCalibration: Identifiable {
    let id: CGDirectDisplayID
    let name: String
    var frame: CGRect = .zero
    var widthCM: Double = 0
    var heightCM: Double = 0
    var builtin = false

}

enum DisplayLayout {
    struct Screen {
        let id: CGDirectDisplayID
        let name: String
        let frame: CGRect
    }

    /// 시스템이 알 수 없는 물리 보정값의 초기값(cm). 사용자는 배치 시트에서 바꿈.
    static let defaultGap = 0.0
    static let defaultViewingDistance = 60.0

    /// 논리 좌표의 인접 관계를 cm 크기에 맞춰 옮김. 포인트 간격은 물리 간격으로 추정하지 않음.
    static func spatialPoses(displays: [DisplayCalibration], gap: Double = defaultGap,
                             viewingDistance: Double = defaultViewingDistance) -> [DisplayPose] {
        guard !displays.isEmpty else { return [] }
        let ordered = displays.sorted {
            if $0.builtin != $1.builtin { return !$0.builtin }
            return leftToRight(($0.id, $0.frame), ($1.id, $1.frame))
        }
        var poses = ordered.map { display in
            let width = display.widthCM.isFinite && display.widthCM > 0 ? display.widthCM : 50
            let height = display.heightCM.isFinite && display.heightCM > 0 ? display.heightCM : width * 9 / 16
            return DisplayPose(id: display.id, width: width, height: height,
                               x: 0, y: 0, z: viewingDistance, yawDegrees: 0)
        }
        let spacing = gap.isFinite ? max(0, gap) : 0
        var placed: Set<Int> = [0]
        while placed.count < ordered.count {
            var best: (parent: Int, child: Int, score: CGFloat)?
            for parent in placed.sorted() {
                for child in ordered.indices where !placed.contains(child) {
                    let a = ordered[parent].frame, b = ordered[child].frame
                    let dx = max(0, max(a.minX - b.maxX, b.minX - a.maxX))
                    let dy = max(0, max(a.minY - b.maxY, b.minY - a.maxY))
                    // 접한 화면을 먼저 연결하고, 같은 접촉 거리에서는 중심이 가까운 쌍을 선택함.
                    let score = hypot(dx, dy) * 1_000_000 + hypot(a.midX - b.midX, a.midY - b.midY)
                    if best == nil || score < best!.score { best = (parent, child, score) }
                }
            }
            guard let edge = best else { break }
            let i = edge.parent, j = edge.child
            let a = ordered[i].frame, b = ordered[j].frame
            let horizontal = abs(b.midX - a.midX) / max(1, (a.width + b.width) / 2)
                >= abs(b.midY - a.midY) / max(1, (a.height + b.height) / 2)
            if horizontal {
                let direction = b.midX >= a.midX ? 1.0 : -1.0
                poses[j].x = poses[i].x + direction * ((poses[i].width + poses[j].width) / 2 + spacing)
                poses[j].y = poses[i].y + alignedOffset(aMin: a.minY, aSize: a.height, bMin: b.minY,
                                                       bSize: b.height, aCM: poses[i].height, bCM: poses[j].height)
            } else {
                let direction = b.midY >= a.midY ? 1.0 : -1.0
                poses[j].y = poses[i].y + direction * ((poses[i].height + poses[j].height) / 2 + spacing)
                poses[j].x = poses[i].x + alignedOffset(aMin: a.minX, aSize: a.width, bMin: b.minX,
                                                       bSize: b.width, aCM: poses[i].width, bCM: poses[j].width)
            }
            placed.insert(j)
        }
        let left = poses.map { $0.x - $0.width / 2 }.min() ?? 0
        let right = poses.map { $0.x + $0.width / 2 }.max() ?? 0
        var center = (left + right) / 2
        // 두 화면에서는 기존의 정면 기준인 이음새를 유지함.
        if poses.count == 2, abs(poses[1].x - poses[0].x) >= (poses[0].width + poses[1].width) / 2 {
            let pair = poses.sorted { $0.x < $1.x }
            center = (pair[0].x + pair[0].width / 2 + pair[1].x - pair[1].width / 2) / 2
        }
        for index in poses.indices { poses[index].x -= center }
        let byID = Dictionary(uniqueKeysWithValues: poses.map { ($0.id, $0) })
        return displays.compactMap { byID[$0.id] }
    }

    private static func alignedOffset(aMin: Double, aSize: Double, bMin: Double,
                                      bSize: Double, aCM: Double, bCM: Double) -> Double {
        guard aSize > 0, bSize > 0 else { return 0 }
        // 공유 구간의 같은 지점을 두 화면의 물리 좌표로 대응시켜 위/아래/중앙 정렬을 보존함.
        let anchor: Double
        if abs(aMin - bMin) < 0.5 { anchor = aMin }
        else if abs(aMin + aSize - bMin - bSize) < 0.5 { anchor = aMin + aSize }
        else { anchor = (max(aMin, bMin) + min(aMin + aSize, bMin + bSize)) / 2 }
        return ((anchor - aMin) / aSize - 0.5) * aCM
            - ((anchor - bMin) / bSize - 0.5) * bCM
    }

    static func calibrations(for screens: [Screen]) -> [DisplayCalibration] {
        // NSScreen의 첫 항목은 주 모니터임. 물리 배치 안내에 배열 순서를 사용하지 않음.
        let ordered = screens.sorted { leftToRight(($0.id, $0.frame), ($1.id, $1.frame)) }
        let horizontalPair = ordered.count == 2 && ordered[0].frame.midX != ordered[1].frame.midX
        return ordered.enumerated().map { index, screen in
            let position = horizontalPair ? (index == 0 ? "왼쪽" : "오른쪽") : "화면 \(index + 1)"
            return DisplayCalibration(id: screen.id, name: "\(position) · \(screen.name)", frame: screen.frame)
        }
    }

    /// 왼쪽, 같은 열이면 위쪽, 그다음 ID 순서임. 화면 목록과 배치 지도가 같은 순서를 씀.
    private static func leftToRight(_ a: (id: CGDirectDisplayID, frame: CGRect),
                                    _ b: (id: CGDirectDisplayID, frame: CGRect)) -> Bool {
        if a.frame.midX != b.frame.midX { return a.frame.midX < b.frame.midX }
        if a.frame.midY != b.frame.midY { return a.frame.midY > b.frame.midY }
        return a.id < b.id
    }
}

extension DisplayLayout {
    /// 현재 연결된 화면과 시스템이 보고한 물리 크기(cm). 회전한 화면은 가로세로를 바꿈.
    @MainActor static func connected(builtInOnly: Bool = LaunchOptions.builtInOnly) -> [DisplayCalibration] {
        let screens = NSScreen.screens.filter { !builtInOnly || CGDisplayIsBuiltin($0.displayID) != 0 }
        return calibrations(for: screens.map { Screen(id: $0.displayID, name: $0.localizedName, frame: $0.frame) })
            .map { display in
                var display = display
                let size = CGDisplayScreenSize(display.id)
                let rotated = Int(CGDisplayRotation(display.id).rounded()) % 180 != 0
                display.widthCM = (rotated ? size.height : size.width) / 10
                display.heightCM = (rotated ? size.width : size.height) / 10
                display.builtin = CGDisplayIsBuiltin(display.id) != 0
                return display
            }
    }
}
