import AppKit
import Testing
@testable import PrivacyAirPods

/// 실제 본체 보정→출력→입력 중단 연결을 검사함. 센서 입력은 합성이며 화면 전환은 하지 않음.
@MainActor
struct ProductProtectionTests {
    @Test(arguments: [false, true])
    func calibratedProductStartsOnBuiltinAndHonorsInputLoss(retain: Bool) async throws {
        let screen = try #require(NSScreen.screens.first { CGDisplayIsBuiltin($0.displayID) != 0 })
        let model = AppModel()
        model.displays = model.displays.filter { $0.id == screen.displayID }
        model.selectedDisplay = screen.displayID
        model.retainBlurOnInputLoss = retain
        defer { model.stopProtection() }
        let now = ProcessInfo.processInfo.systemUptime
        model.sample = HeadSample(timestamp: now, receivedAt: now, yaw: 0,
                                  acceleration: .zero, gravity: SIMD3(0, -1, 0), source: 1)
        model.receiving = true
        model.calibrateDesk()
        #expect(model.applyLayout(model.layoutDraft))
        #expect(model.canProtect)
        model.toggleProtection()
        // 시작 작업의 완료만 기다림. 타이머/센서 유효 기간을 늘리지 않음.
        for _ in 0..<100 where model.startingProtection { await Task.yield() }
        #expect(model.protected)
        #expect(!model.startingProtection)
        let panel = try #require(model.protectionWindows.first)
        #expect(panel.frame == screen.frame)
        let view = try #require(panel.contentView as? SpaceTransitionBackdrop)
        model.stopMotion()
        #expect(model.deskReference == nil)
        #expect(!model.canProtect)
        #expect(model.protected == retain)
        #expect(panel.isVisible == retain)
        #expect(!view.emergencyCovered)
        if retain {
            let mask = try #require(view.maskImage)
            let data = try #require(mask.dataProvider?.data)
            let bytes = try #require(CFDataGetBytePtr(data))
            for x in [0, 128, 255] { #expect(bytes[x * 4 + 3] == 255) }
            model.retainBlurOnInputLoss = false
            #expect(!panel.isVisible)
            #expect(!model.protected)
        }
    }
}
