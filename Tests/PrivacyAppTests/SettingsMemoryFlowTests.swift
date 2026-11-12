import AppKit
import Testing
import PrivacyCore
@testable import PrivacyAirPods

/// 설정과 모니터 조합별 배치 기억의 사용자 흐름 e2e. 실제 UserDefaults suite와 실제 AppModel을 씀.
/// AirPods, 시계, 알림, 화면 목록만 대역이며 실제 재부팅·SMAppService·UserDefaults.standard는 건드리지 않음.
/// 재부팅 뒤 화면 ID 변경은 같은 UUID에 다른 ID를 주는 방식으로 모사함. 실제 재부팅 증명이 아님.
@MainActor
@Suite(.serialized)
struct SettingsMemoryFlowTests {
    private let shortText = "화면 구성이 바뀜 · 정면을 다시 맞춰 주세요"
    private let longText = "화면 구성이 바뀜 · 정면과 배치를 다시 맞춰 주세요"

    /// 저장 값이 깨졌을 때 쓸 손상 형식. 설정 저장 키에만 쓰는 값들임.
    enum BrokenSettings: CaseIterable {
        case notJSON, wrongShape, wrongType, koreanGuideName

        func write(to defaults: UserDefaults) {
            switch self {
            case .notJSON:
                defaults.set(Data("{not json".utf8), forKey: SettingsMemory.settingsKey)
            case .wrongShape:
                defaults.set(Data("[1,2,3]".utf8), forKey: SettingsMemory.settingsKey)
            case .wrongType:
                defaults.set(42, forKey: SettingsMemory.settingsKey)
            case .koreanGuideName:
                // 화면 문구인 '남성'은 저장 키가 아니므로 읽지 않고 기본값을 써야 함.
                defaults.set(Data(#"{"startAngle":20,"maximumBlur":50,"connectionWidth":10,"responseTime":0.3,"retainBlurOnInputLoss":true,"armLengthCM":70,"armGuide":"남성"}"#.utf8),
                             forKey: SettingsMemory.settingsKey)
            }
        }
    }

    /// 배치 저장 키에만 쓰는 손상 형식. 조합 키는 맞게 두어 손상 때문에 복원이 막히는지 확인함.
    enum BrokenLayouts: CaseIterable {
        case notJSON, wrongShape, wrongType, missingField

        func write(to defaults: UserDefaults, key: String) {
            switch self {
            case .notJSON:
                defaults.set(Data("[oops".utf8), forKey: SettingsMemory.layoutsKey)
            case .wrongShape:
                defaults.set(Data("[1,2,3]".utf8), forKey: SettingsMemory.layoutsKey)
            case .wrongType:
                defaults.set("text", forKey: SettingsMemory.layoutsKey)
            case .missingField:
                defaults.set(Data("{\"\(key)\":[{\"uuid\":\"MONITOR-A\"}]}".utf8), forKey: SettingsMemory.layoutsKey)
            }
        }
    }

    enum UnusableMonitors: CaseIterable {
        case missingUUID, duplicatedUUID
    }

    @Test func freshMacStartsWithTheDefaultValues() throws {
        let h = try ProtectionHarness()
        defer { h.tearDown() }
        #expect(h.model.startAngle == 35)
        #expect(h.model.maximumBlur == 31.25)
        #expect(h.model.connectionWidth == 25)
        #expect(h.model.responseTime == 0.18)
        #expect(!h.model.retainBlurOnInputLoss)
        #expect(h.model.armLengthCM == 53.012)
        #expect(h.model.armGuide == .female)
        #expect(h.model.appliedPoses.isEmpty)
    }

    @Test func settingsAndArmLengthSurviveRelaunch() throws {
        let h = try ProtectionHarness()
        defer { h.tearDown() }
        h.model.startAngle = 20
        h.model.maximumBlur = 50
        h.model.connectionWidth = 10
        h.model.responseTime = 0.3
        h.model.retainBlurOnInputLoss = true
        h.model.armLengthCM = 70
        h.model.armGuide = .male

        let again = h.relaunch()
        #expect(again.startAngle == 20)
        #expect(again.maximumBlur == 50)
        #expect(again.connectionWidth == 10)
        #expect(again.responseTime == 0.3)
        #expect(again.retainBlurOnInputLoss)
        #expect(again.armLengthCM == 70)
        #expect(again.armGuide == .male)
    }

    @Test func protectedModelRelaunchesWithProtectionOffAndNoDeskReference() async throws {
        let h = try ProtectionHarness()
        defer { h.tearDown() }
        _ = try await h.protect()
        #expect(h.model.protected)

        let again = h.relaunch()
        #expect(!again.protected)
        #expect(again.deskReference == nil)
        #expect(!again.canProtect)
        #expect(again.protectionWindows.isEmpty)
    }

