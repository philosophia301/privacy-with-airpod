import Foundation

/// 설정 화면의 준비 항목 세 가지. 나열 순서가 화면 순서임.
enum ReadinessKind: CaseIterable {
    case airPods, desk, screens
}

/// done은 끝남, todo는 사용자가 할 일이 있음, wait는 다른 항목이 먼저 끝나야 함.
enum ReadinessState: Equatable {
    case done, todo, wait
}

struct ReadinessItem: Equatable, Identifiable {
    let kind: ReadinessKind
    let state: ReadinessState
    /// 항목 이름. 화면 항목은 화면 수를 포함함.
    let label: String
    /// 현재 상태를 짧게 말하는 문구.
    let status: String
    /// 다음 행동의 이유. 끝난 항목은 nil.
    let why: String?
    /// 행동 버튼 문구. 할 일이 없으면 nil.
    let actionTitle: String?
    let actionEnabled: Bool

    var id: ReadinessKind { kind }
}

/// 상태 카드 캐릭터의 기본 표정. 정면을 방금 맞춘 뒤 잠깐 보이는 cheer는 화면 단위가 덧씌움.
enum HeroMood: Equatable {
    case lost, think, relax, `guard`
}

/// 준비 규칙이 읽는 실제 상태 묶음. 계산은 이 값만 보고 하며 상태를 저장하지 않음.
struct ReadinessSnapshot: Equatable {
    /// AirPods 입력이 신선함.
    var fresh: Bool
    /// 동작 접근이 시스템에서 거절됨.
    var motionAccessDenied: Bool
    /// 책상 정면 보정이 있음.
    var deskCalibrated: Bool
    /// 화면 배치가 적용됨.
    var layoutApplied: Bool
    var screenCount: Int
    /// 보호 중이거나 시작 중임. 정면 맞추기와 배치 변경을 막음.
    var locked: Bool
}

/// 준비 항목과 캐릭터 기분을 실제 상태에서 계산하는 순수 규칙.
enum Readiness {
    static func items(_ snapshot: ReadinessSnapshot) -> [ReadinessItem] {
        [airPods(snapshot), desk(snapshot), screens(snapshot)]
    }

    static func remaining(_ items: [ReadinessItem]) -> Int {
        items.filter { $0.state != .done }.count
    }

    /// 보호 상태가 최우선이고, 입력이 없으면 lost, 정면이 없으면 think임.
    static func mood(_ snapshot: ReadinessSnapshot) -> HeroMood {
        if snapshot.locked { return .guard }
        if !snapshot.fresh { return .lost }
        if !snapshot.deskCalibrated { return .think }
        return .relax
    }

    private static func airPods(_ snapshot: ReadinessSnapshot) -> ReadinessItem {
        if snapshot.fresh {
            return ReadinessItem(kind: .airPods, state: .done, label: "AirPods", status: "연결됨",
                                 why: nil, actionTitle: nil, actionEnabled: false)
        }
        // 거절은 재시도로 풀리지 않으므로 시스템 설정 안내를 먼저 보여 줌.
        let why = snapshot.motionAccessDenied ? "시스템 설정에서 동작 접근을 허용해 주세요" : "AirPods를 껴 주세요"
        return ReadinessItem(kind: .airPods, state: .todo, label: "AirPods", status: "연결 안 됨",
                             why: why, actionTitle: "다시 확인", actionEnabled: true)
    }

    private static func desk(_ snapshot: ReadinessSnapshot) -> ReadinessItem {
        let label = "책상 정면"
        if snapshot.deskCalibrated {
            return ReadinessItem(kind: .desk, state: .done, label: label, status: "맞춤",
                                 why: nil, actionTitle: "다시 맞추기", actionEnabled: !snapshot.locked)
        }
        if snapshot.fresh {
            return ReadinessItem(kind: .desk, state: .todo, label: label, status: "아직 안 맞춤",
                                 why: "평소 자세로 화면을 보고 눌러 주세요", actionTitle: "지금 맞추기",
                                 actionEnabled: !snapshot.locked)
        }
        return ReadinessItem(kind: .desk, state: .wait, label: label, status: "아직 안 맞춤",
                             why: "AirPods가 연결되면 맞출 수 있어요", actionTitle: "지금 맞추기",
                             actionEnabled: false)
    }

    private static func screens(_ snapshot: ReadinessSnapshot) -> ReadinessItem {
        let label = "화면 \(snapshot.screenCount)대"
        if snapshot.layoutApplied {
            return ReadinessItem(kind: .screens, state: .done, label: label, status: "배치됨",
                                 why: nil, actionTitle: "배치 수정", actionEnabled: !snapshot.locked)
        }
        return ReadinessItem(kind: .screens, state: .todo, label: label, status: "아직 안 함",
                             why: "화면 위치를 알려 주세요", actionTitle: "배치하기",
                             actionEnabled: !snapshot.locked)
    }
}
