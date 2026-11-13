import AppKit
import Testing
import PrivacyCore
@testable import PrivacyAirPods

/// 자리 이탈 가리기의 사용자 흐름 e2e. 실제 AppModel과 WindowServer 가림 창의 마스크를 관측함.
/// AirPods 동작·걷기 활동과 시계만 대역이며, 실제 일어서기 감지 품질이나 실제 자리 비움은 증명하지 않음.
/// 시간 기대값은 일어섬 동작 구간과 승인된 3초·0.5초 전환에서 정하며 판정 알고리즘의 내부 시각을 복사하지 않음.
/// 보호 시작 직후 1.5초는 감지가 입력을 무시하므로 자세를 바꾸는 모든 흐름은 보호 뒤 2초 쉰 뒤 시작함.
@MainActor
@Suite(.serialized)
struct SeatAwayFlowTests {
    /// 흐름 중 자리 비움이 한 번이라도 됐는지 갱신 주기마다 기록함. 자리 비움이 잠깐 켜졌다 꺼져도 잡으려고 씀.
    @MainActor
    private final class AwayWatch {
        private let harness: ProtectionHarness
        private(set) var everAway = false

        init(_ harness: ProtectionHarness) {
            self.harness = harness
        }

        func note() {
            everAway = everAway || harness.model.away
        }

        /// 정면을 보는 채 seconds만큼 갱신하며 매 주기 기록함.
        func hold(for seconds: TimeInterval) {
            for _ in 0..<Int((seconds / 0.05).rounded()) {
                harness.hold(right: 0, for: 0.05)
                note()
            }
        }
    }

    /// 보호 중 2초 쉬고 일어선 뒤 3초가 지나 자리 비움이 되고, 가림이 최대가 될 때까지 기다린 상태를 만듦.
    private func standUpAndWalkAway(_ h: ProtectionHarness) async throws -> NSPanel {
        let panel = try await h.protect()
        h.hold(right: 0, for: 2)
        h.rise(by: 0.45, over: 1.2)
        h.hold(right: 0, for: 5)
        #expect(h.model.away)
        #expect(try h.maskAlpha(panel) == [255, 255, 255])
        return panel
    }

    /// 일어섬 동작이 시작한 뒤 3초가 지나기 전에는 자리 비움이 아니고, 3초 뒤 동작 구간 안에서 자리 비움이 됨.
    /// 일어섬은 동작 초반에 보고되므로 자리 비움 시각은 동작 시작 뒤 3초보다 늦고 동작 끝 뒤 3.1초보다 이름.
    @Test func standingUpCoversTheWholeScreenOnlyAfterThreeSeconds() async throws {
        let h = try ProtectionHarness()
        defer { h.tearDown() }
        let panel = try await h.protect()
        h.hold(right: 0, for: 2)
        let riseStart = h.clock.now
        h.rise(by: 0.45, over: 1.2)
        let riseEnd = riseStart + 1.2
        // rise가 끝난 시각은 동작 시작 1.25초 뒤이므로 여기서 1.65초 더 쉬면 동작 시작 2.9초 시점임.
        h.hold(right: 0, for: 1.65)
        #expect(!h.model.away)
        #expect(try h.maskAlpha(panel) == [0, 0, 0])

        var waited = 0.0
        while !h.model.away && waited < 8 {
            h.hold(right: 0, for: 0.05)
            waited += 0.05
        }
        let awayAt = h.clock.now
        #expect(h.model.away)
        #expect(awayAt >= riseStart + 3.0 && awayAt <= riseEnd + 3.1)
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
        h.hold(right: 0, for: 2)
        h.activity.send(.moving)
        h.hold(right: 0, for: 0.6)
        #expect(h.model.away)

        h.rise(by: -0.45, over: 1.2)
        // 앉음 확인이 동작 끝 근처에 끝나므로 확인 시간을 넉넉히 기다린 뒤 판정함.
        h.hold(right: 0, for: 1.5)
        #expect(!h.model.away)
        // 앉은 뒤 늦게 온 걷기 callback은 무시돼야 함. 앉은 사용자는 다시 내려앉을 수 없음.
        h.activity.send(.moving)
        h.hold(right: 0, for: 1)
        #expect(!h.model.away)
        #expect(try h.maskAlpha(panel) == [0, 0, 0])
    }