    @Test func calibrationAndDirectPreviewValuesAreNotRemembered() throws {
        let h = try ProtectionHarness()
        defer { h.tearDown() }
        h.model.demoAngle = 30
        h.model.startMotion()
        h.look(right: 20)
        #expect(h.model.calibrateDesk())
        #expect(h.model.deskReference != nil)

        let again = h.relaunch()
        #expect(again.deskReference == nil)
        #expect(again.demoAngle == 0)
        #expect(again.demo)
    }

    @Test func appliedLayoutRelaunchesToTheSamePosesAndCoverAngles() throws {
        let h = try ProtectionHarness()
        defer { h.tearDown() }
        h.model.startAngle = 20
        // 40cm 화면을 오른쪽 60cm에 둠. 시작 각도를 바꿔도 같은 배치가 같은 가림 값을 내야 함.
        let side = [DisplayPose(id: h.display.id, width: 40, height: 25, x: 60, y: 0, z: 60, yawDegrees: 0)]
        #expect(h.model.applyLayout(side))
        let angles = [-30.0, 0, 45]
        let before = angles.map { h.model.settingsByDisplay(previewAngle: $0) }

        let again = h.relaunch()
        #expect(again.appliedPoses == side)
        #expect(angles.map { again.settingsByDisplay(previewAngle: $0) } == before)
        #expect(again.readinessItems[2].state == .done)
        #expect(again.readinessItems[2].status == "배치됨")
    }

    @Test func layoutFollowsTheMonitorUUIDWhenDisplayIDChanges() throws {
        let h = try ProtectionHarness()
        defer { h.tearDown() }
        h.relaunch(with: [ProtectionHarness.screen(id: h.display.id, uuid: "MONITOR-A")])
        let side = [DisplayPose(id: h.display.id, width: 40, height: 25, x: 60, y: 0, z: 60, yawDegrees: 0)]
        #expect(h.model.applyLayout(side))

        let newID = h.display.id &+ 1
        let again = h.relaunch(with: [ProtectionHarness.screen(id: newID, uuid: "MONITOR-A")])
        var moved = side
        moved[0].id = newID
        #expect(again.appliedPoses == moved)
        #expect(Set(again.settingsByDisplay(previewAngle: 0).keys) == [newID])
        #expect(again.readinessItems[2].state == .done)
    }

    @Test func eachMonitorSetKeepsItsOwnLayoutAcrossConnectAndDisconnect() throws {
        let h = try ProtectionHarness()
        defer { h.tearDown() }
        let a = ProtectionHarness.screen(id: h.display.id, uuid: "MONITOR-A")
        let b = ProtectionHarness.screen(id: h.display.id &+ 1, uuid: "MONITOR-B",
                                         frame: CGRect(x: 1920, y: 0, width: 1920, height: 1080))
        let onlyA = [DisplayPose(id: a.id, width: 40, height: 25, x: 0, y: 0, z: 60, yawDegrees: 0)]
        let both = [
            DisplayPose(id: a.id, width: 40, height: 25, x: -22, y: 0, z: 60, yawDegrees: 0),
            DisplayPose(id: b.id, width: 40, height: 25, x: 22, y: 0, z: 60, yawDegrees: 0)
        ]

        h.relaunch(with: [a])
        #expect(h.model.applyLayout(onlyA))

        // 처음 보는 [A, B]는 배치를 다시 받음. 이때 문구는 배치까지 다시 맞추라고 말함.
        h.setScreens([a, b])
        #expect(h.model.appliedPoses.isEmpty)
        #expect(h.model.captureStatus == longText)
        #expect(h.model.applyLayout(both))

        // [A]로 돌아오면 [A]의 배치가 되살아나고 정면만 다시 맞추면 됨.
        h.setScreens([a])
        #expect(h.model.appliedPoses == onlyA)
        #expect(h.model.captureStatus == shortText)

        // 다시 [A, B]가 되면 [A, B]의 배치가 되살아남.
        h.setScreens([a, b])
        #expect(h.model.appliedPoses == both)
        #expect(h.model.captureStatus == shortText)

        // [B] 단독은 저장된 적 없는 조합이므로 배치를 다시 받음.
        h.setScreens([b])
        #expect(h.model.appliedPoses.isEmpty)
        #expect(h.model.captureStatus == longText)

        // 재실행해도 조합별 배치가 각각 그대로 남음.
        let again = h.relaunch(with: [a, b])
        #expect(again.appliedPoses == both)
    }

