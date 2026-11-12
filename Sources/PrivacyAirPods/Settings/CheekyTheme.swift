import AppKit
import CoreText
import SwiftUI

// 설정 창 공통 색·글꼴·카드·버튼·상태 배지. 화면 조립과 상태 규칙은 이 파일이 소유하지 않음.

enum CheekyPalette {
    static let cream = Color(cheekyHex: 0xFFF5E6)
    static let yellow = Color(cheekyHex: 0xFFE632)
    static let yellowDeep = Color(cheekyHex: 0xFFCF32)
    static let cocoa = Color(cheekyHex: 0x8C6239)
    static let tan = Color(cheekyHex: 0xC69C6D)
    static let brown = Color(cheekyHex: 0xA67C52)
    static let ink = Color(cheekyHex: 0x5A3A1E)
    static let tabOff = Color(cheekyHex: 0xF3E3C6)
    static let dashedDivider = Color(cheekyHex: 0xEADBC4)
    static let white = Color.white
}

extension Color {
    init(cheekyHex value: UInt32) {
        self.init(
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255
        )
    }
}

// 한글과 일반 글자는 시스템 글꼴의 세 굵기만 씀. heavy와 black은 디자인 규칙상 금지.
enum CheekyWeight {
    case medium
    case semibold
    case bold

    var fontWeight: Font.Weight {
        switch self {
        case .medium: .medium
        case .semibold: .semibold
        case .bold: .bold
        }
    }
}

enum CheekyFont {
    private static let bagelName = "BagelFatOne-Regular"

    // 프로세스 안에서 한 번만 등록함. 등록 뒤 이름 조회가 실패하면 번들 누락으로 보고 대체 글꼴을 씀.
    private static let bagelAvailable: Bool = {
        guard let url = Bundle.main.resourceURL?
            .appendingPathComponent("Fonts", isDirectory: true)
            .appendingPathComponent("BagelFatOne-Regular.ttf") else { return false }
        var error: Unmanaged<CFError>?
        CTFontManagerRegisterFontsForURL(url as CFURL, .process, &error)
        return NSFont(name: bagelName, size: 12) != nil
    }()

    static func text(_ size: CGFloat, weight: CheekyWeight) -> Font {
        .system(size: size, weight: weight.fontWeight)
    }

    // 숫자와 영문 장식 전용. 한글 단위에는 쓰지 않음.
    static func display(_ size: CGFloat) -> Font {
        if bagelAvailable {
            return .custom(bagelName, size: size)
        }
        return .system(size: size, weight: .bold, design: .rounded)
    }
}

// 카드 그림자는 레이아웃 밖으로 3pt 내려감. 호출부가 아래 여백을 3pt 이상 둠.
struct CheekyCardModifier: ViewModifier {
    let background: Color
    let radius: CGFloat = 18

    func body(content: Content) -> some View {
        content
            .background(RoundedRectangle(cornerRadius: radius).fill(background))
            .overlay(RoundedRectangle(cornerRadius: radius).stroke(CheekyPalette.cocoa, lineWidth: 2))
            .background(
                RoundedRectangle(cornerRadius: radius)
                    .fill(CheekyPalette.cocoa)
                    .offset(y: 3)
            )
    }
}

extension View {
    func cheekyCard(background: Color = CheekyPalette.white) -> some View {
        modifier(CheekyCardModifier(background: background))
    }
}

enum CheekySize {
    case regular
    case large

    var height: CGFloat { self == .large ? 46 : 30 }
    var padding: CGFloat { self == .large ? 22 : 14 }
    var fontSize: CGFloat { self == .large ? 15 : 13 }
}

enum CheekyButtonVariant {
    case plain
    case yellow
    case cocoa
}

struct CheekyButtonStyle: ButtonStyle {
    var variant: CheekyButtonVariant = .plain
    var size: CheekySize = .regular

