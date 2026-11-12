import AppKit
import Testing
import PrivacyCore
@testable import PrivacyAirPods

/// 자리 이탈 가리기의 사용자 흐름 e2e. 실제 AppModel과 WindowServer 가림 창의 마스크를 관측함.
/// AirPods 동작·걷기 활동과 시계만 대역이며, 실제 일어서기 감지 품질이나 실제 자리 비움은 증명하지 않음.
/// 시간 기대값은 일어선 시각에서 3초와 0.5초 전환으로 정하며 판정 알고리즘을 복사하지 않음.
@MainActor
@Suite(.serialized)
struct SeatAwayFlowTests {
    /// 보호 중 일어선 뒤 3초가 지나 자리 비움이 되고, 가림이 최대가 될 때까지 기다린 상태를 만듦.
    private func standUpAndWalkAway(_ h: ProtectionHarness) async throws -> NSPanel {
        let panel = try await h.protect()
        h.hold(right: 0, for: 1)
        h.rise(by: 0.45, over: 1.2)
        h.hold(right: 0, for: 5)
        #expect(h.model.away)
        #expect(try h.maskAlpha(panel) == [255, 255, 255])
        return panel
    }

    @Test func standingUpCoversTheWholeScreenOnlyAfterThreeSeconds() async throws {
        let h = try ProtectionHarness()
        defer { h.tearDown() }
        let panel = try await h.protect()
        h.hold(right: 0, for: 1)
        h.rise(by: 0.45, over: 1.2)
        // 동작이 끝난 지 2.9초면 일어섬 확정(약 0.3초) 뒤 3초가 아직 지나지 않음.
        h.hold(right: 0, for: 2.9)
        #expect(try h.maskAlpha(panel) == [0, 0, 0])
        #expect(!h.model.away)

        // 3.4초면 확정 뒤 3초를 넘김.
        h.hold(right: 0, for: 0.5)
        #expect(h.model.away)
        #expect(h.model.captureStatus.contains("자리 비움"))
        // 판정 직후에는 0.5초에 걸쳐 옮겨 가므로 가운데가 아직 최대가 아님.
        let middle = try h.maskAlpha(panel)[1]
        #expect(middle > 0 && middle < 255)

        h.hold(right: 0, for: 0.5)
        #expect(try h.maskAlpha(panel) == [255, 255, 255])
    }

    @Test func walkingCallbackArrivingRightAfterSittingDoesNotCoverAgain() async throws {
        let h = try ProtectionHarness()
        defer { h.tearDown() }
        let panel = try await h.protect()
        h.hold(right: 0, for: 1)
        h.activity.send(.moving)
        h.hold(right: 0, for: 0.6)
        #expect(h.model.away)

        h.rise(by: -0.45, over: 1.2)
        h.hold(right: 0, for: 0.5)
        #expect(!h.model.away)
        // 앉은 뒤 늦게 온 걷기 callback은 무시돼야 함. 앉은 사용자는 다시 내려앉을 수 없음.
        h.activity.send(.moving)
        h.hold(right: 0, for: 1)
        #expect(!h.model.away)
        #expect(try h.maskAlpha(panel) == [0, 0, 0])
    }

    @Test func sittingDownWithinThreeSecondsDoesNotCover() async throws {
        let h = try ProtectionHarness()
        defer { h.tearDown() }
        let panel = try await h.protect()
        h.hold(right: 0, for: 1)
        h.rise(by: 0.45, over: 1.2)
        h.hold(right: 0, for: 1)
        // 앉는 동작이 3초 안에 나와 자리 비움 기록을 지움. 이후 4초 동안 가리지 않아야 함.
        h.rise(by: -0.45, over: 1.2)
        h.hold(right: 0, for: 4)
        #expect(!h.model.away)
        #expect(try h.maskAlpha(panel) == [0, 0, 0])
    }

