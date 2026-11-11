import Foundation

/// 책상 정면을 원점으로 두고 실제 길이와 시청 거리로 펼친 연속 시야.
public struct PanoramaProfile: Sendable, Equatable {
    public let leftWidth: Double
    public let rightWidth: Double
    public let gap: Double
    public let viewingDistance: Double
    public let frontPosition: Double
    public let startDegrees: Double
    public let transitionFraction: Double

    public init?(leftWidth: Double, rightWidth: Double, gap: Double, viewingDistance: Double,
                 frontPosition: Double, startDegrees: Double, transitionFraction: Double) {
        guard [leftWidth, rightWidth, gap, viewingDistance, frontPosition, startDegrees, transitionFraction].allSatisfy(\.isFinite),
              leftWidth > 0, rightWidth > 0, gap >= 0, viewingDistance > 0,
              startDegrees >= 0, transitionFraction >= 0, transitionFraction <= 0.5 else { return nil }
        self.leftWidth = leftWidth
        self.rightWidth = rightWidth
        self.gap = gap
        self.viewingDistance = viewingDistance
        self.frontPosition = frontPosition
        self.startDegrees = startDegrees
        self.transitionFraction = transitionFraction
    }

    public var totalWidth: Double { leftWidth + gap + rightWidth }
    public var rightOrigin: Double { leftWidth + gap }

    public func angle(at position: Double) -> Double {
        atan2(position - frontPosition, viewingDistance) * 180 / .pi
    }

    public func strength(at position: Double, gaze: Double) -> Double {
        guard position.isFinite, gaze.isFinite else { return 1 }
        let distance = abs(BlurProfile.relativeDegrees(current: gaze, reference: angle(at: position)))
        let transition = (angle(at: totalWidth) - angle(at: 0)) * transitionFraction
        guard transition > 0 else { return distance > startDegrees ? 1 : 0 }
        let progress = min(1, max(0, (distance - startDegrees) / transition))
        return progress * progress * (3 - 2 * progress)
    }
}

public struct PanoramaSlice: Sendable, Equatable {
    public let profile: PanoramaProfile
    public let origin: Double
    public let width: Double
    public let gaze: Double

    public init(profile: PanoramaProfile, origin: Double, width: Double, gaze: Double) {
        self.profile = profile
        self.origin = origin
        self.width = width
        self.gaze = gaze
    }

    public func strength(at x: Double) -> Double {
        profile.strength(at: origin + x * width, gaze: gaze)
    }
}
