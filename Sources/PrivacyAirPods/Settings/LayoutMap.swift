import AppKit
import PrivacyCore
import SwiftUI

// 배치 수정 시트의 위에서 본 지도와 옆 높이 그림. 상태와 기하는 LayoutEditor가 맡고, 이 파일은 그리기와 이벤트 전달만 함.

/// 화면 번호와 이름. 키는 DisplayPose.id임.
typealias LayoutMapLabels = [UInt32: (number: Int, name: String)]

/// 지도 바탕색. 설정 창 공통 팔레트에 없어서 여기서만 둠.
private let paperColor = Color(cheekyHex: 0xFFFCF4)

/// 머리 중심에서 바라본 위쪽 지도. sample마다 바뀌는 고개 각도는 이 뷰만 관찰함.
struct TopLayoutMap: View {
    @Binding var editor: LayoutEditor
    @ObservedObject var readout: LiveReadout
    /// nil이면 AirPods 고개 각도를 쓰고, 값이 있으면 수동 회전 값을 씀.
    let manualYaw: Double?
    let start: Double
    let transitionFraction: Double
    let armLength: Double
    let labels: LayoutMapLabels
    @State private var pressing = false

    var body: some View {
        let snapshot = editor
        let gaze = manualYaw ?? readout.angle
        let strengths = snapshot.faceStrengths(gaze: gaze, start: start, transitionFraction: transitionFraction)
        let painter = MapPainter(editor: snapshot, gaze: gaze, start: start, armLength: armLength,
                                 strengths: strengths, labels: labels)
        ZStack(alignment: .topLeading) {
            Canvas { context, _ in
                painter.paint(&context)
            }
            .frame(width: LayoutEditor.mapSize.width, height: LayoutEditor.mapSize.height)
            .accessibilityHidden(true)
            ForEach(snapshot.poses, id: \.id) { pose in
                monitorTarget(pose, selected: snapshot.selected)
            }
        }
        .frame(width: LayoutEditor.mapSize.width, height: LayoutEditor.mapSize.height, alignment: .topLeading)
        .contentShape(Rectangle())
        .gesture(mapDrag)
        .onContinuousHover(perform: updateCursor)
        .focusable()
        .onKeyPress(phases: [.down, .repeat]) { handleKey($0) }
        .accessibilityElement(children: .contain)
    }

    private var mapDrag: some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .local)
            .onChanged { value in
                if pressing {
                    editor.updateDrag(to: value.location)
                } else {
                    pressing = true
                    _ = editor.beginMapDrag(at: value.location)
                }
            }
            .onEnded { _ in
                editor.endDrag()
                pressing = false
            }
    }

    private func updateCursor(_ phase: HoverPhase) {
        switch phase {
        case let .active(point):
            cursor(at: point).set()
        case .ended:
            NSCursor.arrow.set()
        }
    }

    private func cursor(at point: CGPoint) -> NSCursor {
        if pressing { return .closedHand }
        return editor.grip(at: point) == nil ? .arrow : .openHand
    }

    // MARK: 키보드

    private func handleKey(_ press: KeyPress) -> KeyPress.Result {
        let step: Double = press.modifiers.contains(.shift) ? 5 : 1
        guard let change = keyChange(press, step: step) else { return .ignored }
        mutate(change)
        return .handled
    }

    /// 방향키는 선택 화면을 옮기고, '['와 ']'는 선택 화면을 돌림. 해당 없는 키는 nil임.
    private func keyChange(_ press: KeyPress, step: Double) -> ((inout LayoutEditor) -> Void)? {
        switch press.key {
        case .leftArrow: return { $0.nudge(dx: -step, dz: 0) }
        case .rightArrow: return { $0.nudge(dx: step, dz: 0) }
        case .upArrow: return { $0.nudge(dx: 0, dz: step) }
        case .downArrow: return { $0.nudge(dx: 0, dz: -step) }
        default: break
        }
        switch press.characters {
        case "[", "{": return { $0.rotate(by: -step) }
        case "]", "}": return { $0.rotate(by: step) }
        default: return nil
        }
    }

    /// 복사본을 바꾼 뒤 한 번에 되돌려 씀. 바인딩 값 하나만 갱신함.
    private func mutate(_ change: (inout LayoutEditor) -> Void) {
        var next = editor
        change(&next)
        editor = next
    }

    // MARK: 접근성

    /// 화면마다 badge 위치에 투명한 요소를 겹쳐 VoiceOver가 화면 단위로 읽고 조절하게 함.
    private func monitorTarget(_ pose: DisplayPose, selected: UInt32) -> some View {
        let shape = LayoutEditor.mapShape(of: pose)
        let id = pose.id
        return Color.clear
            .frame(width: 44, height: 44)
            .contentShape(Rectangle())
            .position(shape.badge)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(LayoutMapText.name(id: id, labels: labels))
            .accessibilityValue(LayoutMapText.value(pose))
            .accessibilityAddTraits(id == selected ? [.isSelected] : [])
            .accessibilityActions {
                Button("선택") { mutate { $0.selected = id } }
                Button("왼쪽으로 5cm") { mutate { $0.selected = id; $0.nudge(dx: -5, dz: 0) } }
                Button("오른쪽으로 5cm") { mutate { $0.selected = id; $0.nudge(dx: 5, dz: 0) } }
                Button("앞으로 5cm") { mutate { $0.selected = id; $0.nudge(dx: 0, dz: 5) } }
                Button("뒤로 5cm") { mutate { $0.selected = id; $0.nudge(dx: 0, dz: -5) } }
                Button("오른쪽으로 5도 돌리기") { mutate { $0.selected = id; $0.rotate(by: 5) } }
                Button("왼쪽으로 5도 돌리기") { mutate { $0.selected = id; $0.rotate(by: -5) } }
            }
    }
}