    @Test func sittingDownAfterAwayReturnsToHeadFollowingBlur() async throws {
        let h = try ProtectionHarness()
        defer { h.tearDown() }
        let panel = try await standUpAndWalkAway(h)

        h.hold(right: 0, for: 1)
        h.rise(by: -0.45, over: 1.2)
        h.hold(right: 0, for: 1)
        #expect(!h.model.away)
        #expect(h.model.captureStatus == "보호 중")
        #expect(try h.maskAlpha(panel) == [0, 0, 0])
    }

    @Test func walkingCoversAtOnceAndSittingBackReturns() async throws {
        let h = try ProtectionHarness()
        defer { h.tearDown() }
        let panel = try await h.protect()
        h.hold(right: 0, for: 1)
        // 일어서기 판정을 기다리지 않고 걷기만으로 자리 비움이 됨.
        h.activity.send(.moving)
        h.hold(right: 0, for: 0.6)
        #expect(h.model.away)
        #expect(try h.maskAlpha(panel) == [255, 255, 255])

        // 걸어서 나간 뒤 다시 앉으면 돌아옴.
        h.rise(by: -0.45, over: 1.2)
        h.hold(right: 0, for: 1)
        #expect(!h.model.away)
        #expect(try h.maskAlpha(panel) == [0, 0, 0])
    }

    @Test func switchOffNeverCoversOnStandingOrWalking() async throws {
        let h = try ProtectionHarness()
        defer { h.tearDown() }
        h.model.hideWhenAway = false
        let panel = try await h.protect()
        #expect(!h.activity.running)
        h.hold(right: 0, for: 1)
        h.rise(by: 0.45, over: 1.2)
        h.hold(right: 0, for: 4)
        h.activity.sendLate(.moving)
        h.hold(right: 0, for: 0.6)
        #expect(!h.model.away)
        #expect(try h.maskAlpha(panel) == [0, 0, 0])
    }

    @Test func switchingOffWhileAwayReturnsToHeadFollowingBlurAtOnce() async throws {
        let h = try ProtectionHarness()
        defer { h.tearDown() }
        let panel = try await standUpAndWalkAway(h)

        h.model.hideWhenAway = false
        #expect(!h.model.away)
        #expect(!h.activity.running)
        // 돌아올 때는 전환 없이 한 주기 안에 고개 따라가기 값이 됨.
        h.hold(right: 0, for: 0.05)
        #expect(try h.maskAlpha(panel) == [0, 0, 0])
    }

    @Test func resumeButtonReturnsWithoutSittingAndDoesNotRearmFromOldStanding() async throws {
        let h = try ProtectionHarness()
        defer { h.tearDown() }
        let panel = try await standUpAndWalkAway(h)

        h.model.resumeProtection()
        #expect(!h.model.away)
        #expect(h.model.captureStatus == "보호 중")
        h.hold(right: 0, for: 0.05)
        #expect(try h.maskAlpha(panel) == [0, 0, 0])

        // 재개 뒤에는 새 일어섬이 없으므로 이전 일어섬 시각으로 다시 가리지 않음.
        h.hold(right: 0, for: 4)
        #expect(!h.model.away)
        #expect(try h.maskAlpha(panel) == [0, 0, 0])
    }

    @Test func inputLossWhileAwayKeepsFullBlurWithoutAwayState() async throws {
        let h = try ProtectionHarness()
        defer { h.tearDown() }
        h.model.retainBlurOnInputLoss = true
        let panel = try await h.protect()
        h.hold(right: 0, for: 1)
        h.activity.send(.moving)
        h.hold(right: 0, for: 0.6)
        #expect(h.model.away)

        h.motion.fail("AirPods 입력 중단")
        h.clock.advance(0.2)
        #expect(h.model.suspended)
        #expect(!h.model.away)
        #expect(h.model.captureStatus.contains("전체 블러 유지"))
        #expect(try h.maskAlpha(panel) == [255, 255, 255])

        // 중단 뒤 들어오는 걷기와 일어섬은 문구도 가림도 바꾸지 않음.
        h.activity.sendLate(.moving)
        h.rise(by: 0.45, over: 1.2)
        h.hold(right: 0, for: 4)
        #expect(!h.model.away)
        #expect(h.model.captureStatus.contains("전체 블러 유지"))
        #expect(try h.maskAlpha(panel) == [255, 255, 255])

        // 중단된 가림에서 보호 재개를 눌러도 문구가 '보호 중'으로 바뀌지 않음.
        h.model.resumeProtection()
        #expect(h.model.captureStatus.contains("전체 블러 유지"))
        #expect(try h.maskAlpha(panel) == [255, 255, 255])
    }