    func makeBody(configuration: Configuration) -> some View {
        CheekyButtonBody(configuration: configuration, variant: variant, size: size)
    }
}

// Environment의 isEnabled를 읽으려고 View로 분리함. ButtonStyle 본문에서는 직접 읽을 수 없음.
private struct CheekyButtonBody: View {
    let configuration: ButtonStyleConfiguration
    let variant: CheekyButtonVariant
    let size: CheekySize
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        let pressed = configuration.isPressed && isEnabled
        configuration.label
            .font(CheekyFont.text(size.fontSize, weight: .semibold))
            .foregroundStyle(textColor)
            .frame(height: size.height)
            .padding(.horizontal, size.padding)
            .background(Capsule().fill(fillColor))
            .overlay(outline)
            .background(shadow(pressed: pressed))
            .offset(y: pressed ? 2 : 0)
            .fixedSize()
            .contentShape(Capsule())
    }

    private var isDisabledLook: Bool { !isEnabled }

    private var textColor: Color {
        if isDisabledLook { return CheekyPalette.brown }
        return variant == .cocoa ? CheekyPalette.cream : CheekyPalette.ink
    }

    private var fillColor: Color {
        if isDisabledLook { return CheekyPalette.cream }
        switch variant {
        case .plain: return CheekyPalette.white
        case .yellow: return CheekyPalette.yellow
        case .cocoa: return CheekyPalette.cocoa
        }
    }

    @ViewBuilder
    private var outline: some View {
        if isDisabledLook {
            Capsule().strokeBorder(CheekyPalette.cocoa, style: StrokeStyle(lineWidth: 2, dash: [4, 3]))
        } else {
            Capsule().strokeBorder(CheekyPalette.cocoa, lineWidth: 2)
        }
    }

    // 눌린 동안 그림자를 빼고 본문을 2pt 내려 물리 버튼처럼 보이게 함.
    @ViewBuilder
    private func shadow(pressed: Bool) -> some View {
        if isDisabledLook || pressed {
            EmptyView()
        } else {
            Capsule()
                .fill(variant == .cocoa ? CheekyPalette.ink : CheekyPalette.cocoa)
                .offset(y: variant == .cocoa ? 3 : 2)
        }
    }
}

// 상태 배지는 시안의 26pt viewBox를 그대로 쓰고 size에 맞춰 축소함.
enum CheekyBadgeGeometry {
    static let viewBox: CGFloat = 26

    static func scaledContext(_ context: GraphicsContext, size: CGSize) -> GraphicsContext {
        var scaled = context
        scaled.concatenate(CGAffineTransform(scaleX: size.width / viewBox, y: size.height / viewBox))
        return scaled
    }
}

struct DoneBadge: View {
    var size: CGFloat = 30

    var body: some View {
        Canvas { context, canvasSize in
            let ctx = CheekyBadgeGeometry.scaledContext(context, size: canvasSize)
            let circle = Path(ellipseIn: CGRect(x: 2, y: 2, width: 22, height: 22))
            ctx.fill(circle, with: .color(CheekyPalette.yellow))
            ctx.stroke(circle, with: .color(CheekyPalette.cocoa), lineWidth: 2)
            var check = Path()
            check.move(to: CGPoint(x: 8, y: 13.4))
            check.addLine(to: CGPoint(x: 11.4, y: 16.8))
            check.addLine(to: CGPoint(x: 18.2, y: 9.6))
            ctx.stroke(check, with: .color(CheekyPalette.ink),
                       style: StrokeStyle(lineWidth: 2.6, lineCap: .round, lineJoin: .round))
        }
        .frame(width: size, height: size)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("완료")
    }
}

struct TodoBadge: View {
    var size: CGFloat = 30

