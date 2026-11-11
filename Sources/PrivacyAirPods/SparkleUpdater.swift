import Foundation
import Sparkle

/// Sparkle 연결부. 실행 시 한 번과 Sparkle 기본 주기(하루)마다 appcast를 확인함.
/// critical로 표시된 새 판본이 있으면 `UpdateState`를 필수로 바꾸고, 설치는 Sparkle 표준 창이 맡음.
/// Blur Lab 빌드에는 포함하지 않음.
@MainActor
final class SparkleUpdater: ObservableObject {
    let state = UpdateState()
    let updater: SPUUpdater
    private let delegate: Delegate

    /// 실제 앱은 앱 번들과 Sparkle 표준 업데이트 창을 씀. 시험은 가짜 번들과 조용한 user driver를 넣음.
    init(hostBundle: Bundle = .main, userDriver: (any SPUUserDriver)? = nil) {
        delegate = Delegate(state: state)
        updater = SPUUpdater(hostBundle: hostBundle, applicationBundle: hostBundle,
                             userDriver: userDriver ?? SPUStandardUserDriver(hostBundle: hostBundle, delegate: nil),
                             delegate: delegate)
        state.checkForUpdates = { [updater] in updater.checkForUpdates() }
        do {
            try updater.start()
        } catch {
            // 설정 오류는 업데이트만 끄고 보호와 설정은 막지 않음.
            NSLog("Privacy AirPods 업데이트 확인을 시작하지 못함: %@", error.localizedDescription)
            return
        }
        // Sparkle 주기와 무관하게 실행할 때마다 필수 여부를 다시 판정함. 확인 실패는 판정을 바꾸지 않음.
        updater.checkForUpdatesInBackground()
    }

    /// Sparkle은 delegate를 약하게 참조하므로 SparkleUpdater가 소유함. 호출은 메인 스레드에서 옴.
    private final class Delegate: NSObject, SPUUpdaterDelegate {
        private let state: UpdateState

        init(state: UpdateState) { self.state = state }

        nonisolated func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
            let version = item.displayVersionString
            let critical = item.isCriticalUpdate
            MainActor.assumeIsolated { state.found(version: version, critical: critical) }
        }

        nonisolated func updaterDidNotFindUpdate(_ updater: SPUUpdater) {
            MainActor.assumeIsolated { state.upToDate() }
        }
    }
}
