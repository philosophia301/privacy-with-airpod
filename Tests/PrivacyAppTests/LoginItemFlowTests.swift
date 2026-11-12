import ServiceManagement
import Testing
@testable import PrivacyAirPods

/// 로그인할 때 열기 스위치 흐름. 로그인 항목 서비스만 가짜이며 실제 SMAppService는 호출하지 않음.
/// 실제 macOS 로그인 항목 등록과 시스템 설정 화면의 표시는 증명하지 않음.
@MainActor
@Suite(.serialized)
struct LoginItemFlowTests {
    @Test func startsOffWithoutRegisteringAnything() {
        let service = FakeLoginItemService(status: .notRegistered)
        let state = LoginItemState(service: service)
        #expect(state.status == .off)
        #expect(service.registerCalls == 0 && service.unregisterCalls == 0)
    }

    @Test func turningOnRegistersOnceAndShowsOn() {
        let service = FakeLoginItemService(status: .notRegistered)
        let state = LoginItemState(service: service)
        state.setEnabled(true)
        #expect(service.registerCalls == 1)
        #expect(state.status == .on)
        #expect(state.errorMessage == nil)
    }

    @Test func turningOffUnregistersOnceAndShowsOff() {
        let service = FakeLoginItemService(status: .notRegistered)
        let state = LoginItemState(service: service)
        state.setEnabled(true)
        state.setEnabled(false)
        #expect(service.unregisterCalls == 1)
        #expect(state.status == .off)
    }

    @Test func failedRegisterKeepsOffAndShowsErrorMessage() {
        let service = FakeLoginItemService(status: .notRegistered)
        service.registerError = FakeLoginItemError.denied
        let state = LoginItemState(service: service)
        state.setEnabled(true)
        #expect(state.status == .off)
        #expect(state.errorMessage != nil)
    }

    @Test func registerThatNeedsUserApprovalShowsNeedsApproval() {
        let service = FakeLoginItemService(status: .notRegistered)
        service.statusAfterRegister = .requiresApproval
        let state = LoginItemState(service: service)
        state.setEnabled(true)
        #expect(state.status == .needsApproval)
    }

    @Test func refreshReflectsChangeMadeInSystemSettings() {
        let service = FakeLoginItemService(status: .notRegistered)
        let state = LoginItemState(service: service)
        service.status = .enabled
        // 설정 창이 보이거나 앱이 활성화되기 전에는 이전에 읽은 값을 유지함.
        #expect(state.status == .off)
        state.refresh()
        #expect(state.status == .on)
    }

    /// 한 번도 등록하지 않은 앱은 실제 SMAppService에서 .notFound를 받음. 스위치가 막히면 켤 수 없음.
    @Test func neverRegisteredAppStartsOffAndCanBeTurnedOn() {
        let service = FakeLoginItemService(status: .notFound)
        let state = LoginItemState(service: service)
        #expect(state.status == .off)
        state.setEnabled(true)
        #expect(service.registerCalls == 1)
        #expect(state.status == .on)
        #expect(state.errorMessage == nil)
    }

    @Test func openSystemSettingsIsForwardedToService() {
        let service = FakeLoginItemService(status: .requiresApproval)
        let state = LoginItemState(service: service)
        state.openSystemSettings()
        #expect(service.openSystemSettingsCalls == 1)
    }
}

private enum FakeLoginItemError: Error {
    case denied
}

/// 가짜 로그인 항목. register와 unregister는 상태만 바꾸고 실제 등록은 하지 않음.
private final class FakeLoginItemService: LoginItemService {
    var status: SMAppService.Status
    var statusAfterRegister: SMAppService.Status = .enabled
    var registerError: Error?
    var registerCalls = 0
    var unregisterCalls = 0
    var openSystemSettingsCalls = 0

    init(status: SMAppService.Status) {
        self.status = status
    }

    func register() throws {
        registerCalls += 1
        if let registerError { throw registerError }
        status = statusAfterRegister
    }

    func unregister() throws {
        unregisterCalls += 1
        status = .notRegistered
    }

    func openSystemSettings() {
        openSystemSettingsCalls += 1
    }
}
