import SwiftUI
import AppKit

// 설정 창 루트. 상태 카드, 폴더 탭, 판본 줄을 조립함. 준비 규칙과 보호 정책은 AppModel과 Readiness가 소유함.
// 이 view는 sample마다 바뀌는 값(LiveReadout)을 읽지 않음. 읽으면 steady 입력에서도 창 전체가 다시 그려짐.

enum SettingsTab {
    case ready, hide
}

struct SettingsView: View {
    @ObservedObject var model: AppModel
    let update: UpdateState
    @ObservedObject var loginItem: LoginItemState
    @State private var tab = SettingsTab.ready
    @State private var cheering = false
    @State private var cheerToken = 0
    @State private var showingLayout = false

    var body: some View {
        VStack(spacing: 16) {
            StatusHero(model: model, mood: mood) { tab = .ready }
            // 탭 아래 2pt를 패널 윗선에 겹쳐 그림. 고른 탭은 그 선을 덮어 패널과 한 장처럼 이어짐.
            VStack(spacing: 0) {
                tabBar.padding(.bottom, -2).zIndex(1)
                panel
            }
            footer
        }
        .padding(.horizontal, 20)
        .padding(.top, 14)
        .padding(.bottom, 16)
        .frame(minWidth: 600, maxWidth: .infinity, minHeight: 760, maxHeight: .infinity, alignment: .top)
        .background(CheekyPalette.cream)
        .preferredColorScheme(.light)
        .modifier(RequiredUpdateGate(state: update, protecting: model.protected || model.startingProtection))
        .sheet(isPresented: $showingLayout) { LayoutSheet(model: model, update: update) }
        .task(id: cheerToken) { await holdCheer(token: cheerToken) }
        // 설정 창이 보일 때와 앱이 활성화될 때 시스템 설정에서 바뀐 로그인 항목 값을 다시 읽음.
        .onAppear { loginItem.refresh() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            loginItem.refresh()
        }
    }

    private var mood: CharacterMood {
        CharacterMood.resolve(base: model.heroMood, cheering: cheering)
    }

    // 정면 맞추기가 실제로 성공한 뒤에만 cheer를 켬. 연속으로 누르면 토큰이 바뀌어 1.8초가 다시 잼.
    private func calibrate() {
        guard model.calibrateDesk() else { return }
        cheering = true
        cheerToken += 1
    }

    // 취소되면 이전 토큰의 대기가 새 cheer를 끄지 않도록 바로 빠져나감.
    private func holdCheer(token: Int) async {
        guard token > 0 else { return }
        do {
            try await Task.sleep(for: .milliseconds(1800))
        } catch {
            return
        }
        cheering = false
    }

