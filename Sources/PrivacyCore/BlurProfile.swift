import Foundation

/// 센서 원래 부호와 무관하게 양수는 오른쪽 회전을 뜻함.
public struct BlurProfile: Sendable, Equatable {
    public var startDegrees: Double
    public var fullDegrees: Double

    public init(startDegrees: Double = 15, fullDegrees: Double = 55) {
        self.startDegrees = startDegrees
        self.fullDegrees = fullDegrees
    }

    public static func relativeDegrees(current: Double, reference: Double) -> Double {
        guard current.isFinite, reference.isFinite else { return .nan }
        let delta = (current - reference).truncatingRemainder(dividingBy: 360)
        return delta > 180 ? delta - 360 : (delta < -180 ? delta + 360 : delta)
    }

    public static func interpolatedDegrees(from: Double, to: Double, fraction: Double) -> Double {
        guard fraction.isFinite else { return .nan }
        let delta = relativeDegrees(current: to, reference: from)
        return relativeDegrees(current: from + delta * min(1, max(0, fraction)), reference: 0)
    }

    public func strength(angle: Double, horizontalPosition x: Double) -> Double {
        guard angle.isFinite, x.isFinite, startDegrees.isFinite, fullDegrees.isFinite,
              startDegrees >= 0, fullDegrees > startDegrees else { return 1 }
        let progress = min(1, max(0, (abs(angle) - startDegrees) / (fullDegrees - startDegrees)))
        let position = min(1, max(0, x))
        let distanceFromHinge = angle >= 0 ? 1 - position : position
        // 양 끝 모두 완전히 가려지되 중간 각도에서는 축에서 먼 쪽이 먼저 가려짐.
        let local = min(1, max(0, progress * 2 - (1 - distanceFromHinge)))
        return local * local * (3 - 2 * local)
    }
}
