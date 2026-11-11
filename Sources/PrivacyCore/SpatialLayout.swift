import Foundation

/// 관측점에서 바라본 한 디스플레이의 물리적 자세. 모든 길이 단위는 cm임.
public struct DisplayPose: Sendable, Equatable {
    public var id: UInt32
    public var width: Double
    public var height: Double
    public var x: Double
    public var y: Double
    public var z: Double
    public var yawDegrees: Double

    public init(id: UInt32, width: Double, height: Double, x: Double, y: Double, z: Double,
                yawDegrees: Double) {
        self.id = id
        self.width = width
        self.height = height
        self.x = x
        self.y = y
        self.z = z
        self.yawDegrees = yawDegrees
    }

    /// 화면을 일정 간격으로 샘플링해 각도 계산을 미리 수행함.
    public func compiled(sampleCount: Int = 256) -> CompiledDisplayAngles? {
        guard width.isFinite, height.isFinite, x.isFinite, y.isFinite, z.isFinite,
              yawDegrees.isFinite, width > 0, height > 0, (2...4096).contains(sampleCount) else {
            return nil
        }

        let yaw = yawDegrees * .pi / 180
        let cosine = cos(yaw)
        let sine = sin(yaw)
        var angles = [Double]()
        angles.reserveCapacity(sampleCount)
        for index in 0..<sampleCount {
            let u = Double(index) / Double(sampleCount - 1)
            let localX = (u - 0.5) * width
            let worldX = x + localX * cosine
            let worldZ = z - localX * sine
            guard worldX.isFinite, worldZ.isFinite, worldZ > 1 else { return nil }
            angles.append(atan2(worldX, worldZ) * 180 / .pi)
        }
        return CompiledDisplayAngles(id: id, angles: angles)
    }
}

public struct CompiledDisplayAngles: Sendable, Equatable {
    public let id: UInt32
    public let angles: [Double]
    public let minimumAngle: Double
    public let maximumAngle: Double
    private let valid: Bool

    public init(id: UInt32, angles: [Double]) {
        self.id = id
        self.valid = angles.count >= 2 && angles.allSatisfy(\.isFinite)
        self.angles = angles
        self.minimumAngle = angles.min() ?? .nan
        self.maximumAngle = angles.max() ?? .nan
    }

    /// 정규화 화면 위치 x에서 gaze에 대한 블러 강도를 계산함.
    public func strength(at x: Double, gaze: Double, start: Double, transition: Double) -> Double {
        guard x.isFinite, gaze.isFinite, start.isFinite, transition.isFinite,
              (0...1).contains(x), start >= 0, transition >= 0,
              valid else { return 1 }

        let scaled = x * Double(angles.count - 1)
        let lower = min(angles.count - 2, Int(scaled.rounded(.down)))
        let fraction = scaled - Double(lower)
        let angle = BlurProfile.interpolatedDegrees(from: angles[lower], to: angles[lower + 1],
                                                    fraction: fraction)
        let distance = abs(BlurProfile.relativeDegrees(current: angle, reference: gaze))
        guard distance.isFinite else { return 1 }
        if transition == 0 { return distance > start ? 1 : 0 }

        let progress = min(1, max(0, (distance - start) / transition))
        return progress * progress * (3 - 2 * progress)
    }
}
