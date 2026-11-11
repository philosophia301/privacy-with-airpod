import AppKit
import Testing
import PrivacyCore
@testable import PrivacyAirPods

/// 사용자 흐름 e2e. 실제 AppModel과 WindowServer 가림 창의 마스크를 관측함.
/// AirPods, 시계, 시스템 알림만 대역이며 실제 머리 움직임 감지나 사람이 보는 화면 품질은 증명하지 않음.
@MainActor
@Suite(.serialized)
struct ProtectionFlowTests {
    @Test func turningHeadMovesBlurAcrossTheLiveCover() async throws {
        let h = try ProtectionHarness()
        defer { h.model.stopProtection() }
        let panel = try await h.protect()
        #expect(panel.isVisible)
        #expect(panel.frame.size == NSScreen.screens.first?.frame.size)
        // 정면에서는 화면 전체(±18.4°)가 시작 각도 35° 안이라 선명함.
        #expect(try h.maskAlpha(panel) == [0, 0, 0])

        // 고개를 홱 돌려도 한 주기에 전부 가리지 않고 전환 시간에 따라 먼 쪽부터 진행함.
        h.look(right: 90)
        h.clock.advance()
        let first = try h.maskAlpha(panel)
        #expect(first[0] > 0 && first[0] < 255)
        #expect(first[1] == 0 && first[2] == 0)

        h.hold(right: 90)
        #expect(try h.maskAlpha(panel) == [255, 255, 255])
        h.hold(right: 45)
        #expect(try h.maskAlpha(panel) == [255, 255, 0])
        h.hold(right: -45)
        #expect(try h.maskAlpha(panel) == [0, 255, 255])
        h.hold(right: 0)
        #expect(try h.maskAlpha(panel) == [0, 0, 0])

        h.model.stopProtection()
        #expect(!panel.isVisible)
        #expect(h.model.protectionWindows.isEmpty)
    }

    @Test func outOfOrderSampleDoesNotMoveTheBlur() async throws {
        let h = try ProtectionHarness()
        defer { h.model.stopProtection() }
        let panel = try await h.protect()
        h.hold(right: 45)
        #expect(try h.maskAlpha(panel) == [255, 255, 0])
        // 늦게 도착한 과거 측정값이 반영되면 가운데가 35° 안으로 돌아와 선명해짐.
        h.look(right: 0, measuredAgo: 0.5)
        h.clock.advance()
        #expect(try h.maskAlpha(panel) == [255, 255, 0])
        #expect(h.model.protected)
    }

    enum InputLoss: String, CaseIterable, CustomTestStringConvertible {
        case silence, sensorError, earbudSwitch, staleSample, sleep, stopInput
        var testDescription: String { rawValue }
    }

    @Test(arguments: InputLoss.allCases, [false, true])
    func inputLossReleasesByDefaultOrKeepsFullBlurWhenOptedIn(_ loss: InputLoss, retain: Bool) async throws {
        let h = try ProtectionHarness()
        defer { h.model.stopProtection() }
        h.model.retainBlurOnInputLoss = retain
        let panel = try await h.protect()
        h.hold(right: 0, for: 0.5)

        switch loss {
        case .silence:
            for _ in 0..<16 { h.clock.advance() }
        case .sensorError:
            h.motion.fail("AirPods 연결 끊김")
        case .earbudSwitch:
            h.look(right: 0, source: 2)
        case .staleSample:
            h.look(right: 0, measuredAgo: 1)
        case .sleep:
            h.workspace.post(name: NSWorkspace.willSleepNotification, object: nil)
            #expect(!h.motion.running)
        case .stopInput:
            h.model.stopMotion()
        }

        #expect(h.model.deskReference == nil)
        #expect(!h.model.canProtect)
        guard retain else {
            #expect(!h.model.protected)
            #expect(!panel.isVisible)
            #expect(h.model.protectionWindows.isEmpty)
            return
        }
        #expect(h.model.protected && h.model.suspended)
        #expect(panel.isVisible)
        #expect(try h.maskAlpha(panel) == [255, 255, 255])

        // 다시 착용해 입력이 돌아와도 보호를 끄고 재보정하기 전에는 가림을 풀지 않음.
        h.model.startMotion()
        h.hold(right: 0, for: 1)
        h.model.calibrateDesk()
        #expect(h.model.deskReference == nil)
        #expect(try h.maskAlpha(panel) == [255, 255, 255])

        h.model.retainBlurOnInputLoss = false
        #expect(!h.model.protected)
        #expect(!panel.isVisible)
    }

