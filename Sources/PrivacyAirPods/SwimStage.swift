import CoreGraphics
import Foundation
import PrivacyCore

/// 한 화면에 그릴 바다 앞단과 치키의 자리. 블러 설정에서 바로 계산함.
///
/// 여러 화면이면 모든 화면이 같은 시선 기준 각도에서 계산하므로 물가, 물 무늬의 깊이, 치키의 위치와 크기가
/// 화면 경계를 이어서 넘음. 앞단마다 바다가 오른쪽에서 들어오는 기준틀 c를 씀. c는 이 화면 폭에 대한 비율이고
/// 바다는 c가 큰 쪽임. 왼쪽에서 들어오는 앞단은 그릴 때 좌우를 뒤집음. 값은 화면 밖(0 미만, 1 초과)도 가짐.
struct SwimStage: Equatable {
    enum Side: Int, CaseIterable { case left, right }

    struct Front: Equatable {
        let side: Side
        /// 물가, 곧 포말 칸 가운데. 물 무늬 깊이는 여기서 0이고 바다 쪽으로 이 화면 폭 하나를 가면 1임.
        let edge: Double
        /// 바다가 배치 끝에서 출발해 지나온 비율(0~1). 치키 자세와 S자 높이를 고름.
        let travel: Double
        /// 이 화면에 걸치지 않으면 nil.
        let actor: Actor?

        var showsWater: Bool { edge - SwimStage.shore < 1 }
    }

    struct Actor: Equatable {
        /// 칸 가운데. x는 기준틀 c, y는 화면 아래 0, 위 1인 비율.
        let x: Double
        let y: Double
        /// 칸 한 변(화면 폭 비율).
        let size: Double
    }

    /// 물가의 블러 강도. 포말 앞 물보라 끝이 블러가 막 시작되는 곳에 닿아 블러와 바다가 함께 움직임.
    static let edgeLevel = 0.1
    /// 포말 칸 반폭(화면 폭 비율). 그림 파일의 물가 칸이 물가 앞뒤로 이만큼을 담음.
    static let shore = 0.11

    let fronts: [Front]

    init(settings: RenderSettings, size: CGSize) {
        switch settings.field {
        case .covered:
            fronts = []
        case let .hinge(profile, angle):
            fronts = Self.hinge(profile, angle: angle, size: size)
        case let .spatial(table, gaze, start, transition, layout):
            fronts = Self.spatial(table, gaze: gaze, start: start, transition: transition, layout: layout, size: size)
        }
    }

    // MARK: 한 화면

    private static func hinge(_ profile: BlurProfile, angle: Double, size: CGSize) -> [Front] {
        let range = profile.fullDegrees - profile.startDegrees
        guard angle.isFinite, profile.startDegrees >= 0, range > 0, size.width > 0, size.height > 0 else { return [] }
        let progress = min(1, max(0, (abs(angle) - profile.startDegrees) / range))
        // BlurProfile.strength의 smoothstep(2p - 1 + c)가 edgeLevel이 되는 c임. 회전축에서 먼 끝이 c = 1임.
        let edge = inverseSmoothstep(edgeLevel) + 1 - 2 * progress
        let travel = clamp(1 - edge)
        let size = 4.6 * min(size.width / 16, size.height / 9) / size.width
        let x = edge + choreography(travel)
        let actor = Actor(x: x, y: 0.5 + wave(travel), size: size)
        // 한 화면만 볼 때는 다 덮은 뒤 물 무늬를 더 밀지 않아 그림 한 장이 화면을 덮은 채로 남음.
        return [Front(side: angle >= 0 ? .left : .right, edge: max(-shore, edge), travel: travel,
                      actor: abs(x - 0.5) < 0.5 + size / 2 ? actor : nil)]
    }

    // MARK: 여러 화면