    var body: some View {
        Canvas { context, canvasSize in
            let ctx = CheekyBadgeGeometry.scaledContext(context, size: canvasSize)
            var triangle = Path()
            triangle.move(to: CGPoint(x: 13, y: 2.5))
            triangle.addLine(to: CGPoint(x: 24.5, y: 22.5))
            triangle.addLine(to: CGPoint(x: 1.5, y: 22.5))
            triangle.closeSubpath()
            ctx.fill(triangle, with: .color(CheekyPalette.cocoa))
            ctx.stroke(triangle, with: .color(CheekyPalette.cocoa),
                       style: StrokeStyle(lineWidth: 2, lineJoin: .round))
            var bar = Path()
            bar.move(to: CGPoint(x: 13, y: 9))
            bar.addLine(to: CGPoint(x: 13, y: 15.5))
            ctx.stroke(bar, with: .color(CheekyPalette.cream),
                       style: StrokeStyle(lineWidth: 2.6, lineCap: .round))
            ctx.fill(Path(ellipseIn: CGRect(x: 11.5, y: 17.5, width: 3, height: 3)),
                     with: .color(CheekyPalette.cream))
        }
        .frame(width: size, height: size)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("할 일")
    }
}

struct WaitBadge: View {
    var size: CGFloat = 30

    var body: some View {
        Canvas { context, canvasSize in
            let ctx = CheekyBadgeGeometry.scaledContext(context, size: canvasSize)
            let circle = Path(ellipseIn: CGRect(x: 2, y: 2, width: 22, height: 22))
            ctx.fill(circle, with: .color(CheekyPalette.cream))
            ctx.stroke(circle, with: .color(CheekyPalette.cocoa),
                       style: StrokeStyle(lineWidth: 2, dash: [3.2, 3]))
            for x in [8.5, 13.0, 17.5] as [CGFloat] {
                ctx.fill(Path(ellipseIn: CGRect(x: x - 1.5, y: 11.5, width: 3, height: 3)),
                         with: .color(CheekyPalette.cocoa))
            }
        }
        .frame(width: size, height: size)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("기다림")
    }
}

// 노랑과 cocoa 6px 사선 줄무늬. 시안의 -45deg 그라데이션을 perpendicular 6px 띠로 옮김.
struct TapeStripe: View {
    var height: CGFloat = 10

    var body: some View {
        Canvas { context, size in
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(CheekyPalette.yellow))
            let period: CGFloat = 12 * 2.0.squareRoot()
            let bandWidth: CGFloat = 6
            // 선 x+y=c의 stroke 폭은 수직 거리이므로 band 폭 6px을 그대로 씀.
            var c: CGFloat = 9 * 2.0.squareRoot() - period * 4
            let limit = size.width + size.height + period * 4
            while c < limit {
                var line = Path()
                // 두 끝점 모두 x+y=c를 만족하도록 맞춤. 바깥 연장분은 Canvas 경계가 잘라냄.
                line.move(to: CGPoint(x: c + 20, y: -20))
                line.addLine(to: CGPoint(x: c - size.height - 20, y: size.height + 20))
                context.stroke(line, with: .color(CheekyPalette.cocoa), lineWidth: bandWidth)
                c += period
            }
        }
        .frame(height: height)
        .clipped()
        .accessibilityHidden(true)
    }
}

// 노랑과 흰 18px 체커. 9px 칸 두 개가 한 타일이며 노랑은 칸 번호 합이 홀수인 칸에 놓임.
struct CheckerBand: View {
    var height: CGFloat = 18

    var body: some View {
        Canvas { context, size in
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(CheekyPalette.white))
            let cell: CGFloat = 9
            let columns = Int((size.width / cell).rounded(.up))
            let rows = Int((size.height / cell).rounded(.up))
            for row in 0..<rows {
                for column in 0..<columns where (row + column) % 2 == 1 {
                    let rect = CGRect(x: CGFloat(column) * cell, y: CGFloat(row) * cell, width: cell, height: cell)
                    context.fill(Path(rect), with: .color(CheekyPalette.yellow))
                }
            }
        }
        .frame(height: height)
        .clipped()
        .accessibilityHidden(true)
    }
}
