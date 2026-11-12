import AppKit

// 상태 카드의 캐릭터 포즈와 말풍선 문구. 화면 배치는 이 파일이 소유하지 않음.

enum CharacterMood: CaseIterable {
    case lost
    case think
    case relax
    case cheer
    case `guard`

    var resourceName: String {
        switch self {
        case .lost: "lost"
        case .think: "think"
        case .relax: "relax"
        case .cheer: "cheer"
        case .guard: "guard"
        }
    }

    var bubble: String {
        switch self {
        case .lost: "AirPods 어디 갔어?"
        case .think: "정면부터 알려 줘요"
        case .relax: "준비 끝!"
        case .cheer: "맞췄다!"
        case .guard: "훔쳐보기 금지!"
        }
    }

    // 기분 규칙의 출처는 Readiness.mood임. 여기서는 정면을 방금 맞춘 1.8초의 cheer만 덧씌움. 보호 중에는 cheer보다 guard가 앞섬.
    static func resolve(base: HeroMood, cheering: Bool) -> CharacterMood {
        switch base {
        case .guard: return .guard
        case .lost: return cheering ? .cheer : .lost
        case .think: return cheering ? .cheer : .think
        case .relax: return cheering ? .cheer : .relax
        }
    }
}

// 가이드 규칙상 좌우 반전, 회전, 색 변경, 잘라내기는 금지함. 표시 시 비율을 유지한 축소만 허용함.
// 그림을 읽지 못하면 nil을 돌려주며 호출부는 그 자리를 비우고 나머지 상태 표시를 그대로 유지함.
@MainActor
enum CharacterArt {
    private static var cache: [CharacterMood: NSImage] = [:]

    static func image(for mood: CharacterMood) -> NSImage? {
        if let cached = cache[mood] { return cached }
        guard let directory = Bundle.main.resourceURL?.appendingPathComponent("Character", isDirectory: true) else {
            return nil
        }
        let url = directory.appendingPathComponent(mood.resourceName).appendingPathExtension("png")
        guard let image = NSImage(contentsOf: url) else { return nil }
        cache[mood] = image
        return image
    }
}