    private var tabBar: some View {
        HStack(spacing: 6) {
            SettingsTabButton(title: "준비", selected: tab == .ready, action: { tab = .ready }) {
                readyAccessory
            }
            SettingsTabButton(title: "가리기", selected: tab == .hide, action: { tab = .hide }) {
                EmptyView()
            }
        }
        .padding(.leading, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var readyAccessory: some View {
        let remaining = model.readinessRemaining
        if remaining == 0 {
            DoneBadge(size: 18)
        } else {
            Text("\(remaining)")
                .font(CheekyFont.display(12))
                .foregroundStyle(CheekyPalette.cream)
                .frame(minWidth: 20, minHeight: 20)
                .padding(.horizontal, 5)
                .background(Capsule().fill(CheekyPalette.cocoa))
                .accessibilityLabel("남은 준비 \(remaining)개")
        }
    }

    private var panel: some View {
        Group {
            switch tab {
            case .ready:
                ReadyTab(model: model, loginItem: loginItem, onCalibrate: calibrate, onOpenLayout: { showingLayout = true })
            case .hide:
                HideTab(model: model)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .cheekyCard()
        .padding(.bottom, 3)
    }

    private var footer: some View {
        HStack(spacing: 10) {
            Text(versionLabel)
                .font(CheekyFont.display(12))
                .foregroundStyle(CheekyPalette.yellow)
                .padding(.horizontal, 10)
                .padding(.vertical, 3)
                .background(Capsule().fill(CheekyPalette.cocoa))
            Button("업데이트 확인") { update.checkForUpdates() }
                .buttonStyle(CheekyButtonStyle())
            Spacer(minLength: 0)
            Text("© The Pinkfong Company")
                .font(CheekyFont.text(11, weight: .medium))
                .foregroundStyle(CheekyPalette.tan)
        }
    }

    // MenuBarVersionText와 같은 Info.plist 키를 읽음. 개발 실행에는 판본 키가 없어 dev로 표시함.
    private var versionLabel: String {
        let short = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
        guard let short, !short.isEmpty else { return "dev" }
        return "v\(short)"
    }
}

private struct SettingsTabButton<Accessory: View>: View {
    let title: String
    let selected: Bool
    let action: () -> Void
    @ViewBuilder let accessory: () -> Accessory

    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                Text(title).font(CheekyFont.text(15, weight: .bold))
                accessory()
            }
            .foregroundStyle(CheekyPalette.ink)
            .padding(.horizontal, 20)
            .frame(height: 40)
            .padding(.bottom, 2)
            .background(UnevenRoundedRectangle(topLeadingRadius: 14, topTrailingRadius: 14)
                .fill(selected ? CheekyPalette.white : CheekyPalette.tabOff))
            .overlay(FolderTabOutline(radius: 14).stroke(CheekyPalette.cocoa, lineWidth: 2))
            .overlay(alignment: .bottom) {
                // 고르지 않은 탭은 패널 윗선을 덮지 않도록 그 자리에 선을 다시 그림.
                if !selected {
                    Rectangle().fill(CheekyPalette.cocoa).frame(height: 2).padding(.bottom, 1)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// 아래가 열린 폴더 탭 테두리. 아래쪽은 패널 윗선이 맡음.
private struct FolderTabOutline: Shape {
    let radius: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + radius))
        path.addArc(center: CGPoint(x: rect.minX + radius, y: rect.minY + radius), radius: radius,
                    startAngle: .degrees(180), endAngle: .degrees(270), clockwise: false)
        path.addLine(to: CGPoint(x: rect.maxX - radius, y: rect.minY))
        path.addArc(center: CGPoint(x: rect.maxX - radius, y: rect.minY + radius), radius: radius,
                    startAngle: .degrees(270), endAngle: .degrees(0), clockwise: false)
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        return path
    }
}

// 상태 카드. 보호 중에는 노랑 바탕과 체커 띠를 씀. 보호 제목의 툴팁은 실제 보호 상태 문구임.
private struct StatusHero: View {
    @ObservedObject var model: AppModel
    let mood: CharacterMood
    let showReady: () -> Void

    var body: some View {
        let guarded = model.protected || model.startingProtection
        let remaining = model.readinessRemaining
        HStack(spacing: 10) {
            CharacterPose(mood: mood)
            VStack(alignment: .leading, spacing: 7) {
                SpeechBubble(text: mood.bubble)
                Text(title)
                    .font(CheekyFont.text(28, weight: .bold))
                    .help(Text(model.captureStatus))
                    .accessibilityHint(Text(model.captureStatus))
                CoinRow(items: model.readinessItems)
            }
            Spacer(minLength: 0)
            VStack(spacing: 6) {
                Button(guarded ? "보호 끄기" : "보호 켜기") { model.toggleProtection() }
                    .buttonStyle(CheekyButtonStyle(variant: guarded ? .plain : .cocoa, size: .large))
                    .disabled(!guarded && !model.canProtect)
                if remaining > 0 && !guarded {
                    Button("준비 \(remaining)개 남음") { showReady() }
                        .buttonStyle(.plain)
                        .font(CheekyFont.text(12, weight: .semibold))
                        .foregroundStyle(CheekyPalette.cocoa)
                        .underline()
                }
            }
        }
        .padding(.leading, 6)
        .padding(.trailing, 18)
        .padding(.top, model.protected ? 26 : 12)
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .top) {
            if model.protected {
                CheckerBand(height: 16).overlay(alignment: .bottom) {
                    Rectangle().fill(CheekyPalette.cocoa).frame(height: 2)
                }
            }
        }
        // 체커 띠가 카드 모서리 밖으로 나가지 않도록 띠까지 포함해 잘라냄. 테두리는 cheekyCard가 따로 그림.
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .cheekyCard(background: model.protected ? CheekyPalette.yellow : CheekyPalette.white)
        .padding(.bottom, 3)
    }

    private var title: String {
        if model.startingProtection { return "준비 중" }
        guard model.protected else { return "보호 꺼짐" }
        return model.suspended ? "전체를 가리는 중" : "보호 중"
    }
}

// 136x112 칸 안에서 비율을 유지한 축소만 함. 그림을 못 읽으면 칸만 비우고 나머지는 그대로 둠.
private struct CharacterPose: View {
    let mood: CharacterMood

    var body: some View {
        ZStack(alignment: .bottom) {
            Ellipse()
                .fill(CheekyPalette.cocoa.opacity(0.16))
                .frame(height: 12)
                .padding(.horizontal, 20)
                .padding(.bottom, 2)
            if let image = CharacterArt.image(for: mood) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: 136, maxHeight: 108)
                    .accessibilityHidden(true)
            }
        }
        .frame(width: 136, height: 112)
    }
}

