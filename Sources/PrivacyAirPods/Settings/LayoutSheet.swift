import SwiftUI
import PrivacyCore

// 배치 수정 시트. 위에서 본 지도, 선택 화면 조절, 고개 확인 줄, 적용 줄을 600 폭 한 장에 모음.
// 편집 규칙은 LayoutEditor가, 흐림 표시 규칙은 RenderSettings가 맡음. 이 본체는 sample마다 바뀌는 readout을 읽지 않음.

struct LayoutSheet: View {
    @ObservedObject var model: AppModel
    let update: UpdateState
    @Environment(\.dismiss) private var dismiss
    @State private var editor: LayoutEditor
    @State private var armLength: Double
    @State private var avatar: HumanGuide
    @State private var showingArm = false
    @State private var manual: Bool
    @State private var manualYaw = 0.0
    @State private var error: String?

    init(model: AppModel, update: UpdateState) {
        self.model = model
        self.update = update
        _editor = State(initialValue: LayoutEditor(poses: model.layoutDraft))
        // 팔 길이와 모형은 마지막으로 적용한 값에서 시작함. 취소하면 model 값을 그대로 둠.
        _armLength = State(initialValue: model.armLengthCM)
        _avatar = State(initialValue: model.armGuide)
        // AirPods 고개 값은 보정 뒤에만 있으므로 보정 전에는 직접 값으로 시작함.
        _manual = State(initialValue: model.deskReference == nil)
    }

    private var labels: LayoutMapLabels { Self.labels(for: model.displays) }
    private var direct: Bool { manual || model.deskReference == nil }
    private var guarded: Bool { model.protected || model.startingProtection }

    var body: some View {
        VStack(spacing: 12) {
            header
            mapCard
            if let pose = editor.selectedPose {
                selectionPanel(pose)
            }
            GazeCheckRow(readout: model.readout, manual: $manual, manualYaw: $manualYaw,
                         canUseAirPods: model.deskReference != nil)
            footer
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 18)
        .frame(width: 600)
        .background(CheekyPalette.cream)
        .preferredColorScheme(.light)
        // 필수 업데이트가 확인되면 시트를 닫아 설정 창의 업데이트 안내로 돌아감.
        .onReceive(update.$requiredVersion) { if $0 != nil { dismiss() } }
    }

