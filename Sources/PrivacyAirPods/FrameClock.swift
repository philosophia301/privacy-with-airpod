import Foundation

/// 보호 갱신 주기와 현재 시각. 센서 유효 기간과 화면 갱신이 같은 시계를 사용함.
/// 실제 앱은 SystemFrameClock, 테스트는 수동으로 진행하는 시계를 씀.
@MainActor
protocol FrameClock: AnyObject {
    /// HeadSample.timestamp와 같은 기준(시스템 가동 시간)의 초.
    var now: TimeInterval { get }
    /// 주기 호출을 시작함. 이미 실행 중이면 이전 호출을 대체함.
    func start(_ tick: @escaping @MainActor @Sendable () -> Void)
    func stop()
}

@MainActor
final class SystemFrameClock: FrameClock {
    private var timer: Timer?

    var now: TimeInterval { ProcessInfo.processInfo.systemUptime }

    func start(_ tick: @escaping @MainActor @Sendable () -> Void) {
        stop()
        // 메인 run loop에 예약하므로 호출은 항상 메인 스레드이며 invalidate 뒤에는 오지 않음.
        timer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { _ in
            MainActor.assumeIsolated { tick() }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }
}