    private static func spatial(_ table: CompiledDisplayAngles, gaze: Double, start: Double, transition: Double,
                                layout: CompiledLayout, size: CGSize) -> [Front] {
        guard gaze.isFinite, start.isFinite, transition.isFinite, start >= 0, transition >= 0,
              size.width > 0, size.height > 0, let here = Screen(table, gaze: gaze) else { return [] }
        let screens = layout.displays.values.compactMap { Screen($0, gaze: gaze) }.sorted { $0.center < $1.center }
        guard let low = screens.map(\.low).min(), let high = screens.map(\.high).max(), high > low else { return [] }
        let strip = Strip(screens: screens)
        let reach = start + transition * inverseSmoothstep(edgeLevel)
        var fronts = [Front]()
        for side in Side.allCases {
            // 왼쪽 바다는 시선 왼쪽 reach 너머, 오른쪽 바다는 오른쪽 reach 너머임. into는 바다 안쪽 각도 방향임.
            let into: Double = side == .left ? -1 : 1
            let front = into * reach
            let travel = clamp((side == .left ? front - low : high - front) / (high - low))
            // 이 화면의 c = 0 끝이 물가에서 바다 쪽으로 얼마나 깊은지를 지나는 화면마다 그 화면 폭으로 재어 더함.
            // 앞단이 이 화면 안이면 각도표를 거꾸로 읽은 위치와 같고, 화면 경계 양쪽의 깊이가 같아짐.
            let edge = -into * strip.widths(from: front, to: side == .left ? here.high : here.low, preferring: here)
            let center = front + into * choreography(travel) * strip.width(at: front)
            let cell = strip.cell(at: center) / here.width
            let elevation = strip.elevation(at: center) + wave(travel) * strip.height(at: center)
            let actor = Actor(x: here.canonical(center, side), y: here.verticalFraction(elevation), size: cell)
            let rise = cell * size.width / size.height / 2
            let overlaps = abs(actor.x - 0.5) < 0.5 + cell / 2 && abs(actor.y - 0.5) < 0.5 + rise
            let result = Front(side: side, edge: edge, travel: travel, actor: overlaps ? actor : nil)
            if result.showsWater || result.actor != nil { fronts.append(result) }
        }
        return fronts
    }

    // MARK: 공통 동선

    /// 치키 칸 가운데가 물가에서 바다 쪽으로 떨어진 거리(화면 폭). 처음에는 바다 속에서 나오고 끝에는 앞질러 화면을 떠남.
    private static func choreography(_ travel: Double) -> Double {
        let entry = 0.17325 * (1 - ease(travel / 0.143))
        let exit = 0.18325 * ease((travel - 0.88) / 0.12)
        return entry - exit
    }

    /// 화면 높이에 대한 S자 높이 변화. Blender 수정 B 동선임.
    private static func wave(_ travel: Double) -> Double {
        (0.07 + 1.55 * sin(2 * .pi * (1.12 * travel - 0.10))) / 9
    }

    private static func ease(_ x: Double) -> Double {
        let v = clamp(x)
        return v * v * (3 - 2 * v)
    }

    private static func clamp(_ x: Double) -> Double { min(1, max(0, x)) }

    /// smoothstep(t) = y인 t(0~1).
    static func inverseSmoothstep(_ y: Double) -> Double {
        0.5 - sin(asin(1 - 2 * clamp(y)) / 3)
    }
}

/// 시선 기준 상대 각도로 편 화면 하나. 왼쪽 끝 low에서 오른쪽 끝 high로 각도가 커짐.
private struct Screen {
    let low: Double
    let high: Double
    let bottom: Double
    let top: Double
    private let angles: [Double]

    var width: Double { high - low }
    var center: Double { (low + high) / 2 }
    var height: Double { top - bottom }
    /// 치키 칸 한 변(도). 한 화면일 때의 4.6 × min(폭/16, 높이/9)와 같음.
    var cell: Double { 4.6 * min(width / 16, height / 9) }

    /// 오른쪽으로 갈수록 각도가 커지지 않는 화면(뒤를 보거나 뒤집힌 배치)은 헤엄을 그리지 않음.
    /// 높이 각도가 없는 표는 16:9 화면으로 보고 가운데를 0으로 둠.
    init?(_ table: CompiledDisplayAngles, gaze: Double) {
        guard let first = table.angles.first, table.angles.count >= 2 else { return nil }
        var relative = [BlurProfile.relativeDegrees(current: first, reference: gaze)]
        for (previous, angle) in zip(table.angles, table.angles.dropFirst()) {
            let step = BlurProfile.relativeDegrees(current: angle, reference: previous)
            guard step > 0, let last = relative.last else { return nil }
            relative.append(last + step)
        }
        guard let low = relative.first, let high = relative.last, low.isFinite, high.isFinite else { return nil }
        angles = relative
        self.low = low
        self.high = high
        if let elevation = table.elevation {
            bottom = elevation.lowerBound
            top = elevation.upperBound
        } else {
            bottom = -(high - low) * 9 / 32
            top = (high - low) * 9 / 32
        }
    }