private struct SpeechBubble: View {
    let text: String

    var body: some View {
        Text(text)
            .font(CheekyFont.text(13, weight: .semibold))
            .foregroundStyle(CheekyPalette.ink)
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .background(RoundedRectangle(cornerRadius: 14).fill(CheekyPalette.white))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(CheekyPalette.cocoa, lineWidth: 2))
            // 꼬리는 말풍선 바탕 뒤에 둠. 안쪽 절반은 바탕에 가려지고 바깥 절반만 보임.
            .background(alignment: .leading) {
                Rectangle()
                    .fill(CheekyPalette.white)
                    .overlay(Rectangle().stroke(CheekyPalette.cocoa, lineWidth: 2))
                    .frame(width: 10, height: 10)
                    .rotationEffect(.degrees(45))
                    .offset(x: -5)
            }
            .padding(.leading, 6)
    }
}

// 준비 항목 순서대로 D O O 동전을 그림. 끝난 동전은 노랑 실선과 기울임, 남은 동전은 점선 cream.
private struct CoinRow: View {
    let items: [ReadinessItem]
    private let letters = ["D", "O", "O"]

    var body: some View {
        let done = items.filter { $0.state == .done }.count
        HStack(spacing: 4) {
            ForEach(items.indices, id: \.self) { index in
                Coin(letter: letters[index % letters.count],
                     done: items[index].state == .done,
                     tilt: index == 1 ? 6 : -6)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("준비 \(items.count)개 중 \(done)개 끝남")
    }
}

private struct Coin: View {
    let letter: String
    let done: Bool
    let tilt: Double

    var body: some View {
        Text(letter)
            .font(CheekyFont.display(12))
            .foregroundStyle(done ? CheekyPalette.ink : CheekyPalette.tan)
            .frame(width: 24, height: 24)
            .background(Circle().fill(done ? CheekyPalette.yellow : CheekyPalette.cream))
            .overlay(Circle().stroke(CheekyPalette.cocoa, style: StrokeStyle(lineWidth: 2, dash: done ? [] : [3, 2.5])))
            .background(Circle().fill(CheekyPalette.cocoa).offset(y: 2).opacity(done ? 1 : 0))
            .rotationEffect(.degrees(done ? tilt : 0))
    }
}
