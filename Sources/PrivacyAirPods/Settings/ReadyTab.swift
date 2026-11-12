import SwiftUI

// 준비 탭. 준비 항목을 스탬프 타일로 그리고 'AirPods를 벗으면' 선택을 둠.
// 항목의 상태와 문구는 Readiness가 소유함. 여기서는 표시와 동작 연결만 함.

struct ReadyTab: View {
    @ObservedObject var model: AppModel
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
            LossChoice(model: model)
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

// 'AirPods를 벗으면' 선택. 값은 AppModel.retainBlurOnInputLoss 하나이며 여기서 정책을 바꾸지 않음.
private struct LossChoice: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("AirPods를 벗으면")
                .font(CheekyFont.text(14, weight: .bold))
            HStack(spacing: 12) {
                LossOption(title: "흐림 풀기", keeps: false, selected: !model.retainBlurOnInputLoss) {
                    model.retainBlurOnInputLoss = false
                }
                LossOption(title: "계속 가리기", keeps: true, selected: model.retainBlurOnInputLoss) {
                    model.retainBlurOnInputLoss = true
                }
            }
        }
    }
}

private struct LossOption: View {
    let title: String
    let keeps: Bool
    let selected: Bool
    let action: () -> Void

    private let shape = RoundedRectangle(cornerRadius: 16)

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                LossIcon(keeps: keeps)
                Text(title)
                    .font(CheekyFont.text(14, weight: .semibold))
                    .foregroundStyle(CheekyPalette.ink)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity, minHeight: 76)
            .background(shape.fill(selected ? CheekyPalette.yellow : CheekyPalette.white))
            .overlay(shape.stroke(CheekyPalette.cocoa, lineWidth: 2))
            .background {
                if selected {
                    shape.fill(CheekyPalette.cocoa).offset(y: 3)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

// 모니터 그림. keeps가 true면 가린 자리를 뜻하는 흐린 띠, false면 풀린 화면의 글줄을 그림.
private struct LossIcon: View {
    let keeps: Bool

    var body: some View {
        Canvas { context, size in
            var scaled = context
            scaled.concatenate(CGAffineTransform(scaleX: size.width / 58, y: size.height / 40))
            let frame = Path(roundedRect: CGRect(x: 2, y: 2, width: 54, height: 30), cornerRadius: 5)
            scaled.fill(frame, with: .color(CheekyPalette.white))
            scaled.stroke(frame, with: .color(CheekyPalette.cocoa), lineWidth: 2.4)
            let stand = StrokeStyle(lineWidth: 2.4, lineCap: .round)
            var standPath = Path()
            standPath.move(to: CGPoint(x: 23, y: 33))
            standPath.addLine(to: CGPoint(x: 23, y: 37))
            standPath.move(to: CGPoint(x: 17, y: 38))
            standPath.addLine(to: CGPoint(x: 41, y: 38))
            scaled.stroke(standPath, with: .color(CheekyPalette.cocoa), style: stand)
            if keeps {
                let blur = Path(roundedRect: CGRect(x: 8, y: 8, width: 38, height: 17), cornerRadius: 8.5)
                scaled.fill(blur, with: .color(CheekyPalette.tan.opacity(0.5)))
            } else {
                var lines = Path()
                lines.move(to: CGPoint(x: 9, y: 11))
                lines.addLine(to: CGPoint(x: 31, y: 11))
                lines.move(to: CGPoint(x: 9, y: 17))
                lines.addLine(to: CGPoint(x: 43, y: 17))
                lines.move(to: CGPoint(x: 9, y: 23))
                lines.addLine(to: CGPoint(x: 25, y: 23))
                scaled.stroke(lines, with: .color(CheekyPalette.cocoa), style: stand)
            }
        }
        .frame(width: 52, height: 36)
        .accessibilityHidden(true)
    }
}