/// 옆에서 본 높이 그림. 선택 화면의 높이를 보여 주며 끌어서 높이를 바꿈. 조절 수단은 시트의 슬라이더이므로 접근성에서는 숨김.
struct SideHeightView: View {
    @Binding var editor: LayoutEditor
    @State private var pressing = false

    var body: some View {
        let snapshot = editor
        Canvas { context, _ in
            SidePainter(editor: snapshot).paint(&context)
        }
        .frame(width: LayoutEditor.sideSize.width, height: LayoutEditor.sideSize.height)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .contentShape(Rectangle())
        .gesture(sideDrag)
        .accessibilityHidden(true)
    }

    private var sideDrag: some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .local)
            .onChanged { value in
                if pressing {
                    editor.updateDrag(to: value.location)
                } else {
                    pressing = true
                    _ = editor.beginSideDrag(at: value.location)
                }
            }
            .onEnded { _ in
                editor.endDrag()
                pressing = false
            }
    }
}

// MARK: 그리기

/// 위쪽 지도의 그림 순서를 묶음. 뒤에서 앞으로 바탕, 책상, 거리 고리, 시야, 시선, 손끝, 화면, 머리 순서로 그림.
private struct MapPainter {
    let editor: LayoutEditor
    let gaze: Double
    let start: Double
    let armLength: Double
    let strengths: [UInt32: [Double]]
    let labels: LayoutMapLabels

    private var headCenter: CGPoint { mapPoint(0, 0) }

    func paint(_ context: inout GraphicsContext) {
        paintPaper(&context)
        paintDesk(&context)
        paintDistanceRings(&context)
        paintVisibleSector(&context)
        paintGazeLine(&context)
        paintReach(&context)
        for shape in editor.mapMonitors {
            paintMonitor(shape, &context)
        }
        paintHead(&context)
    }

    private func paintPaper(_ context: inout GraphicsContext) {
        context.fill(Path(CGRect(origin: .zero, size: LayoutEditor.mapSize)), with: .color(paperColor))
        var dots = Path()
        for x in stride(from: CGFloat(9), to: LayoutEditor.mapSize.width, by: 18) {
            for y in stride(from: CGFloat(9), to: LayoutEditor.mapSize.height, by: 18) {
                dots.addEllipse(in: CGRect(x: x - 1.2, y: y - 1.2, width: 2.4, height: 2.4))
            }
        }
        context.fill(dots, with: .color(CheekyPalette.dashedDivider))
    }

    private func paintDesk(_ context: inout GraphicsContext) {
        let desk = polyline([mapPoint(-130, 8), mapPoint(130, 8), mapPoint(130, 100), mapPoint(-130, 100)],
                            closed: true)
        context.fill(desk, with: .color(CheekyPalette.tabOff.opacity(0.7)))
        context.stroke(desk, with: .color(CheekyPalette.tan), lineWidth: 2)
    }