    enum Leaving: String, CaseIterable, CustomTestStringConvertible {
        /// 일어선 뒤 3초가 지나기 전.
        case standing
        /// 걷기로 자리 비움이 된 뒤.
        case away
        var testDescription: String { rawValue }
    }

    enum Loss: String, CaseIterable, CustomTestStringConvertible {
        case sensorError, silence
        var testDescription: String { rawValue }
    }

    private func loseInput(_ h: ProtectionHarness, _ loss: Loss) {
        switch loss {
        case .sensorError:
            h.motion.fail("AirPods 연결 끊김")
            h.clock.advance()
        case .silence:
            for _ in 0..<16 { h.clock.advance() }
        }
    }

    /// 'AirPods를 벗으면'이 흐림 풀기여도 자리를 뜨는 중 입력이 끊기면 가림을 유지함.
    /// 다시 끼고 입력이 또 끊기거나 설정을 바꿔도 풀리지 않고, 보호를 꺼야만 풀림.
    @Test(arguments: Leaving.allCases, Loss.allCases)
    func inputLossWhileLeavingKeepsFullBlurEvenWhenSetToRelease(_ leaving: Leaving, loss: Loss) async throws {
        let h = try ProtectionHarness()
        defer { h.tearDown() }
        #expect(!h.model.retainBlurOnInputLoss)
        let panel = try await h.protect()
        h.hold(right: 0, for: 1)
        switch leaving {
        case .standing:
            h.rise(by: 0.45, over: 1.2)
            h.hold(right: 0, for: 1)
            #expect(!h.model.away)
            #expect(try h.maskAlpha(panel) == [0, 0, 0])
        case .away:
            h.activity.send(.moving)
            h.hold(right: 0, for: 0.6)
            #expect(h.model.away)
        }

        loseInput(h, loss)
        #expect(h.model.protected && h.model.suspended)
        #expect(panel.isVisible)
        #expect(try h.maskAlpha(panel) == [255, 255, 255])
        #expect(h.model.captureStatus.contains("자리를 비운 중이라 전체 블러 유지"))

        // 다시 끼고 앉아 입력이 돌아온 뒤 또 끊겨도 설정대로 풀리지 않음.
        h.model.startMotion()
        h.hold(right: 0, for: 1)
        h.rise(by: -0.45, over: 1.2)
        h.hold(right: 0, for: 1)
        #expect(try h.maskAlpha(panel) == [255, 255, 255])
        loseInput(h, .silence)
        #expect(h.model.protected)
        #expect(try h.maskAlpha(panel) == [255, 255, 255])

        // 유지 이유가 설정이 아니므로 설정을 켰다 꺼도 풀리지 않음.
        h.model.retainBlurOnInputLoss = true
        h.model.retainBlurOnInputLoss = false
        #expect(h.model.protected)
        #expect(panel.isVisible)

        h.model.stopProtection()
        #expect(!panel.isVisible)
        #expect(h.model.protectionWindows.isEmpty)
    }

    /// 자리를 뜨는 중의 유지는 그 보호에만 해당함. 보호를 끄고 다시 켠 뒤 앉아서 입력이 끊기면 설정대로 풀림.
    @Test func leaveRetainEndsWithProtectionAndNextSeatedLossFollowsReleaseSetting() async throws {
        let h = try ProtectionHarness()
        defer { h.tearDown() }
        _ = try await h.protect()
        h.hold(right: 0, for: 1)
        h.activity.send(.moving)
        h.hold(right: 0, for: 0.6)
        loseInput(h, .sensorError)
        #expect(h.model.protected && h.model.suspended)
        h.model.stopProtection()

        let panel = try await h.protect()
        h.hold(right: 0, for: 1)
        loseInput(h, .sensorError)
        #expect(!h.model.protected)
        #expect(!panel.isVisible)
    }

