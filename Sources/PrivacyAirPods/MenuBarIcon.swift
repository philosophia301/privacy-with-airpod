import AppKit
import Combine
import SwiftUI

/// 메뉴 막대 아이콘의 10초 리듬 규칙. 보호 시작 뒤 경과 시간을 흐림 정도로 바꾸는 유일한 곳.
enum MenuBarBlurRhythm {
    /// 프레임 장수. scripts/make-menu-bar-icon.py가 만든 blur-00..blur-24와 같음.
    static let frameCount = 25
    static let period: TimeInterval = 10
    /// 전환 구간에서만 쓰는 프레임 간격(10fps). MenuBarExtra label 갱신은 15fps에서 CPU가 약 3배로 뛰어 10fps로 둠.
    static let frameInterval: TimeInterval = 1.0 / 10.0

    private struct Segment {
        let start: TimeInterval
        let end: TimeInterval
        let from: Double
        let to: Double
    }

    /// 한 주기의 구간. 시작 흐림과 끝 흐림이 같으면 정지 구간이라 예약 작업을 돌리지 않음.
    private static let segments = [
        Segment(start: 0, end: 2, from: 0, to: 1),
        Segment(start: 2, end: 7, from: 1, to: 1),
        Segment(start: 7, end: 9, from: 1, to: 0),
        Segment(start: 9, end: 10, from: 0, to: 0)
    ]

    struct Moment {
        /// 0이 선명, 1이 최대 흐림.
        let level: Double
        /// 보호 시작부터 잰 다음 상태 변화 시각.
        let nextChange: TimeInterval
        /// 다음 변화 전까지 흐림이 움직이는 중인지.
        let animating: Bool
    }

    static func moment(atElapsed elapsed: TimeInterval) -> Moment {
        let epsilon = 1e-6
        var cycleStart = (elapsed / period).rounded(.down) * period
        var phase = elapsed - cycleStart
        if period - phase < epsilon {
            cycleStart += period
            phase = 0
        }
        let segment = segments.first(where: { phase < $0.end - epsilon }) ?? segments[segments.count - 1]
        let u = min(1, max(0, (phase - segment.start) / (segment.end - segment.start)))
        let eased = u * u * (3 - 2 * u)
        return Moment(level: segment.from + (segment.to - segment.from) * eased,
                      nextChange: cycleStart + segment.end,
                      animating: segment.from != segment.to)
    }

    static func frameIndex(for level: Double) -> Int {
        Int((min(1, max(0, level)) * Double(frameCount - 1)).rounded())
    }
}

/// 메뉴 막대 아이콘이 쓰는 시계 경계. 실제 앱은 Timer, 테스트는 수동 시계를 씀.
@MainActor
protocol MenuBarIconClock: AnyObject {
    var now: TimeInterval { get }
    /// 예약은 하나만 유지함. 새 예약은 이전 예약을 대체하고, repeating이 nil이면 한 번만 실행함.
    func schedule(after delay: TimeInterval, repeating interval: TimeInterval?, _ action: @escaping @MainActor @Sendable () -> Void)
    func cancel()
}

@MainActor
final class SystemMenuBarIconClock: MenuBarIconClock {
    private var timer: Timer?

    var now: TimeInterval { ProcessInfo.processInfo.systemUptime }