    private func paintDistanceRings(_ context: inout GraphicsContext) {
        for radius in [50.0, 100.0, 150.0] {
            context.strokeLine(worldArc(radius: radius, from: -90, to: 90, steps: 72),
                               color: CheekyPalette.dashedDivider, width: 1.5, dash: [4, 5])
            // 숫자는 고리 왼쪽 끝 아래, 머리 높이 줄 밑에 자처럼 둠. 가운데 위에 두면 시선 선과 화면에 겹침.
            let end = worldPoint(radius, degrees: -90)
            context.draw(Text("\(Int(radius))").font(CheekyFont.display(10))
                            .foregroundStyle(CheekyPalette.cocoa),
                         at: CGPoint(x: max(end.x, 12), y: end.y + 4), anchor: .top)
        }
    }

    /// 머리에서 고개 방향 양쪽 끝각까지의 범위. 사용자가 고개를 돌려 볼 수 있는 시야를 뜻함.
    private func paintVisibleSector(_ context: inout GraphicsContext) {
        let sector = [headCenter] + worldArc(radius: 200, from: gaze - start, to: gaze + start, steps: 48)
        let path = polyline(sector, closed: true)
        context.fill(path, with: .color(CheekyPalette.yellow.opacity(0.42)))
        context.stroke(path, with: .color(CheekyPalette.yellowDeep), lineWidth: 1.5)
    }

    private func paintGazeLine(_ context: inout GraphicsContext) {
        context.strokeLine([headCenter, worldPoint(205, degrees: gaze)],
                           color: CheekyPalette.cocoa, width: 2, dash: [4, 5])
    }

    private func paintReach(_ context: inout GraphicsContext) {
        context.strokeLine(worldArc(radius: armLength, from: -84, to: 84, steps: 64),
                           color: CheekyPalette.brown, width: 2, dash: [2, 6], cap: .round)
        let label = worldPoint(armLength + 12 / Double(LayoutEditor.mapScale), degrees: 72)
        context.draw(Text("손끝").font(CheekyFont.text(11, weight: .bold)).foregroundStyle(CheekyPalette.cocoa),
                     at: label)
    }

    private func paintMonitor(_ shape: LayoutEditor.MapMonitor, _ context: inout GraphicsContext) {
        let selected = shape.id == editor.selected
        if selected {
            context.stroke(polyline(shape.body, closed: true), with: .color(CheekyPalette.yellowDeep),
                           style: StrokeStyle(lineWidth: 9, lineJoin: .round))
        }
        paintBody(shape, &context)
        paintFace(shape, &context)
        paintBadge(shape, selected: selected, &context)
        if selected {
            paintHandle(shape, &context)
        }
    }

    private func paintBody(_ shape: LayoutEditor.MapMonitor, _ context: inout GraphicsContext) {
        let body = polyline(shape.body, closed: true)
        context.fill(body, with: .color(CheekyPalette.cocoa))
        context.stroke(body, with: .color(CheekyPalette.ink), lineWidth: 1.5)
    }

    /// 앞면은 흰 바탕 위에 블러 세기 표본을 왼쪽에서 오른쪽으로 이은 그라데이션을 덧칠함.
    private func paintFace(_ shape: LayoutEditor.MapMonitor, _ context: inout GraphicsContext) {
        let face = polyline(shape.face, closed: true)
        context.fill(face, with: .color(.white))
        guard let samples = strengths[shape.id], samples.count >= 2 else { return }
        let stops = samples.indices.map { index in
            Gradient.Stop(color: CheekyPalette.tan.opacity(samples[index] * 0.9),
                          location: CGFloat(index) / CGFloat(samples.count - 1))
        }
        context.fill(face, with: .linearGradient(Gradient(stops: stops),
                                                 startPoint: shape.left, endPoint: shape.right))
    }