    /// 일어섰다가 3초 안에 다시 앉은 뒤의 입력 중단은 앉은 상태이므로 흐림 풀기 설정을 따름.
    @Test func inputLossAfterSittingBackFollowsReleaseSetting() async throws {
        let h = try ProtectionHarness()
        defer { h.tearDown() }
        let panel = try await h.protect()
        h.hold(right: 0, for: 1)
        h.rise(by: 0.45, over: 1.2)
        h.hold(right: 0, for: 1)
        h.rise(by: -0.45, over: 1.2)
        h.hold(right: 0, for: 1)

        loseInput(h, .sensorError)
        #expect(!h.model.protected)
        #expect(!panel.isVisible)
    }

    /// 스위치를 끄면 자리 이탈을 보지 않으므로 일어선 뒤의 입력 중단도 흐림 풀기 설정을 따름.
    @Test func inputLossWhileStandingWithSwitchOffFollowsReleaseSetting() async throws {
        let h = try ProtectionHarness()
        defer { h.tearDown() }
        h.model.hideWhenAway = false
        let panel = try await h.protect()
        h.hold(right: 0, for: 1)
        h.rise(by: 0.45, over: 1.2)
        h.hold(right: 0, for: 1)

        loseInput(h, .sensorError)
        #expect(!h.model.protected)
        #expect(!panel.isVisible)
    }

    @Test func notProtectedNeverEntersAway() throws {
        let h = try ProtectionHarness()
        defer { h.tearDown() }
        h.model.startMotion()
        h.look(right: 0)
        #expect(h.model.calibrateDesk())
        #expect(h.model.applyLayout(h.frontLayout))
        h.rise(by: 0.45, over: 1.2)
        h.hold(right: 0, for: 4)
        h.activity.sendLate(.moving)
        h.hold(right: 0, for: 0.6)
        #expect(!h.model.protected)
        #expect(!h.model.away)
        #expect(h.model.protectionWindows.isEmpty)
    }

    @Test func bendingAndAdjustingWhileSeatedDoesNotCover() async throws {
        let h = try ProtectionHarness()
        defer { h.tearDown() }
        let panel = try await h.protect()
        h.hold(right: 0, for: 1)
        // 앉은 채 0.1m 들어 올렸다 내리고, 0.3m 숙였다 펴는 자세 고침은 자리 이탈이 아님.
        h.rise(by: 0.1, over: 0.5)
        h.hold(right: 0, for: 0.5)
        h.rise(by: -0.1, over: 0.5)
        h.hold(right: 0, for: 0.5)
        h.rise(by: -0.3, over: 1.2)
        h.hold(right: 0, for: 1)
        h.rise(by: 0.3, over: 1.2)
        h.hold(right: 0, for: 4)
        #expect(!h.model.away)
        #expect(try h.maskAlpha(panel) == [0, 0, 0])
    }

    @Test func coverFadesInOverHalfASecondAfterTheTimerExpires() async throws {
        let h = try ProtectionHarness()
        defer { h.tearDown() }
        let panel = try await h.protect()
        h.hold(right: 0, for: 1)
        h.rise(by: 0.45, over: 1.2)
        var waited = 0.0
        while !h.model.away && waited < 8 {
            h.hold(right: 0, for: 0.05)
            waited += 0.05
        }
        #expect(h.model.away)
        // 판정 0.25초 뒤에는 전환 중이고, 0.5초 뒤에는 최대여야 함.
        h.hold(right: 0, for: 0.25)
        let middle = try h.maskAlpha(panel)[1]
        #expect(middle > 0 && middle < 255)
        h.hold(right: 0, for: 0.25)
        #expect(try h.maskAlpha(panel) == [255, 255, 255])
    }
}
