import Testing
import PrivacyCore
@testable import PrivacyAirPods

@MainActor
struct InputLossTests {
    @Test(arguments: [false, true])
    func defaultInputLossStopsActiveOrStartingProtection(starting: Bool) {
        let model = AppModel()
        #expect(!model.retainBlurOnInputLoss)
        model.protected = !starting
        model.startingProtection = starting
        model.deskReference = 20
        model.stopMotion()
        #expect(!model.protected)
        #expect(!model.startingProtection)
        #expect(!model.suspended)
        #expect(model.deskReference == nil)
        #expect(!model.canProtect)
    }

    @Test func optedInInputLossCoversEveryDisplayUntilOptionIsDisabled() throws {
        let model = AppModel()
        model.displays = [DisplayCalibration(id: 11, name: "left"), DisplayCalibration(id: 12, name: "right")]
        model.retainBlurOnInputLoss = true
        model.protected = true
        defer { model.stopProtection() }
        model.stopMotion()
        #expect(model.protected)
        #expect(model.suspended)
        let settings = model.settingsByDisplay()
        #expect(settings.count == 2)
        for id in [11, 12] {
            let setting = try #require(settings[UInt32(id)])
            for x in [0.0, 0.5, 1.0] { #expect(setting.strength(at: x) == 1) }
        }
        model.retainBlurOnInputLoss = false
        #expect(!model.protected)
        #expect(!model.suspended)
    }

    @Test func changingInputPreferenceDoesNotReleaseOtherSuspension() {
        let model = AppModel()
        model.retainBlurOnInputLoss = true
        model.protected = true
        model.suspended = true
        defer { model.stopProtection() }
        model.retainBlurOnInputLoss = false
        #expect(model.protected)
        #expect(model.suspended)
    }
}
