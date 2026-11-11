import SwiftUI

/// 필수 업데이트 여부. Sparkle 연결부(`SparkleUpdater`)가 갱신하고 설정 화면은 이 값으로 조작을 막음.
/// 메뉴의 보호 켜기와 끄기, 이미 켜진 보호는 막지 않음. 확인 실패나 오프라인은 필수로 보지 않음.
@MainActor
final class UpdateState: ObservableObject {
    /// 필수로 표시된 새 판본의 표시 버전. nil이면 막지 않음.
    @Published private(set) var requiredVersion: String?
    /// 업데이트 창을 여는 동작. 실제 앱은 Sparkle의 업데이트 확인을 연결함.
    var checkForUpdates: @MainActor () -> Void = {}

    func found(version: String, critical: Bool) {
        requiredVersion = critical ? version : nil
    }

    /// 최신 판본임이 확인되면 이전 판정을 지움.
    func upToDate() {
        requiredVersion = nil
    }
}

/// 필수 업데이트가 있으면 설정 화면의 조작을 막고 업데이트 안내만 남김.
struct RequiredUpdateGate: ViewModifier {
    @ObservedObject var state: UpdateState
    let protecting: Bool

    func body(content: Content) -> some View {
        content
            .disabled(state.requiredVersion != nil)
            .overlay {
                if let version = state.requiredVersion {
                    RequiredUpdateNotice(version: version, protecting: protecting, update: state.checkForUpdates)
                }
            }
    }
}

private struct RequiredUpdateNotice: View {
    let version: String
    let protecting: Bool
    let update: @MainActor () -> Void

    var body: some View {
        ZStack {
            Rectangle().fill(.regularMaterial)
            VStack(spacing: 14) {
                Image(systemName: "arrow.down.circle.fill").font(.system(size: 40)).foregroundStyle(.tint)
                Text("필수 업데이트 \(version)").font(.title2.bold())
                Text("이 버전에서는 설정을 더 이상 바꿀 수 없습니다. 업데이트한 뒤 다시 설정해 주세요.")
                    .multilineTextAlignment(.center)
                Text(protecting
                     ? "지금 켜진 보호는 그대로 유지되며 메뉴 막대에서 끌 수 있습니다."
                     : "메뉴 막대의 보호 켜기와 끄기는 이번 실행에서 계속 사용할 수 있습니다.")
                    .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
                Button("업데이트") { update() }
                    .buttonStyle(.borderedProminent).controlSize(.large)
            }
            .padding(32).frame(maxWidth: 440)
        }
        .accessibilityElement(children: .contain)
    }
}