    @Test func monitorRotatedSinceSaveDoesNotGetItsLayoutBack() throws {
        let h = try ProtectionHarness()
        defer { h.tearDown() }
        let landscape = ProtectionHarness.screen(id: h.display.id, uuid: "MONITOR-A")
        h.relaunch(with: [landscape])
        #expect(h.model.applyLayout(h.frontLayout))

        let rotated = ProtectionHarness.screen(id: h.display.id, uuid: "MONITOR-A",
                                               frame: CGRect(x: 0, y: 0, width: 1080, height: 1920))
        let turned = h.relaunch(with: [rotated])
        #expect(turned.appliedPoses.isEmpty)
        #expect(turned.readinessItems[2].state == .todo)

        // 원래 방향으로 돌려놓으면 같은 배치가 다시 살아남.
        let back = h.relaunch(with: [landscape])
        #expect(back.appliedPoses == h.frontLayout)
    }

    @Test(arguments: BrokenSettings.allCases)
    func brokenSavedSettingsFallBackToDefaultsAndKeepTheLayout(_ broken: BrokenSettings) throws {
        let h = try ProtectionHarness()
        defer { h.tearDown() }
        #expect(h.model.applyLayout(h.frontLayout))
        h.model.startAngle = 20
        broken.write(to: h.defaults)

        let again = h.relaunch()
        #expect(again.startAngle == 35)
        #expect(again.maximumBlur == 31.25)
        #expect(again.connectionWidth == 25)
        #expect(again.responseTime == 0.18)
        #expect(!again.retainBlurOnInputLoss)
        #expect(again.armLengthCM == 53.012)
        #expect(again.armGuide == .female)
        // 설정 값이 깨져도 조합 배치는 별개 항목이므로 그대로 되살아남.
        #expect(again.appliedPoses == h.frontLayout)
    }

    @Test(arguments: BrokenLayouts.allCases)
    func brokenSavedLayoutsAreIgnoredWithoutTouchingSettings(_ broken: BrokenLayouts) throws {
        let h = try ProtectionHarness()
        defer { h.tearDown() }
        h.model.startAngle = 20
        #expect(h.model.applyLayout(h.frontLayout))
        let key = try #require(SettingsMemory.combinationKey(for: h.screens.displays))
        broken.write(to: h.defaults, key: key)

        let again = h.relaunch()
        #expect(again.appliedPoses.isEmpty)
        #expect(again.readinessItems[2].state == .todo)
        #expect(again.startAngle == 20)
    }

