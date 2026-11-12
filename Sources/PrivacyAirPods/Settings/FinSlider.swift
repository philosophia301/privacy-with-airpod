import SwiftUI

// 시스템 Slider 대신 쓰는 지느러미 슬라이더. 썸 그림은 fin-final.svg(38x30)를 38x32 상자 아래쪽에 둠.

enum FinSliderStyle {
    case fin
    case wave
}

struct FinSlider: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    var step: Double?
    let label: String
    var style: FinSliderStyle = .fin
    var valueText: (Double) -> String = { String(format: "%.0f", $0) }

    @Environment(\.isEnabled) private var isEnabled

    // 썸 중심이 트랙 중앙에 오도록 맞춘 높이. 물보라 중심이 이 y에 놓임.
    static let height: CGFloat = 32
    static let thumbWidth: CGFloat = 38
    static let trackCenterY: CGFloat = FinThumb.offsetY + 22

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            ZStack(alignment: .topLeading) {
                track(width: width)
                FinThumb()
                    .frame(width: Self.thumbWidth, height: Self.height)
                    .offset(x: thumbCenterX(width: width) - Self.thumbWidth / 2)
            }
            .frame(width: width, height: Self.height, alignment: .topLeading)
            .contentShape(Rectangle())
            .gesture(dragGesture(width: width))
        }
        .frame(height: Self.height)
        .focusable()
        .onKeyPress(.leftArrow) { nudge(-1) }
        .onKeyPress(.downArrow) { nudge(-1) }
        .onKeyPress(.rightArrow) { nudge(1) }
        .onKeyPress(.upArrow) { nudge(1) }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue(valueText(value))
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: nudge(1)
            case .decrement: nudge(-1)
            @unknown default: break
            }
        }
        .accessibilityRespondsToUserInteraction(isEnabled)
        .opacity(isEnabled ? 1 : 0.45)
        .allowsHitTesting(isEnabled)
    }

    @ViewBuilder
    private func track(width: CGFloat) -> some View {
        switch style {
        case .fin:
            FinTrack(fraction: fraction, thumbCenterX: thumbCenterX(width: width))
                .frame(width: width, height: 12)
                .offset(y: Self.trackCenterY - 6)
        case .wave:
            WaveTrack()
                .frame(width: width, height: 14)
                .offset(y: Self.trackCenterY - 7)
        }
    }

    private var span: Double { range.upperBound - range.lowerBound }

    private var fraction: Double {
        guard span > 0 else { return 0 }
        return min(max((value - range.lowerBound) / span, 0), 1)
    }

    private func thumbCenterX(width: CGFloat) -> CGFloat {
        let travel = max(width - Self.thumbWidth, 0)
        return Self.thumbWidth / 2 + travel * CGFloat(fraction)
    }

    private func dragGesture(width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { drag in
                guard isEnabled else { return }
                let travel = max(width - Self.thumbWidth, 1)
                let raw = (drag.location.x - Self.thumbWidth / 2) / travel
                value = snapped(range.lowerBound + Double(min(max(raw, 0), 1)) * span)
            }
    }

    @discardableResult
    private func nudge(_ direction: Int) -> KeyPress.Result {
        guard isEnabled else { return .ignored }
        value = snapped(value + Double(direction) * stepSize)
        return .handled
    }

    private var stepSize: Double {
        if let step, step > 0 { return step }
        return span / 100
    }

    private func snapped(_ raw: Double) -> Double {
        let clamped = min(max(raw, range.lowerBound), range.upperBound)
        guard let step, step > 0 else { return clamped }
        let steps = ((clamped - range.lowerBound) / step).rounded()
        return min(max(range.lowerBound + steps * step, range.lowerBound), range.upperBound)
    }
}

// 값까지 노랑, 나머지는 크림. 위쪽 안쪽 흰 하이라이트로 눌린 홈처럼 보이게 함.
private struct FinTrack: View {
    let fraction: Double
    let thumbCenterX: CGFloat

    var body: some View {
        ZStack(alignment: .topLeading) {
            Capsule().fill(CheekyPalette.cream)
            Rectangle()
                .fill(CheekyPalette.yellow)
                .frame(width: thumbCenterX)
                .frame(maxWidth: .infinity, alignment: .leading)
            Rectangle()
                .fill(Color.white.opacity(0.55))
                .frame(height: 2)
                .frame(maxHeight: .infinity, alignment: .top)
                .padding(.horizontal, 6)
                .offset(y: 1)
        }
        .clipShape(Capsule())
        .overlay(Capsule().strokeBorder(CheekyPalette.cocoa, lineWidth: 2))
    }
}

// 고개 방향처럼 값이 연속임을 드러내는 물결 트랙. 값 표시는 썸과 접근성 값이 맡음.
private struct WaveTrack: View {
    var body: some View {
        Canvas { context, size in
            let tile: CGFloat = 20
            let originY = (size.height - 12) / 2
            var wave = Path()
            var x: CGFloat = 0
            while x < size.width {
                wave.move(to: CGPoint(x: x, y: originY + 6))
                wave.addQuadCurve(to: CGPoint(x: x + 10, y: originY + 6),
                                  control: CGPoint(x: x + 5, y: originY + 1))
                wave.addQuadCurve(to: CGPoint(x: x + tile, y: originY + 6),
                                  control: CGPoint(x: x + 15, y: originY + 11))
                x += tile
            }
            context.stroke(wave, with: .color(CheekyPalette.tan),
                           style: StrokeStyle(lineWidth: 2.2, lineCap: .round))
        }
        .accessibilityHidden(true)
    }
}

