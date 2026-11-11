import SwiftUI
import PrivacyCore

struct ExperimentView: View {
    @ObservedObject var model: AppModel
    @State private var showingLayout = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                HStack {
                    Button("AirPods 입력 시작") { model.startMotion() }
                    Button("입력 중지") { model.stopMotion() }
                    Spacer()
                    Text(model.motionStatus).font(.caption).foregroundStyle(model.fresh ? .green : .secondary)
                }
                calibration
                panorama
                preview
                protection
                movement
            }
            .padding(28)
        }
        .frame(minWidth: 780, minHeight: 620)
        .sheet(isPresented: $showingLayout) { SpatialSetupView(model: model) }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("고개를 돌리면, 부드럽게 가리기").font(.title2.bold())
            Text("먼저 예제로 효과를 확인하고, 책상 정면을 한 번 맞추고 화면 배치를 설정해 주세요.")
                .foregroundStyle(.secondary)
        }
    }

    private var calibration: some View {
        GroupBox("1 · 책상 정면과 블러 시작 각도") {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Button(model.deskReference == nil ? "책상 정면 맞추기" : "책상 정면 다시 맞추기") { model.calibrateDesk() }
                        .disabled(!model.fresh || model.protected || model.startingProtection)
                    Text(model.deskReference == nil ? "보정 전" : "정면 보정 완료")
                    Spacer()
                    Text("블러 시작")
                    Slider(value: $model.startAngle, in: 0...45, step: 1)
                        .accessibilityLabel("블러 시작 각도")
                    Text("\(Int(model.startAngle))°부터").monospacedDigit()
                }
                Text("평소 책상 정면을 바라보고 한 번 눌러 주세요. 화면별 정면 보정은 필요 없습니다. 입력이 끊기면 다시 보정하며 설정은 이번 실행에만 유지됩니다.")
                    .font(.caption).foregroundStyle(.secondary)
            }.padding(8)
        }
    }

    private var panorama: some View {
        GroupBox("책상 배치 · 3D 설정") {
            VStack(alignment: .leading, spacing: 10) {
                Text("감지한 화면 \(model.displays.count)대 · 내장 화면 \(model.displays.contains(where: \.builtin) ? "활성" : "비활성")")
                ForEach(model.displays) { display in
                    Text(String(format: "%@ · 시스템 크기 %.1f × %.1f cm", display.name, display.widthCM, display.heightCM))
                        .font(.caption).foregroundStyle(.secondary)
                }
                HStack {
                    Button(model.appliedPoses.isEmpty ? "3D로 배치 맞추기" : "3D 배치 수정") { showingLayout = true }
                        .disabled(model.protected || model.startingProtection)
                    Text(model.appliedPoses.isEmpty ? "배치 적용 전" : "배치 적용 완료 · 실제 보호에는 각도표만 사용")
                        .font(.caption)
                }
                Text("감지한 화면 크기를 사용합니다. 3D 설정에서 위치와 가로·세로 방향을 맞춰 주세요. 화면 구성 변경 시 다시 적용해 주세요.")
                    .font(.caption).foregroundStyle(.secondary)
            }.frame(maxWidth: .infinity, alignment: .leading).padding(8)
        }
    }

    private var preview: some View {
        GroupBox("2 · 블러 미리보기") {
            VStack(spacing: 12) {
                HStack {
                    Toggle("수동 각도 미리보기", isOn: $model.demo)
                    Spacer()
                    Picker("미리볼 화면", selection: $model.selectedDisplay) {
                        ForEach(model.displays) { Text($0.name).tag($0.id) }
                    }.frame(maxWidth: 240)
                    Text(String(format: "%+.1f°", model.demo ? model.demoAngle : model.currentAngle)).monospacedDigit()
                }
                if model.demo {
                    HStack {
                        Text("왼쪽")
                        Slider(value: $model.demoAngle, in: -90...90)
                        Text("오른쪽")
                    }
                } else {
                    Toggle("좌우 방향 반전 · 실물 확인용", isOn: Binding(get: { model.direction > 0 }, set: { model.direction = $0 ? 1 : -1 }))
                        .disabled(model.protected)
                }
                if let image = model.previewImage {
                    Image(decorative: image, scale: 1)
                        .resizable().aspectRatio(800.0 / 420, contentMode: .fit)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .accessibilityLabel("앱이 만든 예제 화면의 블러 미리보기")
                }
                HStack {
                    Text("효과 농도")
                    Slider(value: $model.maximumBlur, in: 15...80)
                    Text("전환")
                    Slider(value: $model.responseTime, in: 0.03...0.5)
                    Text(String(format: "%.2f초", model.responseTime)).monospacedDigit()
                }
            }.padding(8)
        }
    }

    private var protection: some View {
        GroupBox("3 · 실제 화면에서 확인") {
            VStack(alignment: .leading, spacing: 10) {
                Text(model.captureStatus).font(.headline)
                Text("실시간 가변 블러 사용 중. 화면 캡처·저장·외부 전송 없음. 예제와 실제 화면의 흐림 정도는 다를 수 있음.")
                    .font(.caption).foregroundStyle(.secondary)
                HStack {
                    Button(model.protected || model.startingProtection ? "보호 끄기" : "실제 화면 회전 블러 켜기") { model.toggleProtection() }
                        .disabled(!model.protected && !model.startingProtection && !model.canProtect)
                    Text("수동 미리보기 각도는 실제 화면에 적용되지 않음.").font(.caption).foregroundStyle(.secondary)
                }
                HStack {
                    Text("파노라마 전환 폭")
                    Slider(value: $model.connectionWidth, in: 0...50, step: 1)
                        .accessibilityLabel("파노라마 전환 폭")
                        .accessibilityValue("\(Int(model.connectionWidth))퍼센트")
                    Text("\(Int(model.connectionWidth))%").monospacedDigit().frame(width: 40)
                    Button("25%로 초기화") { model.connectionWidth = 25 }
                }
                Text("파노라마 전체 폭에 대한 비율입니다. 0%는 뚜렷한 경계, 높일수록 선명함에서 블러로 넓고 부드럽게 바뀝니다. 실제 보호 중 즉시 반영되며 이번 실행에만 유지됩니다.")
                    .font(.caption).foregroundStyle(.secondary)
                Toggle("AirPods 입력이 끊기면 전체 블러 유지하기", isOn: $model.retainBlurOnInputLoss)
                Text("기본값은 블러 해제입니다. 옵션을 켜면 탈착·연결 끊김 등 입력 중단 시 전체 블러를 유지합니다. 이번 실행에만 유지되며, 다시 착용한 뒤에는 보호를 끄고 정면 보정 후 시작해 주세요. 자리 이탈·기립 자동 보호는 아직 연결하지 않았습니다.")
                    .font(.caption).foregroundStyle(.secondary)
            }.frame(maxWidth: .infinity, alignment: .leading).padding(8)
        }
    }

    private var movement: some View {
        GroupBox("4 · 자리 이탈 / 기립 관측 · 실험값") {
            VStack(alignment: .leading, spacing: 10) {
                Text("앉은 상태에서 시작하고, 선택한 동작을 한 번 수행해 주세요. 최대 10초 동안의 수직 이동 추정이며 실제 거리나 기립 판정이 아님.")
                    .font(.caption).foregroundStyle(.secondary)
                HStack {
                    Picker("동작", selection: $model.trialLabel) {
                        ForEach(["앉은 채 정지", "제자리 자세 고침", "일어서서 정지", "일어나 걷고 정지", "의자 뒤로 밀기", "일어섰다 다시 앉기"], id: \.self) { Text($0) }
                    }
                    Button("관측 시작") { model.startProbe() }.disabled(!model.fresh || model.probing)
                    Button("중지") { model.probing = false }.disabled(!model.probing)
                }
                HStack(spacing: 24) {
                    Text(String(format: "시간 %.2f s", model.probe.duration))
                    Text(String(format: "수직 추정 %+.3f m", model.probe.displacement.z))
                    Text(String(format: "속도 %+.3f m/s", model.probe.velocity.z))
                    Text("\(model.probe.sampleCount) samples")
                }.monospacedDigit()
                Text(model.probe.status).font(.caption)
                Text("정지 상태에서 값이 계속 변하면 추정 오차임. 동작 이름은 사람이 정한 비교 조건이며 센서가 판정한 결과가 아님.")
                    .font(.caption).foregroundStyle(.secondary)
            }.padding(8)
        }
    }
}
