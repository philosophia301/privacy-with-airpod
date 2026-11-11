import SwiftUI
import PrivacyCore

struct SpatialSetupView: View {
    @ObservedObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var poses: [DisplayPose]
    @State private var selected: UInt32
    @State private var manual = true
    @State private var yaw = 0.0
    @State private var armLength = HumanGuide.female.armLengthCM
    @State private var avatar = HumanGuide.female
    @State private var camera = 0
    @State private var error: String?

    init(model: AppModel) {
        self.model = model
        let initial = model.layoutDraft
        _poses = State(initialValue: initial)
        _selected = State(initialValue: initial.first?.id ?? 0)
    }

    private var valid: Bool { !poses.isEmpty && poses.allSatisfy { $0.compiled() != nil } }

    var body: some View {
        VStack(spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("나의 책상 배치").font(.title2.bold())
                    Text("손끝을 거리 가이드로 삼아 화면을 배치해 보세요.").foregroundStyle(.secondary)
                }
                Spacer()
                Picker("보기", selection: $camera) {
                    Text("입체").tag(0); Text("위에서").tag(1); Text("정면").tag(2)
                }.pickerStyle(.segmented).frame(width: 230)
            }
            GazeReader(readout: model.readout, manualYaw: manual ? yaw : nil) { gaze in
                SpatialScene(poses: poses, selected: $selected, gaze: gaze, start: model.startAngle,
                             transitionFraction: model.connectionWidth / 100, radius: model.maximumBlur,
                             armLength: armLength, avatar: avatar, camera: camera)
                    .frame(height: 300).clipShape(RoundedRectangle(cornerRadius: 16))
                    .accessibilityLabel("가상 책상과 모니터 배치. 모니터를 클릭하면 해당 모니터가 선택됩니다. 보기 버튼으로 시점을 바꿉니다.")
            }
            HStack {
                Picker("사람 모형", selection: $avatar) {
                    ForEach(HumanGuide.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }.frame(width: 175)
                    .onChange(of: avatar) { _, preset in armLength = preset.armLengthCM }
                Text("팔 길이 · 어깨~손목")
                Slider(value: $armLength, in: 40...85)
                Text(String(format: "%.1f cm", armLength)).monospacedDigit()
                Text("한국 성인 평균 초기값 · 직접 조절 가능").font(.caption).foregroundStyle(.secondary)
            }
            HStack {
                Picker("모니터", selection: $selected) {
                    ForEach(model.displays) { Text($0.name).tag($0.id) }
                }.frame(width: 240)
                Text("높이는 눈높이 기준").font(.caption).foregroundStyle(.secondary)
            }
            if let index = poses.firstIndex(where: { $0.id == selected }) {
                HStack {
                    Button(poses[index].height > poses[index].width ? "가로로 전환" : "세로로 전환") {
                        let width = poses[index].width
                        poses[index].width = poses[index].height
                        poses[index].height = width
                    }
                    Text("가상 배치만 전환됩니다.").font(.caption).foregroundStyle(.secondary)
                }
                HStack(spacing: 20) {
                    adjustment("좌우", value: $poses[index].x, range: -150...150)
                    adjustment("높이", value: $poses[index].y, range: -60...60)
                }
                HStack(spacing: 20) {
                    adjustment("거리", value: $poses[index].z, range: 25...150)
                    adjustment("회전", value: $poses[index].yawDegrees, range: -65...65)
                }
            }
            HStack {
                Toggle("수동 고개 회전", isOn: $manual)
                Slider(value: $yaw, in: -100...100).disabled(!manual).accessibilityLabel("가상 고개 회전")
                GazeReader(readout: model.readout, manualYaw: manual ? yaw : nil) { gaze in
                    Text(String(format: "%+.0f°", gaze)).monospacedDigit()
                }
                if !manual && !model.fresh { Text("AirPods 입력 필요").foregroundStyle(.orange) }
            }
            HStack {
                Text(error ?? (valid ? "가상 화면과 실제 보호는 같은 각도표를 사용합니다. 보기 버튼으로 관찰 시점을 바꿉니다." : "화면 크기는 양수이며 전체 화면이 눈앞 1cm보다 멀리 있어야 합니다."))
                    .font(.caption).foregroundStyle(valid ? Color.secondary : Color.orange)
                Spacer()
                Button("취소") { dismiss() }
                Button("이 배치 적용") {
                    if model.applyLayout(poses) { dismiss() }
                    else { error = "화면 구성이 바뀌었거나 배치가 유효하지 않습니다. 다시 열어 주세요." }
                }.buttonStyle(.borderedProminent).disabled(!valid || model.protected || model.startingProtection)
            }
        }.padding(24).frame(width: 930)
    }

    private func adjustment(_ title: String, value: Binding<Double>, range: ClosedRange<Double>) -> some View {
        HStack {
            Text(title).font(.caption).frame(width: 30)
            Slider(value: value, in: range, step: 1).accessibilityLabel("선택한 모니터 \(title)")
        }
    }

}

/// 수동 회전이 아니면 AirPods 각도를 sample마다 반영함. 시트 전체 대신 이 부분만 LiveReadout을 관찰함.
private struct GazeReader<Content: View>: View {
    @ObservedObject var readout: LiveReadout
    let manualYaw: Double?
    @ViewBuilder let content: (Double) -> Content

    var body: some View { content(manualYaw ?? readout.angle) }
}