    func schedule(after delay: TimeInterval, repeating interval: TimeInterval?, _ action: @escaping @MainActor @Sendable () -> Void) {
        cancel()
        // 메뉴가 열려 추적 중에도 갱신되도록 common 모드에 둠.
        let timer = Timer(fire: Date(timeIntervalSinceNow: max(0, delay)), interval: interval ?? 0,
                          repeats: interval != nil) { _ in
            MainActor.assumeIsolated { action() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func cancel() {
        timer?.invalidate()
        timer = nil
    }
}

/// 메뉴 막대 아이콘 상태. AppModel의 protected를 관찰해 프레임 번호를 정하고, 전환 구간에서만 주기 작업을 예약함.
@MainActor
final class MenuBarIconModel: ObservableObject {
    @Published private(set) var frame = 0
    @Published private(set) var isProtected = false
    /// nil이면 프레임을 다 읽지 못한 것이므로 SF Symbol 눈으로 대체함.
    let frames: [NSImage]?
    private let clock: MenuBarIconClock
    private let reduceMotion: @MainActor () -> Bool
    private var origin: TimeInterval?
    private var subscription: AnyCancellable?
    // 앱 수명과 같은 객체라 해제하지 않음. 테스트는 매번 새 알림 센터를 줌.
    private var observer: NSObjectProtocol?

    init(frames: [NSImage]?, protection: AnyPublisher<Bool, Never>, clock: MenuBarIconClock,
         reduceMotion: @escaping @MainActor () -> Bool, workspaceNotifications: NotificationCenter) {
        self.frames = frames
        self.clock = clock
        self.reduceMotion = reduceMotion
        // @Published 값은 메인 스레드에서 바뀌므로 동기 전달을 메인 액터로 받음.
        subscription = protection.sink { [weak self] on in
            MainActor.assumeIsolated { self?.setProtected(on) }
        }
        observer = workspaceNotifications.addObserver(
            forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil, queue: nil
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.apply() }
        }
    }

    /// 프레임이 없을 때 쓰는 SF Symbol 이름.
    var fallbackSymbolName: String { isProtected ? "eye.slash.fill" : "eye" }

    /// 앱 번들의 프레임. 하나라도 없으면 nil.
    static var bundledFrames: [NSImage]? {
        guard let resources = Bundle.main.resourceURL else { return nil }
        return loadFrames(in: resources.appendingPathComponent("MenuBarIcon", isDirectory: true))
    }

    /// blur-00..blur-24를 읽음. 색을 유지하려고 template을 끄고, 픽셀의 절반 크기(pt)로 둠.
    static func loadFrames(in directory: URL) -> [NSImage]? {
        var frames: [NSImage] = []
        for index in 0..<MenuBarBlurRhythm.frameCount {
            let url = directory.appendingPathComponent(String(format: "blur-%02d.png", index))
            guard let image = NSImage(contentsOf: url),
                  let rep = image.representations.first, rep.pixelsWide > 0, rep.pixelsHigh > 0 else { return nil }
            image.isTemplate = false
            image.size = NSSize(width: CGFloat(rep.pixelsWide) / 2, height: CGFloat(rep.pixelsHigh) / 2)
            frames.append(image)
        }
        return frames
    }

    private func setProtected(_ on: Bool) {
        isProtected = on
        apply()
    }

    /// 보호 상태와 손쉬운 사용 설정으로 전체 리듬을 다시 정함. 이전 예약은 항상 취소함.
    private func apply() {
        clock.cancel()
        origin = nil
        guard isProtected else { setFrame(0); return }
        guard frames != nil else { return }
        if reduceMotion() { setFrame(MenuBarBlurRhythm.frameCount - 1); return }
        origin = clock.now
        step()
    }

    /// 정지 구간의 시작이나 전환 구간의 끝에서 호출함. 정지면 한 번만, 전환이면 10fps로 예약함.
    private func step() {
        guard let origin else { return }
        let elapsed = clock.now - origin
        let moment = MenuBarBlurRhythm.moment(atElapsed: elapsed)
        setFrame(MenuBarBlurRhythm.frameIndex(for: moment.level))
        if moment.animating {
            clock.schedule(after: MenuBarBlurRhythm.frameInterval, repeating: MenuBarBlurRhythm.frameInterval) { [weak self] in
                self?.animate()
            }
        } else {
            clock.schedule(after: max(0, moment.nextChange - elapsed), repeating: nil) { [weak self] in
                self?.step()
            }
        }
    }

    /// 전환 구간의 10fps 프레임. 전환이 끝났으면 정지 구간 예약으로 넘김.
    private func animate() {
        guard let origin else { return }
        let moment = MenuBarBlurRhythm.moment(atElapsed: clock.now - origin)
        guard moment.animating else { step(); return }
        setFrame(MenuBarBlurRhythm.frameIndex(for: moment.level))
    }

    private func setFrame(_ index: Int) {
        if frame != index { frame = index }
    }
}

/// 라벨이 그릴 대상. 라벨 분기를 테스트에서 값으로 확인하려고 분리함.
enum MenuBarLabelSource: Equatable {
    case frame(Int)
    case symbol(String)
}

extension MenuBarIconModel {
    var labelSource: MenuBarLabelSource {
        frames == nil ? .symbol(fallbackSymbolName) : .frame(frame)
    }
}

/// 메뉴 막대 라벨. 프레임이 있으면 원본 색 그림, 없으면 SF Symbol 눈.
struct MenuBarIconLabel: View {
    @ObservedObject var model: MenuBarIconModel

    var body: some View {
        Group {
            switch model.labelSource {
            case .frame(let index):
                if let frames = model.frames { Image(nsImage: frames[index]) }
            case .symbol(let name):
                Image(systemName: name)
            }
        }
        .accessibilityLabel("Privacy AirPods")
    }
}

/// 메뉴 맨 위의 판본 문구. Dock 아이콘 없이도 실행 중인 판본을 확인하려고 둠.
enum MenuBarVersionText {
    static var current: String {
        let info = Bundle.main.infoDictionary
        return make(short: info?["CFBundleShortVersionString"] as? String,
                    build: info?["CFBundleVersion"] as? String)
    }

    static func make(short: String?, build: String?) -> String {
        guard let short, let build, !short.isEmpty, !build.isEmpty else { return "개발 실행 · 판본 정보 없음" }
        return "버전 \(short) (빌드 \(build))"
    }
}