// fin-final.svg의 다섯 경로와 두 원을 SwiftUI Path로 옮김. 좌표는 원본 38x30 viewBox 기준이며 호출부가 아래로 이동함.
struct FinThumb: View {
    // 상자 38x32의 아래쪽 30pt에 그림을 둠. 물보라 중심이 트랙 중앙에 옴.
    static let offsetY: CGFloat = 2

    var body: some View {
        Canvas { context, size in
            var ctx = context
            let scale = size.width / FinSlider.thumbWidth
            ctx.concatenate(CGAffineTransform(scaleX: scale, y: scale)
                .translatedBy(x: 0, y: Self.offsetY))

            let body = FinArt.body()
            ctx.fill(body, with: .color(CheekyPalette.yellow))
            ctx.stroke(body, with: .color(CheekyPalette.cocoa),
                       style: StrokeStyle(lineWidth: 2.2, lineJoin: .round))
            ctx.fill(FinArt.shade(), with: .color(CheekyPalette.yellowDeep))
            ctx.stroke(FinArt.highlight(), with: .color(.white),
                       style: StrokeStyle(lineWidth: 1.7, lineCap: .round))
            ctx.fill(FinArt.star(), with: .color(CheekyPalette.cocoa))

            let splash = FinArt.splash()
            ctx.fill(splash, with: .color(.white))
            ctx.stroke(splash, with: .color(CheekyPalette.cocoa),
                       style: StrokeStyle(lineWidth: 2, lineJoin: .round))
            for bubble in FinArt.bubbles() {
                ctx.fill(bubble, with: .color(.white))
                ctx.stroke(bubble, with: .color(CheekyPalette.cocoa), lineWidth: 1.2)
            }
        }
        .frame(width: FinSlider.thumbWidth, height: FinSlider.height)
        .accessibilityHidden(true)
    }
}

enum FinArt {
    static func body() -> Path {
        var path = Path()
        path.move(to: CGPoint(x: 6, y: 24))
        path.addCurve(to: CGPoint(x: 30.5, y: 3),
                      control1: CGPoint(x: 9.5, y: 15.5), control2: CGPoint(x: 17, y: 6.5))
        path.addCurve(to: CGPoint(x: 29, y: 24),
                      control1: CGPoint(x: 25.5, y: 9), control2: CGPoint(x: 24.8, y: 16.5))
        path.closeSubpath()
        return path
    }

    static func shade() -> Path {
        var path = Path()
        path.move(to: CGPoint(x: 28.6, y: 5.4))
        path.addCurve(to: CGPoint(x: 27.2, y: 23.4),
                      control1: CGPoint(x: 25, y: 10.5), control2: CGPoint(x: 24.2, y: 17))
        path.addLine(to: CGPoint(x: 24.6, y: 23.4))
        path.addCurve(to: CGPoint(x: 28.6, y: 5.4),
                      control1: CGPoint(x: 22.4, y: 17), control2: CGPoint(x: 23.4, y: 10.4))
        path.closeSubpath()
        return path
    }

    static func highlight() -> Path {
        var path = Path()
        path.move(to: CGPoint(x: 11, y: 19.5))
        path.addCurve(to: CGPoint(x: 23.6, y: 6.8),
                      control1: CGPoint(x: 13.8, y: 14), control2: CGPoint(x: 18.2, y: 9.6))
        return path
    }

    static func star() -> Path {
        let points: [CGPoint] = [
            CGPoint(x: 18.6, y: 12.6), CGPoint(x: 19.6, y: 14.6), CGPoint(x: 21.8, y: 14.9),
            CGPoint(x: 20.2, y: 16.4), CGPoint(x: 20.6, y: 18.6), CGPoint(x: 18.6, y: 17.6),
            CGPoint(x: 16.6, y: 18.6), CGPoint(x: 17.0, y: 16.4), CGPoint(x: 15.4, y: 14.9),
            CGPoint(x: 17.6, y: 14.6)
        ]
        var path = Path()
        path.move(to: points[0])
        for point in points.dropFirst() {
            path.addLine(to: point)
        }
        path.closeSubpath()
        return path
    }

    static func splash() -> Path {
        var path = Path()
        path.move(to: CGPoint(x: 3.2, y: 27.6))
        path.addCurve(to: CGPoint(x: 7.8, y: 22.8),
                      control1: CGPoint(x: 1.4, y: 24), control2: CGPoint(x: 4.6, y: 21.2))
        path.addCurve(to: CGPoint(x: 16.2, y: 22.2),
                      control1: CGPoint(x: 8.8, y: 19.2), control2: CGPoint(x: 14.6, y: 18.6))
        path.addCurve(to: CGPoint(x: 25, y: 23),
                      control1: CGPoint(x: 18, y: 19.2), control2: CGPoint(x: 23.8, y: 19.4))
        path.addCurve(to: CGPoint(x: 31, y: 27.6),
                      control1: CGPoint(x: 28, y: 21.2), control2: CGPoint(x: 32.4, y: 23))
        path.closeSubpath()
        return path
    }

    static func bubbles() -> [Path] {
        [
            Path(ellipseIn: CGRect(x: 34 - 1.7, y: 20.2 - 1.7, width: 3.4, height: 3.4)),
            Path(ellipseIn: CGRect(x: 35.4 - 1.1, y: 15.4 - 1.1, width: 2.2, height: 2.2))
        ]
    }
}