    /// 일어섰다가 3초 안에 다시 앉는 동작 동안 자리 비움이 한 번도 되지 않아야 함.
    /// 앉음 확인이 늦게 끝나는 동안 자리 비움 타이머가 멈춰 있어야 통과함.
    @Test func sittingDownWithinThreeSecondsDoesNotCover() async throws {
        let h = try ProtectionHarness()
        defer { h.tearDown() }
        let panel = try await h.protect()
        h.hold(right: 0, for: 2)
        h.rise(by: 0.45, over: 1.2)
        h.hold(right: 0, for: 1)

        let watch = AwayWatch(h)
        var everCovered = false
        // 앉는 동작 시작부터 끝까지 매 주기 자리 비움과 가림을 기록함. 마스크를 읽지 못해도 가린 것으로 봄.
        h.rise(by: -0.45, over: 1.2) {
            watch.note()
            everCovered = everCovered || (try? h.maskAlpha(panel)) != [0, 0, 0]
        }
        watch.hold(for: 4)

        #expect(!watch.everAway)
        #expect(!h.model.away)
        #expect(!everCovered)
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
        h.hold(right: 0, for: 2)
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

    /// 걸어서 나갔다가 멈추지 않고 걷는 채 다시 앉으면 돌아옴. 걷는 동안의 걸음 신호가 자리 비움을 풀지 않아야 함.
    @Test func walkingBackAndSittingWithoutStoppingReturns() async throws {
        let h = try ProtectionHarness()
        defer { h.tearDown() }
        let panel = try await h.protect()
        h.hold(right: 0, for: 1)
        h.activity.send(.moving)
        h.hold(right: 0, for: 0.6)
        #expect(h.model.away)

        h.walk(for: 3)
        h.rise(by: -0.45, over: 1.2)
        h.hold(right: 0, for: 2)
        #expect(!h.model.away)
        #expect(h.model.captureStatus == "보호 중")
        #expect(try h.maskAlpha(panel) == [0, 0, 0])
    }

    /// 걸어서 자리 비움이 된 뒤 멈추지 않고 걷다 그대로 멈추면 앉지 않았으므로 계속 가림.
    @Test func walkingAwayAndStoppingWithoutSittingStaysCovered() async throws {
        let h = try ProtectionHarness()
        defer { h.tearDown() }
        let panel = try await h.protect()
        h.hold(right: 0, for: 1)
        h.activity.send(.moving)
        h.walk(for: 6)
        h.hold(right: 0, for: 4)
        #expect(h.model.away)
        #expect(try h.maskAlpha(panel) == [255, 255, 255])
    }

    @Test func switchOffNeverCoversOnStandingOrWalking() async throws {
        let h = try ProtectionHarness()
        defer { h.tearDown() }
        h.model.hideWhenAway = false
        let panel = try await h.protect()
        #expect(!h.activity.running)
        h.hold(right: 0, for: 2)
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
        h.hold(right: 0, for: 2)
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
        h.hold(right: 0, for: 2)
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
        h.hold(right: 0, for: 2)
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
        h.hold(right: 0, for: 2)
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

    /// 앉은 채 작은 머리 조정과 자세 고침을 해도 자리 비움이 되지 않음.
    /// 0.1m를 1초에 올렸다 1초에 내리는 조정은 실측 앉은 상태의 최대 속도보다 낮은 동작임.
    @Test func bendingAndAdjustingWhileSeatedDoesNotCover() async throws {
        let h = try ProtectionHarness()
        defer { h.tearDown() }
        let panel = try await h.protect()
        h.hold(right: 0, for: 2)
        let watch = AwayWatch(h)
        // 앉은 채 0.1m 들어 올렸다 내리고, 0.3m 숙였다 펴는 자세 고침은 자리 이탈이 아님.
        h.rise(by: 0.1, over: 1.0, after: watch.note)
        watch.hold(for: 0.5)
        h.rise(by: -0.1, over: 1.0, after: watch.note)
        watch.hold(for: 0.5)
        h.rise(by: -0.3, over: 1.2, after: watch.note)
        watch.hold(for: 1)
        h.rise(by: 0.3, over: 1.2, after: watch.note)
        watch.hold(for: 4)
        #expect(!watch.everAway)
        #expect(!h.model.away)
        #expect(try h.maskAlpha(panel) == [0, 0, 0])
    }

    @Test func coverFadesInOverHalfASecondAfterTheTimerExpires() async throws {
        let h = try ProtectionHarness()
        defer { h.tearDown() }
        let panel = try await h.protect()
        h.hold(right: 0, for: 2)
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
