import Foundation
import PrivacyCore

/// 설정과 모니터 조합별 배치를 이 Mac의 UserDefaults에 저장하고 읽는 경계.
/// 값이 없거나 깨졌거나 형식이 다르면 nil을 돌려주어 호출한 쪽이 기본값을 쓰게 함. 외부로 보내지 않음.
struct SettingsMemory {
    static let settingsKey = "settings.v1"
    static let layoutsKey = "layouts.v1"

    let defaults: UserDefaults

    func loadSettings() -> StoredSettings? {
        guard let data = defaults.data(forKey: Self.settingsKey),
              let stored = try? JSONDecoder().decode(StoredSettings.self, from: data) else { return nil }
        return stored.clamped
    }

    func saveSettings(_ settings: StoredSettings) {
        guard let data = try? JSONEncoder().encode(settings) else { return }
        defaults.set(data, forKey: Self.settingsKey)
    }

    func loadLayout(for key: String) -> [StoredPose]? {
        guard let entry = loadLayoutEntries()[key] else { return nil }
        return try? JSONDecoder().decode([StoredPose].self, from: entry)
    }

    /// 조합마다 한 항목씩 담으므로 다른 조합의 배치는 건드리지 않음.
    func saveLayout(_ poses: [StoredPose], for key: String) {
        guard let entry = try? JSONEncoder().encode(poses) else { return }
        var entries = loadLayoutEntries()
        entries[key] = entry
        // Data는 base64로 감싸지므로 항목을 JSON 객체로 되돌려 한 파일로 묶음.
        let merged = entries.compactMapValues { try? JSONSerialization.jsonObject(with: $0) }
        guard let data = try? JSONSerialization.data(withJSONObject: merged) else { return }
        defaults.set(data, forKey: Self.layoutsKey)
    }

    /// 항목을 해석하지 않은 채 조합별로 나눠 읽음. 한 항목이 깨져도 다른 조합의 배치는 지켜짐.
    private func loadLayoutEntries() -> [String: Data] {
        guard let data = defaults.data(forKey: Self.layoutsKey),
              let raw = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [:] }
        return raw.compactMapValues { try? JSONSerialization.data(withJSONObject: $0) }
    }
}

/// 가리기 값, 입력 중단 정책, 팔 길이, 모형. 범위는 HideTab과 LayoutSheet 슬라이더와 같아야 함.
struct StoredSettings: Codable, Equatable {
    var startAngle: Double
    var maximumBlur: Double
    var connectionWidth: Double
    var responseTime: Double
    var retainBlurOnInputLoss: Bool
    /// 자리를 뜨면 가리기 스위치. 이 키가 없는 이전 형식은 기본값 켜짐으로 읽음.
    var hideWhenAway: Bool
    var armLengthCM: Double
    var armGuide: StoredGuide

    /// 손으로 고친 파일처럼 범위를 벗어난 값도 크래시 없이 슬라이더가 만들 수 있는 값으로 자름.
    var clamped: StoredSettings {
        var value = self
        value.startAngle = Self.clamp(startAngle, 0...45)
        value.maximumBlur = Self.clamp(maximumBlur, 15...80)
        value.connectionWidth = Self.clamp(connectionWidth, 0...50)
        value.responseTime = Self.clamp(responseTime, 0.03...0.5)
        value.armLengthCM = Self.clamp(armLengthCM, 40...85)
        return value
    }

    /// NaN은 범위 어디에도 속하지 않으므로 하한으로 보냄.
    private static func clamp(_ value: Double, _ range: ClosedRange<Double>) -> Double {
        value.isNaN ? range.lowerBound : min(max(value, range.lowerBound), range.upperBound)
    }
}

// 확장에 둬서 memberwise init을 유지함. hideWhenAway만 없어도 되게 읽고 나머지는 이전과 같이 필수로 읽음.
extension StoredSettings {
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        startAngle = try container.decode(Double.self, forKey: .startAngle)
        maximumBlur = try container.decode(Double.self, forKey: .maximumBlur)
        connectionWidth = try container.decode(Double.self, forKey: .connectionWidth)
        responseTime = try container.decode(Double.self, forKey: .responseTime)
        retainBlurOnInputLoss = try container.decode(Bool.self, forKey: .retainBlurOnInputLoss)
        hideWhenAway = try container.decodeIfPresent(Bool.self, forKey: .hideWhenAway) ?? true
        armLengthCM = try container.decode(Double.self, forKey: .armLengthCM)
        armGuide = try container.decode(StoredGuide.self, forKey: .armGuide)
    }
}

