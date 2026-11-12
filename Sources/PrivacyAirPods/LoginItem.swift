import ServiceManagement
import SwiftUI

// '로그인할 때 열기' 스위치의 상태와 macOS 로그인 항목 연결.
// 앱은 스스로 등록하지 않음. 사용자가 스위치를 켜야만 register를 부름. 시스템 설정에서 바뀐 값은 refresh로 다시 읽음.
// 등록 실패 시 이전 상태를 유지함. 실패 뒤 다시 읽으면 등록되지 않은 값이 켜진 것처럼 보일 수 있어서 읽지 않음.

protocol LoginItemService {
    var status: SMAppService.Status { get }
    func register() throws
    func unregister() throws
    func openSystemSettings()
}

// 테스트는 이 구현을 만들지 않음. 실제 SMAppService 호출은 앱 실행 경로에서만 일어남.
struct SystemLoginItemService: LoginItemService {
    var status: SMAppService.Status { SMAppService.mainApp.status }

    func register() throws {
        try SMAppService.mainApp.register()
    }

    func unregister() throws {
        try SMAppService.mainApp.unregister()
    }

    func openSystemSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}

enum LoginItemStatus: Equatable {
    case off
    case on
    case needsApproval

    /// 한 번도 등록하지 않은 앱도 .notFound를 받음. 이를 막힘으로 보면 스위치를 켤 길이 없으므로
    /// 꺼짐으로 보고, 등록이 실제로 안 되면 register 오류 문구로 알림.
    init(_ status: SMAppService.Status) {
        switch status {
        case .enabled: self = .on
        case .requiresApproval: self = .needsApproval
        case .notRegistered, .notFound: self = .off
        @unknown default: self = .off
        }
    }
}

@MainActor
final class LoginItemState: ObservableObject {
    @Published private(set) var status: LoginItemStatus
    @Published private(set) var errorMessage: String?

    private let service: LoginItemService

    init(service: LoginItemService) {
        self.service = service
        status = LoginItemStatus(service.status)
    }

    func setEnabled(_ enabled: Bool) {
        do {
            if enabled {
                try service.register()
            } else {
                try service.unregister()
            }
        } catch {
            errorMessage = "로그인 항목을 바꾸지 못했어요. 잠시 뒤 다시 시도해 주세요"
            return
        }
        errorMessage = nil
        status = LoginItemStatus(service.status)
    }

    // 시스템 설정에서 사용자가 바꾼 값을 읽음. 설정 창이 보일 때와 앱이 활성화될 때 부름.
    func refresh() {
        errorMessage = nil
        status = LoginItemStatus(service.status)
    }

    func openSystemSettings() {
        service.openSystemSettings()
    }
}
