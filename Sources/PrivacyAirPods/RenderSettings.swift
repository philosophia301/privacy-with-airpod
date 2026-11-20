import Foundation
import PrivacyCore

/// 한 화면의 가로 위치별 블러 강도 규칙과 반경. 실제 보호, 설정 미리보기, 배치 지도가 같은 값을 사용함.
struct RenderSettings: Sendable, Equatable {
    enum Field: Sendable, Equatable {
        /// 보정 전, 입력 중단, 출력 오류처럼 위치와 무관하게 모두 가림.
        case covered
        /// 배치 없이 한 화면을 회전축 기준으로 가림. 배치 적용 전 예제와 Blur Lab이 사용함.
        case hinge(BlurProfile, angle: Double)
        /// 적용한 배치의 각도표에서 시선과 각 위치의 각도 차이로 강도를 정함.
        /// 배치 전체는 헤엄 가림이 모든 화면을 한 바다로 이을 때 씀. 블러 강도는 이 화면의 표만으로 정함.
        case spatial(CompiledDisplayAngles, gaze: Double, start: Double, transition: Double, layout: CompiledLayout)
    }

    var field: Field
    var radius: Double
    /// 자리 비움 가림 정도. 0은 고개 따라가기, 1은 위치와 무관한 최대 블러임.
    var coverage: Double

    init(field: Field, radius: Double, coverage: Double = 0) {
        self.field = field
        self.radius = radius
        self.coverage = coverage
    }

    static func covered(radius: Double = 45) -> RenderSettings {
        RenderSettings(field: .covered, radius: radius)
    }

    static func hinge(angle: Double, start: Double = 15, full: Double = 55, radius: Double = 45) -> RenderSettings {
        RenderSettings(field: .hinge(BlurProfile(startDegrees: start, fullDegrees: full), angle: angle), radius: radius)
    }

    /// 배치 전체 시야 폭에 대한 전환 비율을 각도로 바꿔 화면 하나의 설정을 만듦.
    static func spatial(_ table: CompiledDisplayAngles, in layout: CompiledLayout, gaze: Double,
                        start: Double, transitionFraction: Double, radius: Double) -> RenderSettings {
        RenderSettings(field: .spatial(table, gaze: gaze, start: start,
                                       transition: layout.transitionDegrees(fraction: transitionFraction),
                                       layout: layout),
                       radius: radius)
    }

    /// x는 화면 왼쪽 0, 오른쪽 1인 정규화 위치임. 결과 1은 최대 블러임.
    func strength(at x: Double) -> Double {
        // 자리 비움 가림은 고개 값과 무관하게 최대 블러 쪽으로 끌어올림. 판정이 깨진 값은 가리는 쪽으로 둠.
        let cover = min(1, max(0, coverage.isFinite ? coverage : 1))
        return cover + (1 - cover) * followStrength(at: x)
    }

    /// backdrop과 헤엄 경계가 같은 256개 위치, 같은 반올림을 사용함.
    func maskRGBA() -> Data? {
        guard radius.isFinite, radius >= 0 else { return nil }
        var bytes = [UInt8](repeating: 255, count: 256 * 4)
        for x in 0..<256 {
            let value = strength(at: Double(x) / 255)
            guard value.isFinite, (0...1).contains(value) else { return nil }
            bytes[x * 4 + 3] = UInt8((value * 255).rounded())
        }
        return Data(bytes)
    }

    private func followStrength(at x: Double) -> Double {
        switch field {
        case .covered:
            1
        case let .hinge(profile, angle):
            profile.strength(angle: angle, horizontalPosition: x)
        case let .spatial(table, gaze, start, transition, _):
            table.strength(at: x, gaze: gaze, start: start, transition: transition)
        }
    }
}