/// 모형의 저장 키. 화면 문구인 HumanGuide.rawValue를 저장하면 문구를 고칠 때 기억이 깨지므로 따로 둠.
enum StoredGuide: String, Codable {
    case female
    case male

    init(_ guide: HumanGuide) {
        switch guide {
        case .female: self = .female
        case .male: self = .male
        }
    }

    var guide: HumanGuide {
        switch self {
        case .female: .female
        case .male: .male
        }
    }
}

/// 한 화면의 배치. 화면 id는 재부팅 뒤 바뀌므로 UUID로 대응시키고, 방향은 저장 당시 상태를 기록함.
struct StoredPose: Codable, Equatable {
    var uuid: String
    var width: Double
    var height: Double
    var x: Double
    var y: Double
    var z: Double
    var yawDegrees: Double
    /// 저장 당시 세로 화면이었는지. 회전이 바뀐 화면은 같은 UUID여도 배치를 되살리지 않음.
    var portrait: Bool
}

extension SettingsMemory {
    /// 연결된 화면 UUID를 정렬해 이은 조합 키. UUID가 없거나 겹치면 nil이라 저장도 복원도 하지 않음.
    static func combinationKey(for displays: [DisplayCalibration]) -> String? {
        guard !displays.isEmpty, hasDistinctUUIDs(displays) else { return nil }
        return displays.map(\.uuid).sorted().joined(separator: ",")
    }

    /// 적용한 배치의 화면 id를 UUID로 바꿈. 대응하는 화면이 하나라도 없으면 nil.
    static func storedPoses(_ poses: [DisplayPose], displays: [DisplayCalibration]) -> [StoredPose]? {
        let byID = Dictionary(displays.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let stored = poses.compactMap { pose -> StoredPose? in
            guard let display = byID[pose.id] else { return nil }
            return StoredPose(uuid: display.uuid, width: pose.width, height: pose.height,
                              x: pose.x, y: pose.y, z: pose.z, yawDegrees: pose.yawDegrees,
                              portrait: display.isPortrait)
        }
        return stored.count == poses.count ? stored : nil
    }

    /// 저장 배치를 현재 화면 id에 대응시킴. 화면 수, UUID 집합, 저장 당시 방향이 모두 같을 때만 돌려줌.
    /// 저장 순서를 그대로 유지해 적용 배치와 같은 순서가 되게 함.
    static func restoredPoses(_ stored: [StoredPose], displays: [DisplayCalibration]) -> [DisplayPose]? {
        guard !displays.isEmpty, hasDistinctUUIDs(displays), stored.count == displays.count else { return nil }
        let byUUID = Dictionary(uniqueKeysWithValues: displays.map { ($0.uuid, $0) })
        var seen = Set<String>()
        let poses = stored.compactMap { item -> DisplayPose? in
            guard seen.insert(item.uuid).inserted, let display = byUUID[item.uuid],
                  display.isPortrait == item.portrait else { return nil }
            // 앱이 적용할 수 없는 값만 손상으로 보고 거름. 편집기 범위로 자르면 손대지 않은 기본 배치
            // (세 화면을 위아래로 쌓아 높이가 60cm를 넘는 경우 등)가 되살아나지 않음.
            guard [item.x, item.y, item.z, item.width, item.height, item.yawDegrees].allSatisfy(\.isFinite),
                  item.width > 0, item.height > 0, item.z > 0,
                  max(abs(item.x), abs(item.y), item.z, item.width, item.height) <= Self.sizeLimitCM,
                  abs(item.yawDegrees) <= 90 else { return nil }
            return DisplayPose(id: display.id, width: item.width, height: item.height,
                               x: item.x, y: item.y, z: item.z, yawDegrees: item.yawDegrees)
        }
        return poses.count == stored.count ? poses : nil
    }

    /// 책상 위 배치로 볼 수 있는 위치와 크기의 상한(10m).
    private static let sizeLimitCM = 1_000.0

    private static func hasDistinctUUIDs(_ displays: [DisplayCalibration]) -> Bool {
        let uuids = displays.map(\.uuid)
        return uuids.allSatisfy { !$0.isEmpty } && Set(uuids).count == uuids.count
    }
}