    private func paintBadge(_ shape: LayoutEditor.MapMonitor, selected: Bool, _ context: inout GraphicsContext) {
        let center = shape.badge
        context.fill(circlePath(center, radius: 11), with: .color(selected ? CheekyPalette.yellow : CheekyPalette.white))
        context.stroke(circlePath(center, radius: 11), with: .color(CheekyPalette.cocoa), lineWidth: 2)
        let number = labels[shape.id].map { "\($0.number)" } ?? "?"
        context.draw(Text(number).font(CheekyFont.display(12)).foregroundStyle(CheekyPalette.ink), at: center)
        // 이름은 badge 위에 둠. badge와 화면 사이에 두면 1.85pt/cm 축척에서 화면 몸체와 겹침.
        let name = labels[shape.id]?.name ?? ""
        context.draw(Text(LayoutMapText.shortName(name)).font(CheekyFont.text(11, weight: .bold))
                        .foregroundStyle(CheekyPalette.cocoa),
                     at: CGPoint(x: center.x, y: center.y - 13), anchor: .bottom)
    }

    /// 선택 화면의 손잡이. 드래그로 yaw를 바꾸며 화면 오른쪽 끝에서 바깥으로 이어짐.
    private func paintHandle(_ shape: LayoutEditor.MapMonitor, _ context: inout GraphicsContext) {
        context.strokeLine([shape.right, shape.handle], color: CheekyPalette.cocoa, width: 2, dash: [4, 5])
        context.fill(circlePath(shape.handle, radius: 10), with: .color(CheekyPalette.yellow))
        context.stroke(circlePath(shape.handle, radius: 10), with: .color(CheekyPalette.cocoa), lineWidth: 2)
        context.draw(Text(Image(systemName: "arrow.clockwise")).font(.system(size: 10, weight: .bold))
                        .foregroundStyle(CheekyPalette.cocoa),
                     at: shape.handle)
    }

    /// 머리 원, 고개 방향 막대, 양쪽 귀 점. 귀 점은 고개에 수직인 8.6cm 위치에 둠.
    private func paintHead(_ context: inout GraphicsContext) {
        let center = headCenter
        let radius = 9 * LayoutEditor.mapScale
        context.fill(circlePath(center, radius: radius), with: .color(.white))
        context.stroke(circlePath(center, radius: radius), with: .color(CheekyPalette.cocoa), lineWidth: 2.5)
        context.strokeLine([worldPoint(8, degrees: gaze), worldPoint(15, degrees: gaze)],
                           color: CheekyPalette.yellowDeep, width: 6, cap: .round)
        let radians = gaze * .pi / 180
        for sign in [-1.0, 1.0] {
            let ear = mapPoint(8.6 * cos(radians) * sign, -8.6 * sin(radians) * sign)
            context.fill(circlePath(ear, radius: 6), with: .color(.white))
            context.stroke(circlePath(ear, radius: 6), with: .color(CheekyPalette.cocoa), lineWidth: 2)
        }
    }
}

/// 옆 그림의 그림 순서. 눈높이, 책상, 선택 화면, 머리 순서로 그림.
private struct SidePainter {
    let editor: LayoutEditor

    func paint(_ context: inout GraphicsContext) {
        paintFrame(&context)
        paintEyeLevel(&context)
        paintDesk(&context)
        if let pose = editor.selectedPose {
            paintScreen(pose, &context)
        }
        paintHead(&context)
    }

    private func paintFrame(_ context: inout GraphicsContext) {
        let rect = CGRect(origin: .zero, size: LayoutEditor.sideSize)
        context.fill(Path(roundedRect: rect, cornerRadius: 12), with: .color(paperColor))
        context.stroke(Path(roundedRect: rect.insetBy(dx: 1, dy: 1), cornerRadius: 12),
                       with: .color(CheekyPalette.dashedDivider),
                       style: StrokeStyle(lineWidth: 2, dash: [4, 4]))
    }

    private func paintEyeLevel(_ context: inout GraphicsContext) {
        let eyeY = sideY(0)
        let width = LayoutEditor.sideSize.width
        context.strokeLine([CGPoint(x: 0, y: eyeY), CGPoint(x: width, y: eyeY)],
                           color: CheekyPalette.brown, width: 1.5, dash: [3, 4])
        context.draw(Text("눈높이").font(CheekyFont.text(10, weight: .bold)).foregroundStyle(CheekyPalette.cocoa),
                     at: CGPoint(x: 28, y: eyeY - 5), anchor: .bottomLeading)
    }

    private func paintDesk(_ context: inout GraphicsContext) {
        let deskY = sideY(-38)
        context.strokeLine([CGPoint(x: 0, y: deskY), CGPoint(x: LayoutEditor.sideSize.width, y: deskY)],
                           color: CheekyPalette.tan, width: 4)
    }

