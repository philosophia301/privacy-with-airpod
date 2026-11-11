import Foundation

/// Size Korea 인체항목 검색, 8차·20~69세 조회. 팔길이는 어깨~손목 체표 길이임.
/// 조회 조건과 원본 수치는 docs/development.md의 3D 조작 피드백에 기록함.
enum HumanGuide: String, CaseIterable {
    case female = "여성"
    case male = "남성"

    var armLengthCM: Double {
        switch self {
        case .female: 53.012
        case .male: 58.198
        }
    }
}
