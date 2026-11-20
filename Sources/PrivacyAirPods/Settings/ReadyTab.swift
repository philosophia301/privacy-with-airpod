import SwiftUI

// 준비 탭. 준비 항목을 스탬프 타일로 그리고 '로그인할 때 열기' 줄을 둠.
// 항목의 상태와 문구는 Readiness가 소유함. 여기서는 표시와 동작 연결만 함.

struct ReadyTab: View {
    @ObservedObject var model: AppModel
    @ObservedObject var loginItem: LoginItemState
    let onCalibrate: () -> Void
    let onOpenLayout: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                ForEach(model.readinessItems) { item in
                    ReadinessTile(item: item) { perform(item.kind) }
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            LoginItemRow(loginItem: loginItem)
        }
    }

    private func perform(_ kind: ReadinessKind) {
        switch kind {
        case .airPods: model.startMotion()
        case .desk: onCalibrate()
        case .screens: onOpenLayout()
        }
    }
}

private struct ReadinessTile: View {
    let item: ReadinessItem
    let action: () -> Void

    private let shape = RoundedRectangle(cornerRadius: 16)

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                Circle().fill(CheekyPalette.white)
                Circle().stroke(CheekyPalette.cocoa, lineWidth: 2)
                StampIcon(kind: item.kind)
                    .frame(width: 28, height: 28)
            }
            .frame(width: 50, height: 50)
            .padding(.top, 8)
            Text(item.label)
                .font(CheekyFont.text(14, weight: .bold))
            Text(item.status)
                .font(CheekyFont.text(12, weight: .semibold))
                .foregroundStyle(item.state == .todo ? CheekyPalette.ink : CheekyPalette.cocoa)
            if let why = item.why {
                Text(why)
                    .font(CheekyFont.text(11, weight: .medium))
                    .foregroundStyle(CheekyPalette.cocoa)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            if let title = item.actionTitle {
                Button(title, action: action)
                    .buttonStyle(CheekyButtonStyle(variant: item.state == .todo ? .cocoa : .plain))
                    .disabled(!item.actionEnabled)
                    .padding(.top, 4)
            }
        }
        .padding(.init(top: 22, leading: 10, bottom: 14, trailing: 10))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(shape.fill(item.state == .wait ? CheekyPalette.cream : CheekyPalette.white))
        // 그림자는 바탕 뒤에 둬야 타일 아래로만 3pt 보임. 순서를 바꾸면 바탕이 그림자에 가려짐.
        .background {
            if item.state == .todo {
                shape.fill(CheekyPalette.cocoa).offset(y: 3)
            }
        }
        .overlay(shape.strokeBorder(CheekyPalette.cocoa,
                                    style: StrokeStyle(lineWidth: 2, dash: item.state == .wait ? [5, 4] : [])))
        .overlay(alignment: .top) {
            if item.state == .todo {
                VStack(spacing: 0) {
                    TapeStripe(height: 10)
                    Rectangle().fill(CheekyPalette.cocoa).frame(height: 2)
                }
                .frame(maxWidth: .infinity, maxHeight: 12, alignment: .top)
                .clipShape(shape)
            }
        }
        .overlay(alignment: .topTrailing) {
            badge
                .rotationEffect(.degrees(8))
                .padding(.init(top: 14, leading: 0, bottom: 0, trailing: 8))
        }
    }

    @ViewBuilder
    private var badge: some View {
        switch item.state {
        case .done: DoneBadge(size: 30)
        case .todo: TodoBadge(size: 30)
        case .wait: WaitBadge(size: 30)
        }
    }
}

// 선 아이콘은 Tab2 시안의 22pt viewBox 좌표를 그대로 씀. 원호는 같은 중심과 반지름의 원으로 바꿈.
private struct StampIcon: View {
    let kind: ReadinessKind

    var body: some View {
        Canvas { context, size in
            var scaled = context
            scaled.concatenate(CGAffineTransform(scaleX: size.width / 22, y: size.height / 22))
            let style = StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round)
            for path in Self.paths(for: kind) {
                scaled.stroke(path, with: .color(CheekyPalette.cocoa), style: style)
            }
        }
        .accessibilityHidden(true)
    }

    private static func paths(for kind: ReadinessKind) -> [Path] {
        switch kind {
        case .airPods:
            return [
                Path(ellipseIn: CGRect(x: 4.5, y: 4.5, width: 5, height: 5)),
                line(from: CGPoint(x: 9.5, y: 7), to: CGPoint(x: 9.5, y: 16)),
                Path(ellipseIn: CGRect(x: 12.5, y: 4.5, width: 5, height: 5)),
                line(from: CGPoint(x: 12.5, y: 7), to: CGPoint(x: 12.5, y: 16))
            ]
        case .desk:
            var arrow = Path()
            arrow.move(to: CGPoint(x: 7.8, y: 9.4))
            arrow.addLine(to: CGPoint(x: 11, y: 6.2))
            arrow.addLine(to: CGPoint(x: 14.2, y: 9.4))
            return [
                Path(ellipseIn: CGRect(x: 3.5, y: 3.5, width: 15, height: 15)),
                line(from: CGPoint(x: 11, y: 15), to: CGPoint(x: 11, y: 6.5)),
                arrow
            ]
        case .screens:
            return [
                Path(CGRect(x: 1.5, y: 6, width: 6.5, height: 5)),
                Path(CGRect(x: 7.5, y: 3, width: 7, height: 7)),
                Path(CGRect(x: 14, y: 6, width: 6.5, height: 5)),
                line(from: CGPoint(x: 11, y: 10), to: CGPoint(x: 11, y: 14)),
                line(from: CGPoint(x: 8, y: 15), to: CGPoint(x: 14, y: 15))
            ]
        }
    }

    private static func line(from start: CGPoint, to end: CGPoint) -> Path {
        var path = Path()
        path.move(to: start)
        path.addLine(to: end)
        return path
    }
}

// '로그인할 때 열기' 줄. 기본은 꺼짐이며 사용자가 켜야 macOS 로그인 항목에 등록됨.
// 스위치 값과 등록 결과는 LoginItemState가 소유하고 여기서는 표시와 안내만 함.
private struct LoginItemRow: View {
    @ObservedObject var loginItem: LoginItemState

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 12) {
                Text("로그인할 때 열기")
                    .font(CheekyFont.text(14, weight: .bold))
                Spacer(minLength: 0)
                Toggle("로그인할 때 열기", isOn: Binding(
                    get: { loginItem.status == .on },
                    set: { loginItem.setEnabled($0) }
                ))
                .toggleStyle(.switch)
                .labelsHidden()
                .tint(CheekyPalette.cocoa)
            }
            notice
        }
    }

    // 오류 문구는 상태별 안내 앞에 붙임. 승인 대기 중에 오류가 나도 시스템 설정으로 가는 길은 남김.
    @ViewBuilder
    private var notice: some View {
        if let message = loginItem.errorMessage {
            noticeText(message)
        }
        switch loginItem.status {
        case .needsApproval:
            HStack(spacing: 8) {
                noticeText("시스템 설정의 로그인 항목에서 허용해 주세요")
                Button("시스템 설정 열기") { loginItem.openSystemSettings() }
                    .buttonStyle(CheekyButtonStyle())
            }
        case .off, .on:
            EmptyView()
        }
    }

    private func noticeText(_ text: String) -> some View {
        Text(text)
            .font(CheekyFont.text(12, weight: .semibold))
            .foregroundStyle(CheekyPalette.cocoa)
            .fixedSize(horizontal: false, vertical: true)
    }
}
