import Foundation
@preconcurrency import CoreMotion

/// AirPods 착용자의 걷기 여부. 자리 이탈 판정 입력이며 원시 활동 값은 저장하지 않음.
enum HeadActivity: Equatable, Sendable {
    case moving
    case stationary
    case unknown

    /// 낮은 신뢰도는 걷기·정지 판정이 아니므로 unknown으로 둠. 잘못된 이탈 판정을 피하기 위함.
    static func classify(
        walking: Bool,
        running: Bool,
        stationary: Bool,
        confidence: CMMotionActivityConfidence
    ) -> HeadActivity {
        guard confidence.rawValue >= CMMotionActivityConfidence.medium.rawValue else { return .unknown }
        if walking || running { return .moving }
        if stationary { return .stationary }
        return .unknown
    }
}

/// 자리 이탈 판정기가 받는 활동 입력. 실제 앱은 HeadActivityService, 테스트는 합성 입력을 씀.
@MainActor
protocol HeadActivitySource: AnyObject {
    var onActivity: ((HeadActivity) -> Void)? { get set }
    func start()
    func stop()
}

@MainActor
final class HeadActivityService: HeadActivitySource {
    private let manager = CMHeadphoneActivityManager()
    private let queue: OperationQueue = {
        let queue = OperationQueue()
        queue.name = "Headphone activity"
        queue.maxConcurrentOperationCount = 1
        return queue
    }()
    private var generation = 0
    var onActivity: ((HeadActivity) -> Void)?

    /// 걷기 감지가 없어도 일어서기 판정은 계속 가능하므로 시작 실패는 조용히 무시함.
    func start() {
        stop()
        let status = CMHeadphoneActivityManager.authorizationStatus()
        guard status != .denied && status != .restricted else { return }
        guard manager.isActivityAvailable else { return }
        manager.startActivityUpdates(to: queue, withHandler: makeHandler(generation: generation))
    }

    func makeHandler(generation currentGeneration: Int) -> @Sendable (CMMotionActivity?, (any Error)?) -> Void {
        // Core Motion은 별도 큐에서 호출함. CMMotionActivity 객체는 넘기지 않고 값만 꺼내 MainActor로 보냄.
        { @Sendable [weak self] activity, error in
            guard error == nil, let activity else { return }
            let classified = HeadActivity.classify(
                walking: activity.walking,
                running: activity.running,
                stationary: activity.stationary,
                confidence: activity.confidence
            )
            Task { @MainActor [weak self] in
                guard self?.generation == currentGeneration else { return }
                self?.onActivity?(classified)
            }
        }
    }

    func stop() {
        generation += 1
        manager.stopActivityUpdates()
    }
}