    @Test func screenChangeStopsProtectionAndRequiresNewLayout() async throws {
        let h = try ProtectionHarness()
        defer { h.model.stopProtection() }
        let panel = try await h.protect()
        h.notifications.post(name: NSApplication.didChangeScreenParametersNotification, object: nil)
        #expect(!h.model.protected)
        #expect(!panel.isVisible)
        #expect(h.model.appliedPoses.isEmpty)

        h.hold(right: 0, for: 0.2)
        h.model.calibrateDesk()
        #expect(!h.model.canProtect)
        #expect(h.model.applyLayout(h.frontLayout))
        #expect(h.model.canProtect)
    }

    @Test func outputFailureKeepsEmergencyCoverUntilUserStops() async throws {
        let h = try ProtectionHarness()
        defer { h.model.stopProtection() }
        let panel = try await h.protect()
        let backdrop = try #require(panel.contentView as? SpaceTransitionBackdrop)
        // UI 범위 밖 값으로 WindowServer 마스크 제출 실패를 일으킴.
        h.model.maximumBlur = .nan
        h.clock.advance()
        #expect(backdrop.emergencyCovered)
        #expect(h.model.protected && h.model.suspended)
        #expect(panel.isVisible)

        // 값이 정상으로 돌아오거나 입력 중단 옵션을 바꿔도 비상 가림은 유지됨.
        h.model.maximumBlur = 31.25
        h.hold(right: 0, for: 0.5)
        h.model.retainBlurOnInputLoss = true
        h.model.retainBlurOnInputLoss = false
        #expect(backdrop.emergencyCovered)
        #expect(h.model.protected)
        #expect(panel.isVisible)

        h.model.stopProtection()
        #expect(!panel.isVisible)
    }

    @Test func appliedLayoutDecidesWhichScreenAnglesBlur() async throws {
        let h = try ProtectionHarness()
        defer { h.model.stopProtection() }
        // 40cm 화면을 오른쪽 60cm에 둠. 화면 각도는 약 33.7°~53.1°라 정면에서는 대부분 가려짐.
        let side = [DisplayPose(id: h.display.id, width: 40, height: 25, x: 60, y: 0, z: 60, yawDegrees: 0)]
        let panel = try await h.protect(layout: side)
        #expect(try h.maskAlpha(panel) == [0, 255, 255])
        h.hold(right: 45)
        #expect(try h.maskAlpha(panel) == [0, 0, 0])

        // 보호 중에는 배치를 바꾸지 않음.
        #expect(!h.model.applyLayout(h.frontLayout))
        #expect(h.model.appliedPoses == side)
        h.model.stopProtection()

        var behindEyes = h.frontLayout
        behindEyes[0].z = 0
        let invalid: [[DisplayPose]] = [
            [], behindEyes, h.frontLayout + h.frontLayout,
            [DisplayPose(id: h.display.id &+ 1, width: 40, height: 25, x: 0, y: 0, z: 60, yawDegrees: 0)]
        ]
        for poses in invalid { #expect(!h.model.applyLayout(poses)) }
        #expect(h.model.appliedPoses == side)
    }

    @Test func protectionNeedsFreshInputCalibrationAndLayout() async throws {
        let h = try ProtectionHarness()
        defer { h.model.stopProtection() }
        func expectRefused() async {
            #expect(!h.model.canProtect)
            await h.model.startProtection()
            #expect(!h.model.protected)
            #expect(h.model.protectionWindows.isEmpty)
        }
        await expectRefused()
        h.model.startMotion()
        h.look(right: 0)
        await expectRefused()
        #expect(h.model.applyLayout(h.frontLayout))
        await expectRefused()
        h.model.calibrateDesk()
        #expect(h.model.canProtect)
        // 보정 뒤 입력이 끊기면 다시 거부함.
        for _ in 0..<16 { h.clock.advance() }
        await expectRefused()
    }

    @Test func idleAppStopsPeriodicUpdates() async throws {
        let h = try ProtectionHarness()
        defer { h.model.stopProtection() }
        #expect(!h.clock.running)
        h.model.setPreviewWindowVisible(true)
        #expect(h.clock.running)
        h.model.setPreviewWindowVisible(false)
        #expect(!h.clock.running)

        try await h.protect()
        #expect(h.clock.running)
        h.model.stopMotion()
        #expect(!h.model.protected)
        #expect(!h.clock.running)
    }
}