    func contains(_ angle: Double) -> Bool { low <= angle && angle <= high }

    /// 상대 각도의 화면 위치(왼쪽 0, 오른쪽 1). 화면 밖은 끝 기울기로 늘려 잼.
    func position(_ angle: Double) -> Double {
        let last = Double(angles.count - 1)
        if angle <= low { return (angle - low) / ((angles[1] - angles[0]) * last) }
        if angle >= high { return 1 + (angle - high) / ((angles[angles.count - 1] - angles[angles.count - 2]) * last) }
        var lower = 0, upper = angles.count - 1
        while upper - lower > 1 {
            let middle = (lower + upper) / 2
            if angles[middle] <= angle { lower = middle } else { upper = middle }
        }
        return (Double(lower) + (angle - angles[lower]) / (angles[upper] - angles[lower])) / last
    }

    func canonical(_ angle: Double, _ side: SwimStage.Side) -> Double {
        side == .left ? 1 - position(angle) : position(angle)
    }

    func verticalFraction(_ elevation: Double) -> Double { (elevation - bottom) / height }
}

/// 배치 전체를 한 줄로 본 것. 화면 사이의 폭, 치키 크기, 높이를 화면 가운데끼리 이어 경계에서 끊기지 않게 함.
private struct Strip {
    let screens: [Screen]

    /// 각도 a에서 b까지(부호 있음)를 지나는 화면마다 그 화면 위치 차이로 잰 합. 화면 안은 각도표를 따르고,
    /// 화면이 없는 틈은 가까운 화면 폭으로 나눔. 겹친 화면은 preferring을 먼저 씀.
    func widths(from a: Double, to b: Double, preferring here: Screen) -> Double {
        guard a != b else { return 0 }
        let lower = min(a, b), upper = max(a, b)
        let ends = ([here] + screens).flatMap { [$0.low, $0.high] }.filter { lower < $0 && $0 < upper }
        let cuts = ([lower, upper] + ends).sorted()
        var total = 0.0
        for (p, q) in zip(cuts, cuts.dropFirst()) where q > p {
            let middle = (p + q) / 2
            if let screen = ([here] + screens).first(where: { $0.contains(middle) }) {
                total += screen.position(q) - screen.position(p)
            } else {
                total += (q - p) / width(at: middle)
            }
        }
        return b > a ? total : -total
    }

    /// 각도 a를 담은 화면의 폭(도). 없으면 가장 가까운 화면 폭.
    func width(at angle: Double) -> Double {
        if let screen = screens.first(where: { $0.contains(angle) }) { return screen.width }
        let nearest = screens.min { distance($0, angle) < distance($1, angle) }
        return nearest?.width ?? 1
    }

    func cell(at angle: Double) -> Double { interpolate(angle, \.cell) }
    func elevation(at angle: Double) -> Double { interpolate(angle, { ($0.bottom + $0.top) / 2 }) }
    func height(at angle: Double) -> Double { interpolate(angle, \.height) }

    private func distance(_ screen: Screen, _ angle: Double) -> Double {
        angle < screen.low ? screen.low - angle : angle - screen.high
    }

    /// 화면 가운데를 마디로 한 꺾은선. 양 끝 화면 바깥은 끝 화면 값을 씀.
    private func interpolate(_ angle: Double, _ value: (Screen) -> Double) -> Double {
        guard let first = screens.first, let last = screens.last else { return 0 }
        if angle <= first.center { return value(first) }
        if angle >= last.center { return value(last) }
        for (left, right) in zip(screens, screens.dropFirst()) where angle <= right.center {
            let fraction = (angle - left.center) / (right.center - left.center)
            return value(left) + (value(right) - value(left)) * fraction
        }
        return value(last)
    }
}