    // MARK: 머리줄과 지도

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("화면 배치")
                .font(CheekyFont.text(20, weight: .bold))
                .foregroundStyle(CheekyPalette.ink)
            Spacer(minLength: 8)
            Image(systemName: "arrow.up.and.down.and.arrow.left.and.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(CheekyPalette.cocoa)
                .accessibilityHidden(true)
            Text("끌어서 옮기고, 동그라미로 돌려요")
                .font(CheekyFont.text(12, weight: .semibold))
                .foregroundStyle(CheekyPalette.cocoa)
        }
    }

    // 지도는 2pt 여백만 두고 카드 안에 넣음. 팔 길이 칩은 지도 왼쪽 위 빈 곳에 겹쳐 둠.
    private var mapCard: some View {
        TopLayoutMap(editor: $editor, readout: model.readout, manualYaw: direct ? manualYaw : nil,
                     start: model.startAngle, transitionFraction: model.connectionWidth / 100,
                     armLength: armLength, labels: labels)
            .padding(2)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .cheekyCard()
            .overlay(alignment: .topLeading) { armChip.padding(10) }
            .padding(.bottom, 3)
    }

    private var armChip: some View {
        Button { showingArm = true } label: {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text("팔 길이")
                    .font(CheekyFont.text(12, weight: .bold))
                Text("\(Int(armLength.rounded()))")
                    .font(CheekyFont.display(13))
                Text("cm")
                    .font(CheekyFont.text(12, weight: .bold))
            }
            .foregroundStyle(CheekyPalette.ink)
            .padding(.horizontal, 10)
            .frame(height: 26)
            .background(Capsule().fill(CheekyPalette.white))
            .overlay(Capsule().stroke(CheekyPalette.cocoa, lineWidth: 2))
        }
        .buttonStyle(.plain)
        .popover(isPresented: $showingArm, arrowEdge: .bottom) { armPopover }
    }

    // 사람 모형을 고르면 그 평균 팔 길이로 맞추고, 아래 슬라이더로 직접 조절함.
    private var armPopover: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 2) {
                ForEach(HumanGuide.allCases, id: \.self) { guide in
                    CheekySegmentButton(title: guide.rawValue, selected: avatar == guide) {
                        avatar = guide
                        armLength = guide.armLengthCM
                    }
                }
            }
            .cheekySegmentGroup()
            FinSlider(value: $armLength, range: 40...85, step: 1, label: "팔 길이",
                      valueText: { "\(Int($0.rounded()))cm" })
        }
        .padding(16)
        .frame(width: 300)
    }

    // MARK: 선택 화면 패널

    private func selectionPanel(_ pose: DisplayPose) -> some View {
        HStack(alignment: .top, spacing: 14) {
            SideHeightView(editor: $editor)
            VStack(alignment: .leading, spacing: 6) {
                selectionHeader(pose)
                badgeRow(pose)
                heightSlider(pose)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cheekyCard()
        .padding(.bottom, 3)
    }

    private func selectionHeader(_ pose: DisplayPose) -> some View {
        HStack(spacing: 6) {
            Text("\(labels[editor.selected]?.number ?? 0)")
                .font(CheekyFont.display(12))
                .foregroundStyle(CheekyPalette.ink)
                .frame(width: 24, height: 24)
                .background(Circle().fill(CheekyPalette.yellow))
                .overlay(Circle().stroke(CheekyPalette.cocoa, lineWidth: 2))
            displayMenu
            Spacer(minLength: 0)
            Button("나를 보게") { editor.faceUser() }
                .buttonStyle(CheekyButtonStyle())
            Button { editor.flipOrientation() } label: {
                Image(systemName: "rectangle.portrait.rotate")
            }
            .buttonStyle(CheekyButtonStyle())
            .accessibilityLabel(pose.width >= pose.height ? "세로로 돌리기" : "가로로 돌리기")
        }
    }

    private var displayMenu: some View {
        Menu {
            ForEach(Array(model.displays.enumerated()), id: \.element.id) { index, display in
                Button("화면 \(index + 1) \(Self.plainName(display.name))") { editor.selected = display.id }
            }
        } label: {
            // AppKit 메뉴 단추는 label의 그림을 글자 앞에 놓으므로 글자만 주고 펼침 표시는 시스템 것을 씀.
            Text(selectedName)
                .font(CheekyFont.text(15, weight: .bold))
                .foregroundStyle(CheekyPalette.ink)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    private var selectedName: String {
        labels[editor.selected]?.name ?? "화면"
    }

    private func badgeRow(_ pose: DisplayPose) -> some View {
        HStack(spacing: 6) {
            CheekyValueBadge(prefix: "거리", number: "\(LayoutEditor.distance(of: pose))", unit: "cm",
                             background: CheekyPalette.white)
            CheekyValueBadge(prefix: "회전", number: degreeText(pose.yawDegrees), unit: "°",
                             background: CheekyPalette.white)
            heightBadge(pose.y)
        }
    }

    private func heightBadge(_ y: Double) -> some View {
        let rounded = Int(y.rounded())
        if rounded == 0 {
            return CheekyValueBadge(prefix: "높이", unit: "눈높이")
        }
        return CheekyValueBadge(prefix: rounded > 0 ? "높이 위" : "높이 아래", number: "\(abs(rounded))", unit: "cm")
    }

    private func heightSlider(_ pose: DisplayPose) -> some View {
        FinSlider(value: Binding(get: { pose.y }, set: { editor.setHeight($0) }),
                  range: -60...60, step: 1, label: "높이", valueText: heightText)
    }

    // MARK: 적용 줄

    private var footer: some View {
        HStack(spacing: 10) {
            Text(message ?? "")
                .font(CheekyFont.text(12, weight: .semibold))
                .foregroundStyle(CheekyPalette.cocoa)
            Spacer(minLength: 0)
            Button("취소") { dismiss() }
                .buttonStyle(CheekyButtonStyle(size: .medium))
                .keyboardShortcut(.cancelAction)
            Button("이 배치 적용") { apply() }
                .buttonStyle(CheekyButtonStyle(variant: .cocoa, size: .medium))
                .keyboardShortcut(.defaultAction)
                .disabled(!editor.isValid || guarded)
        }
    }

    private var message: String? {
        if let error { return error }
        return editor.isValid ? nil : "화면이 눈앞 1cm보다 멀리 있어야 해요"
    }

    private func apply() {
        if model.applyLayout(editor.poses, armLengthCM: armLength, armGuide: avatar) {
            dismiss()
        } else {
            error = "화면 구성이 바뀌었어요. 다시 열어 주세요"
        }
    }

    // 화면 번호와 이름을 DisplayPose.id 키로 묶음. 이름은 DisplayLayout이 붙인 위치 표기 뒤쪽만 씀.
    static func labels(for displays: [DisplayCalibration]) -> LayoutMapLabels {
        displays.enumerated().reduce(into: LayoutMapLabels()) { result, item in
            result[item.element.id] = (number: item.offset + 1, name: plainName(item.element.name))
        }
    }

    static func plainName(_ name: String) -> String {
        name.components(separatedBy: " · ").last ?? name
    }
}

// 고개 확인 줄. AirPods 값과 직접 값 중 고르고, 값 배지와 물결 슬라이더를 보여 줌.
// sample마다 바뀌는 readout은 이 작은 뷰만 관찰함.
private struct GazeCheckRow: View {
    @ObservedObject var readout: LiveReadout
    @Binding var manual: Bool
    @Binding var manualYaw: Double
    let canUseAirPods: Bool

    var body: some View {
        let direct = manual || !canUseAirPods
        let shown = direct ? manualYaw : readout.angle
        HStack(spacing: 12) {
            HStack(spacing: 2) {
                CheekySegmentButton(title: "AirPods", selected: !direct, enabled: canUseAirPods) {
                    manual = false
                }
                CheekySegmentButton(title: "직접", selected: direct) {
                    manual = true
                }
            }
            .cheekySegmentGroup()
            FinSlider(value: direct ? $manualYaw : .constant(readout.angle), range: -90...90,
                      label: "고개 방향", style: .wave, valueText: { degreeText($0) + "°" })
                .disabled(!direct)
            CheekyValueBadge(prefix: "고개", number: degreeText(shown), unit: "°")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: 16).fill(CheekyPalette.white))
        .overlay(RoundedRectangle(cornerRadius: 16)
            .strokeBorder(CheekyPalette.dashedDivider, style: StrokeStyle(lineWidth: 2, dash: [5, 4])))
    }
}

// 각도 표기의 부호. 양수는 +를 붙이고 0은 부호 없이 씀.
private func degreeText(_ value: Double) -> String {
    let rounded = Int(value.rounded())
    return rounded > 0 ? "+\(rounded)" : "\(rounded)"
}

// 높이 0은 눈높이로 읽히게 하고, 나머지는 위와 아래 cm로 나눔.
private func heightText(_ value: Double) -> String {
    let rounded = Int(value.rounded())
    if rounded == 0 { return "눈높이" }
    return rounded > 0 ? "위 \(rounded)cm" : "아래 \(-rounded)cm"
}