    @Test func storedSettingsAboveTheSliderRangesAreClampedToTheUpperEdge() throws {
        let h = try ProtectionHarness()
        defer { h.tearDown() }
        h.defaults.set(Data(#"{"startAngle":90,"maximumBlur":200,"connectionWidth":80,"responseTime":2,"retainBlurOnInputLoss":true,"armLengthCM":100,"armGuide":"male"}"#.utf8),
                       forKey: SettingsMemory.settingsKey)

        let again = h.relaunch()
        #expect(again.startAngle == 45)
        #expect(again.maximumBlur == 80)
        #expect(again.connectionWidth == 50)
        #expect(again.responseTime == 0.5)
        #expect(again.armLengthCM == 85)
        #expect(again.armGuide == .male)
        #expect(again.retainBlurOnInputLoss)
    }

    @Test func storedSettingsBelowTheSliderRangesAreClampedToTheLowerEdge() throws {
        let h = try ProtectionHarness()
        defer { h.tearDown() }
        h.defaults.set(Data(#"{"startAngle":-5,"maximumBlur":5,"connectionWidth":-1,"responseTime":0.001,"retainBlurOnInputLoss":false,"armLengthCM":10,"armGuide":"female"}"#.utf8),
                       forKey: SettingsMemory.settingsKey)

        let again = h.relaunch()
        #expect(again.startAngle == 0)
        #expect(again.maximumBlur == 15)
        #expect(again.connectionWidth == 0)
        #expect(again.responseTime == 0.03)
        #expect(again.armLengthCM == 40)
        #expect(!again.retainBlurOnInputLoss)
    }

    @Test(arguments: UnusableMonitors.allCases)
    func monitorSetWithoutDistinctUUIDsIsNeitherSavedNorRestored(_ kind: UnusableMonitors) throws {
        let h = try ProtectionHarness()
        defer { h.tearDown() }
        let first = ProtectionHarness.screen(id: h.display.id, uuid: "MONITOR-A")
        let secondUUID = kind == .missingUUID ? "" : "MONITOR-A"
        let second = ProtectionHarness.screen(id: h.display.id &+ 1, uuid: secondUUID,
                                              frame: CGRect(x: 1920, y: 0, width: 1920, height: 1080))
        let screens = [first, second]
        let poses = [
            DisplayPose(id: first.id, width: 40, height: 25, x: -22, y: 0, z: 60, yawDegrees: 0),
            DisplayPose(id: second.id, width: 40, height: 25, x: 22, y: 0, z: 60, yawDegrees: 0)
        ]

        h.relaunch(with: screens)
        #expect(h.model.applyLayout(poses))
        #expect(h.defaults.data(forKey: SettingsMemory.layoutsKey) == nil)

        let again = h.relaunch(with: screens)
        #expect(again.appliedPoses.isEmpty)
        #expect(again.readinessItems[2].state == .todo)
    }

    @Test func armLengthAndGuideAreRememberedOnlyWhenTheLayoutIsApplied() throws {
        let h = try ProtectionHarness()
        defer { h.tearDown() }
        // 배치가 적용되지 않으면(화면 대응 실패) 팔 길이와 모형도 바뀌지 않음.
        let stale = [DisplayPose(id: h.display.id &+ 99, width: 40, height: 25, x: 0, y: 0, z: 60, yawDegrees: 0)]
        #expect(!h.model.applyLayout(stale, armLengthCM: 70, armGuide: .male))
        let untouched = h.relaunch()
        #expect(untouched.armLengthCM == 53.012)
        #expect(untouched.armGuide == .female)

        #expect(h.model.applyLayout(h.frontLayout, armLengthCM: 70, armGuide: .male))
        let again = h.relaunch()
        #expect(again.armLengthCM == 70)
        #expect(again.armGuide == .male)
    }

    @Test func oneBrokenLayoutEntryDoesNotEraseTheOtherCombinations() throws {
        let h = try ProtectionHarness()
        defer { h.tearDown() }
        #expect(h.model.applyLayout(h.frontLayout))
        let key = try #require(SettingsMemory.combinationKey(for: h.screens.displays))
        let good = try #require(h.memory.loadLayout(for: key))
        let goodJSON = String(decoding: try JSONEncoder().encode(good), as: UTF8.self)
        h.defaults.set(Data("{\"\(key)\":\(goodJSON),\"OTHER\":[{\"uuid\":\"x\"}]}".utf8),
                       forKey: SettingsMemory.layoutsKey)

        h.memory.saveLayout(good, for: "THIRD")
        #expect(h.memory.loadLayout(for: key) == good)
        #expect(h.memory.loadLayout(for: "THIRD") == good)
    }

    // JSON은 무한대와 NaN을 쓰지 못하므로 저장 파일에 들어올 수 있는 유한한 손상 값만 씀.
    @Test(arguments: [("yaw", 120.0), ("z", -5.0), ("x", 5_000.0), ("width", 0.0)])
    func storedPosesTheAppCannotApplyAreNotRestored(_ field: String, _ value: Double) throws {
        let h = try ProtectionHarness()
        defer { h.tearDown() }
        #expect(h.model.applyLayout(h.frontLayout))
        let key = try #require(SettingsMemory.combinationKey(for: h.screens.displays))
        var stored = try #require(h.memory.loadLayout(for: key))
        switch field {
        case "yaw": stored[0].yawDegrees = value
        case "z": stored[0].z = value
        case "x": stored[0].x = value
        default: stored[0].width = value
        }
        h.memory.saveLayout(stored, for: key)

        let again = h.relaunch()
        #expect(again.appliedPoses.isEmpty)
    }

    /// 손대지 않고 적용한 기본 배치는 편집기 범위(높이 ±60cm)를 넘을 수 있음. 그래도 다시 열면 되살아나야 함.
    @Test func untouchedDefaultLayoutOfThreeStackedMonitorsSurvivesRelaunch() throws {
        let h = try ProtectionHarness()
        defer { h.tearDown() }
        // 27인치(60x34cm) 세 대를 위아래로 쌓으면 맨 위 화면 중심이 눈높이보다 68cm 넘게 위에 놓임.
        let stack = (0..<3).map { index in
            DisplayCalibration(id: h.display.id &+ CGDirectDisplayID(index), name: "쌓은 화면 \(index)",
                               frame: CGRect(x: 0, y: Double(index) * 1080, width: 1920, height: 1080),
                               widthCM: 60, heightCM: 34, uuid: "STACK-\(index)")
        }
        h.relaunch(with: stack)
        let draft = h.model.layoutDraft
        #expect(draft.map { abs($0.y) }.max() ?? 0 > 60)
        #expect(h.model.applyLayout(draft))

        let again = h.relaunch(with: stack)
        #expect(again.appliedPoses == draft)
    }
}