    /// 화면 위아래 끝을 막대로 그림. 가로 위치는 30~132pt로 잘라 옆 그림 안에 두고, 낮은 화면은 책상까지 받침을 그림.
    private func paintScreen(_ pose: DisplayPose, _ context: inout GraphicsContext) {
        let distance = Double(LayoutEditor.distance(of: pose))
        let x = min(max(LayoutEditor.sidePoint(distance: distance, y: 0).x, 30), 132)
        let bottomCM = pose.y - pose.height / 2
        let top = sideY(pose.y + pose.height / 2)
        let bottom = sideY(bottomCM)
        if bottomCM > -35 {
            context.strokeLine([CGPoint(x: x, y: bottom), CGPoint(x: x, y: sideY(-38))],
                               color: CheekyPalette.cocoa, width: 3)
        }
        context.strokeLine([CGPoint(x: x, y: top), CGPoint(x: x, y: bottom)],
                           color: CheekyPalette.cocoa, width: 8, cap: .round)
        context.strokeLine([CGPoint(x: x - 4, y: top), CGPoint(x: x - 4, y: bottom)],
                           color: .white, width: 2.5, cap: .round)
    }

    private func paintHead(_ context: inout GraphicsContext) {
        let center = LayoutEditor.sideOrigin
        context.fill(circlePath(center, radius: 9), with: .color(.white))
        context.stroke(circlePath(center, radius: 9), with: .color(CheekyPalette.cocoa), lineWidth: 2)
    }
}

// MARK: 공통 도우미

/// 지도 점 도우미. 기하 계산은 LayoutEditor에 맡기고 이름만 짧게 함.
private func mapPoint(_ x: Double, _ z: Double) -> CGPoint {
    LayoutEditor.mapPoint(x: x, z: z)
}

/// 머리 중심에서 고개 각도(도, 오른쪽이 양수) 방향으로 cm 거리에 있는 지도 점.
private func worldPoint(_ radius: Double, degrees: Double) -> CGPoint {
    let radians = degrees * .pi / 180
    return mapPoint(radius * sin(radians), radius * cos(radians))
}

private func worldArc(radius: Double, from: Double, to: Double, steps: Int) -> [CGPoint] {
    (0...steps).map { index in
        worldPoint(radius, degrees: from + (to - from) * Double(index) / Double(steps))
    }
}

private func sideY(_ y: Double) -> CGFloat {
    LayoutEditor.sidePoint(distance: 0, y: y).y
}

private func polyline(_ points: [CGPoint], closed: Bool = false) -> Path {
    var path = Path()
    guard let first = points.first else { return path }
    path.move(to: first)
    for point in points.dropFirst() {
        path.addLine(to: point)
    }
    if closed {
        path.closeSubpath()
    }
    return path
}

private func circlePath(_ center: CGPoint, radius: CGFloat) -> Path {
    Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius,
                           width: radius * 2, height: radius * 2))
}

private extension GraphicsContext {
    mutating func strokeLine(_ points: [CGPoint], color: Color, width: CGFloat,
                             dash: [CGFloat] = [], cap: CGLineCap = .butt) {
        stroke(polyline(points), with: .color(color),
               style: StrokeStyle(lineWidth: width, lineCap: cap, dash: dash))
    }
}

/// 접근성 문구. 화면 이름은 10자까지만 표시하고 나머지는 줄임.
private enum LayoutMapText {
    static func shortName(_ name: String) -> String {
        name.count > 10 ? String(name.prefix(9)) + "…" : name
    }

    static func name(id: UInt32, labels: LayoutMapLabels) -> String {
        guard let label = labels[id] else { return "화면" }
        return "화면 \(label.number) \(label.name)"
    }

    /// 왼쪽과 오른쪽은 사용자 기준이며 x가 음수이면 왼쪽임.
    static func value(_ pose: DisplayPose) -> String {
        let x = Int(pose.x.rounded())
        let side: String
        if x < 0 {
            side = "왼쪽 \(-x)cm"
        } else if x > 0 {
            side = "오른쪽 \(x)cm"
        } else {
            side = "가운데"
        }
        return "\(side), 거리 \(LayoutEditor.distance(of: pose))cm, 회전 \(Int(pose.yawDegrees.rounded()))도"
    }
}
