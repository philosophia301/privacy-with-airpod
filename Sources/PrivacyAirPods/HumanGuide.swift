import Foundation

/// Size Korea 인체항목 검색, 8차·20~69세 조회. 팔길이는 어깨~손목 체표 길이임.
/// 배치 시트의 손끝 고리 기본값으로 씀. 조회 조건과 원본 수치는 docs/development.md에 기록함.
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
