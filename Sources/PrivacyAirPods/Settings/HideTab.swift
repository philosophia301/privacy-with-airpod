import SwiftUI

// 가리기 탭. 미리보기 방식, 모니터 미리보기, 고개 행, 네 가지 조절값을 그림.
// sample마다 바뀌는 값(readout)은 MonitorPreview와 GazeRow 안에서만 관찰함. 이 탭의 본체는 readout을 읽지 않음.

struct HideTab: View {
    @ObservedObject var model: AppModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 10) {
                    PreviewModePill(model: model)
                    Spacer(minLength: 0)
                    if model.displays.count > 1 {
                        DisplayMenu(model: model)
                    }
                }
                MonitorPreview(readout: model.readout)
                GazeRow(demo: model.demo, demoAngle: $model.demoAngle, readout: model.readout)
                TuningGrid(model: model)
                AwayRow(model: model)
            }
        }
    }
}

// 자리 이탈 가리기 스위치. 판정과 복귀 규칙은 AppModel이 소유하고 여기서는 값만 바꿈.
// 640x820 창에서 조절값 아래 남는 높이가 한 줄뿐이라 설명은 짧게 같은 줄에 두고 전체 문장은 툴팁으로 줌.
private struct AwayRow: View {
    @ObservedObject var model: AppModel
    private static let help = "일어선 뒤 3초가 지나거나 걸으면 화면 전체를 흐려요. 다시 앉으면 돌아와요"

    var body: some View {
        HStack(spacing: 10) {
            Text("자리를 뜨면 가리기")
                .font(CheekyFont.text(14, weight: .bold))
            Text("일어서고 3초 뒤, 걸으면 바로")
                .font(CheekyFont.text(12, weight: .semibold))
                .foregroundStyle(CheekyPalette.cocoa)
            Spacer(minLength: 0)
            Toggle("자리를 뜨면 가리기", isOn: $model.hideWhenAway)
                .toggleStyle(.switch)
                .labelsHidden()
                .tint(CheekyPalette.cocoa)
                .accessibilityHint(Text(Self.help))
        }
        .help(Text(Self.help))
    }
}

// AirPods 보기는 보정 뒤에만 켤 수 있음. 보정 전에는 실제 고개 값이 없어 미리보기가 의미를 잃음.
private struct PreviewModePill: View {
    @ObservedObject var model: AppModel

    var body: some View {
        HStack(spacing: 2) {
            CheekySegmentButton(title: "AirPods", selected: !model.demo, enabled: model.deskReference != nil) {
                model.demo = false
            }
            CheekySegmentButton(title: "직접 돌려보기", selected: model.demo) {
                model.demo = true
            }
        }
        .cheekySegmentGroup()
    }
}

// 화면이 두 대 이상일 때만 보임. 미리볼 화면 선택은 AppModel.selectedDisplay 하나에 씀.
private struct DisplayMenu: View {
    @ObservedObject var model: AppModel

    var body: some View {
        HStack(spacing: 6) {
            Text("미리볼 화면")
                .font(CheekyFont.text(12, weight: .semibold))
                .foregroundStyle(CheekyPalette.cocoa)
            Picker("미리볼 화면", selection: $model.selectedDisplay) {
                ForEach(model.displays) { Text($0.name).tag($0.id) }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .fixedSize()
        }
    }
}

// 모니터 틀 안에 예제 화면의 미리보기를 넣음. 프레임이 없으면 빈 화면만 보이고 나머지 구성은 그대로 둠.
// 틀은 예제 화면(800x420) 비율에 맞춰 빈 여백 없이 감쌈.
private struct MonitorPreview: View {
    @ObservedObject var readout: LiveReadout
    private static let screenHeight: CGFloat = 180

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                RoundedRectangle(cornerRadius: 9).fill(Color(cheekyHex: 0xFFFCF4))
                if let image = readout.previewImage {
                    Image(image, scale: 1, label: Text("앱이 만든 예제 화면의 블러 미리보기"))
                        .resizable()
                        .clipShape(RoundedRectangle(cornerRadius: 9))
                }
            }
            .frame(width: Self.screenHeight * 800 / 420, height: Self.screenHeight)
            .padding(6)
            .background(RoundedRectangle(cornerRadius: 14).fill(CheekyPalette.cocoa))
            .background(RoundedRectangle(cornerRadius: 14).fill(CheekyPalette.ink).offset(y: 3))
            RoundedRectangle(cornerRadius: 2)
                .fill(CheekyPalette.cocoa)
                .frame(width: 54, height: 9)
                .padding(.top, 3)
            RoundedRectangle(cornerRadius: 4)
                .fill(CheekyPalette.cocoa)
                .frame(width: 120, height: 7)
        }
        .frame(maxWidth: .infinity)
    }
}

// 고개 값 배지와 물결 슬라이더. 직접 돌려보기에서만 조작하며 AirPods 보기에서는 실제 각도를 보여 줌.
private struct GazeRow: View {
    let demo: Bool
    let demoAngle: Binding<Double>
    @ObservedObject var readout: LiveReadout

    var body: some View {
        let shown = demo ? demoAngle.wrappedValue : readout.angle
        HStack(spacing: 12) {
            HStack(spacing: 4) {
                Text("고개")
                    .font(CheekyFont.text(12, weight: .bold))
                Text(Self.angleText(shown))
                    .font(CheekyFont.display(14))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 3)
            .background(Capsule().fill(CheekyPalette.yellow))
            .overlay(Capsule().stroke(CheekyPalette.cocoa, lineWidth: 2))
            .fixedSize()
            FinSlider(value: demo ? demoAngle : .constant(readout.angle),
                      range: -90...90,
                      label: "고개 방향",
                      style: .wave,
                      valueText: Self.angleText)
                .disabled(!demo)
        }
    }

    static func angleText(_ value: Double) -> String {
        let rounded = Int(value.rounded())
        return rounded > 0 ? "+\(rounded)°" : "\(rounded)°"
    }
}

// 네 가지 조절값을 2열로 둠. 값 범위와 단위는 AppModel의 기존 정의를 그대로 씀.
private struct TuningGrid: View {
    @ObservedObject var model: AppModel

    var body: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 24), GridItem(.flexible())],
                  alignment: .leading, spacing: 10) {
            TuningSlider(title: "흐려지는 각도",
                         help: "책상 정면에서 이만큼 돌리면 흐려지기 시작합니다",
                         value: $model.startAngle, range: 0...45, step: 1,
                         format: { "\(Int($0.rounded()))°" })
            TuningSlider(title: "흐림 세기",
                         help: nil,
                         value: $model.maximumBlur, range: 15...80, step: 1,
                         format: { "\(Int($0.rounded()))" })
            TuningSlider(title: "경계 폭",
                         help: "낮추면 경계가 또렷하고, 높이면 넓고 부드럽게 흐려집니다",
                         value: $model.connectionWidth, range: 0...50, step: 1,
                         format: { "\(Int($0.rounded()))%" })
            TuningSlider(title: "따라오는 속도",
                         help: nil,
                         value: $model.responseTime, range: 0.03...0.5, step: 0.01,
                         format: { String(format: "%.2f", $0) }, unit: "초")
        }
    }
}

private struct TuningSlider: View {
    let title: String
    let help: String?
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    let format: (Double) -> String
    var unit = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                    .font(CheekyFont.text(14, weight: .semibold))
                    .help(Text(help ?? ""))
                Spacer(minLength: 8)
                CheekyValueBadge(number: format(value), unit: unit)
            }
            FinSlider(value: $value, range: range, step: step, label: title,
                      valueText: { format($0) + unit })
        }
    }
}
