import AppKit
import Testing
import PrivacyCore
@testable import PrivacyAirPods

/// 준비 항목 사용자 흐름 e2e. 실제 AppModel의 상태가 항목과 캐릭터 기분을 어떻게 바꾸는지 관측함.
/// AirPods, 시계, 알림만 대역이며 실제 머리 움직임이나 화면 문구의 배치는 증명하지 않음.
@MainActor
@Suite(.serialized)
struct ReadinessFlowTests {
    @Test func startingWithoutInputShowsAirPodsTodoDeskWaitAndScreensTodo() throws {
        let h = try ProtectionHarness()
        defer { h.tearDown() }
        let items = h.model.readinessItems
        #expect(items.map(\.state) == [.todo, .wait, .todo])
        #expect(items[0].status == "연결 안 됨" && items[0].why == "AirPods를 껴 주세요")
        #expect(items[0].actionTitle == "다시 확인" && items[0].actionEnabled)
        #expect(items[1].why == "AirPods가 연결되면 맞출 수 있어요" && !items[1].actionEnabled)
        #expect(items[2].label == "화면 1대" && items[2].why == "화면 위치를 알려 주세요")
        #expect(h.model.readinessRemaining == 3)
        #expect(h.model.heroMood == .lost)
    }

    @Test func freshInputCalibrationAndLayoutFinishTheChecklistInOrder() throws {
        let h = try ProtectionHarness()
        defer { h.tearDown() }
        h.model.startMotion()
        h.look(right: 0)
        var items = h.model.readinessItems
        #expect(items.map(\.state) == [.done, .todo, .todo])
        #expect(items[1].why == "평소 자세로 화면을 보고 눌러 주세요" && items[1].actionEnabled)
        #expect(h.model.heroMood == .think)

        h.model.calibrateDesk()
        items = h.model.readinessItems
        #expect(items[1].state == .done && items[1].status == "맞춤" && items[1].actionTitle == "다시 맞추기")
        #expect(h.model.readinessRemaining == 1)
        #expect(h.model.heroMood == .relax)

        #expect(h.model.applyLayout(h.frontLayout))
        items = h.model.readinessItems
        #expect(items[2].state == .done && items[2].status == "배치됨" && items[2].actionTitle == "배치 수정")
        #expect(h.model.readinessRemaining == 0)
    }

    @Test func protectionLocksDeskAndLayoutActionsUntilStopped() async throws {
        let h = try ProtectionHarness()
        defer { h.tearDown() }
        try await h.protect()
        var items = h.model.readinessItems
        #expect(items.map(\.state) == [.done, .done, .done])
        #expect(!items[1].actionEnabled)
        #expect(!items[2].actionEnabled)
        #expect(h.model.readinessRemaining == 0)
        #expect(h.model.heroMood == .guard)

        h.model.stopProtection()
        items = h.model.readinessItems
        #expect(items[1].actionEnabled && items[2].actionEnabled)
        #expect(h.model.heroMood == .relax)
    }

    @Test func silentInputReturnsAirPodsToTodoAndDeskToWaitWhileKeepingLayout() async throws {
        let h = try ProtectionHarness()
        defer { h.tearDown() }
        try await h.protect()
        // 기본 정책은 입력이 끊기면 보호를 풀고, 배치는 실험 실행 중 그대로 남김.
        for _ in 0..<16 { h.clock.advance() }
        #expect(!h.model.protected)
        let items = h.model.readinessItems
        #expect(items.map(\.state) == [.todo, .wait, .done])
        #expect(items[0].why == "AirPods를 껴 주세요")
        #expect(items[1].why == "AirPods가 연결되면 맞출 수 있어요")
        #expect(h.model.heroMood == .lost)
    }

    @Test func losingDeskReferenceReturnsHidePreviewFromAirPodsToManual() throws {
        let h = try ProtectionHarness()
        defer { h.tearDown() }
        h.model.startMotion()
        h.look(right: 0)
        #expect(h.model.calibrateDesk())
        #expect(!h.model.demo)

        // AirPods를 빼 sample이 끊기면 정면 기준이 사라짐. AirPods 보기는 고를 수 없으므로 직접 돌려보기로 돌아옴.
        for _ in 0..<16 { h.clock.advance() }
        #expect(h.model.deskReference == nil)
        #expect(h.model.demo)

        // 다시 맞춘 뒤 화면 구성이 바뀌어도 같은 규칙을 따르고, 메뉴 상태 문구는 다시 맞출 것을 알림.
        h.hold(right: 0, for: 0.2)
        #expect(h.model.calibrateDesk())
        #expect(!h.model.demo)
        h.notifications.post(name: NSApplication.didChangeScreenParametersNotification, object: nil)
        #expect(h.model.deskReference == nil)
        #expect(h.model.demo)
        #expect(h.model.captureStatus == "화면 구성이 바뀜 · 정면과 배치를 다시 맞춰 주세요")
    }

    @Test func deniedMotionAccessAsksForSystemSettingsInsteadOfWearing() throws {
        let h = try ProtectionHarness()
        defer { h.tearDown() }
        h.model.startMotion()
        // 동작 접근 거절은 MotionService가 내는 문구 그대로 AppModel에 전달됨.
        h.motion.fail(MotionService.accessDeniedMessage)
        #expect(h.model.motionAccessDenied)
        #expect(h.model.readinessItems[0].why == "시스템 설정에서 동작 접근을 허용해 주세요")

        // 다른 입력 오류가 오면 거절 안내를 지우고 착용 안내로 돌아감.
        h.model.startMotion()
        h.motion.fail("AirPods 연결 끊김")
        #expect(!h.model.motionAccessDenied)
        #expect(h.model.readinessItems[0].why == "AirPods를 껴 주세요")
    }
}
