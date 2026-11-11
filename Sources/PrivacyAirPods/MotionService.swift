import Foundation
@preconcurrency import CoreMotion

struct HeadSample: Sendable {
    let timestamp: Double
    let receivedAt: TimeInterval
    let yaw: Double
    let acceleration: SIMD3<Double>
    let gravity: SIMD3<Double>
    let source: Int

    func isFresh(at now: TimeInterval) -> Bool {
        freshnessRemaining(at: now) > 0
    }

    /// 센서가 침묵해도 기존 유효 기간의 끝에서 다시 확인할 수 있게 함.
    func freshnessRemaining(at now: TimeInterval) -> TimeInterval {
        let age = now - timestamp
        let deliveryAge = now - receivedAt
        guard age.isFinite, age >= 0, deliveryAge.isFinite, deliveryAge >= 0 else { return 0 }
        return max(0, 0.75 - max(age, deliveryAge))
    }
}

/// AppModel이 받는 머리 동작 입력. 실제 앱은 MotionService, 테스트는 합성 입력을 씀.
@MainActor
protocol HeadMotionSource: AnyObject {
    var onSample: ((HeadSample) -> Void)? { get set }
    var onError: ((String) -> Void)? { get set }
    func start()
    func stop()
}

@MainActor
final class MotionService: HeadMotionSource {
    private let manager = CMHeadphoneMotionManager()
    private let queue: OperationQueue = {
        let queue = OperationQueue()
        queue.name = "Headphone motion"
        queue.maxConcurrentOperationCount = 1
        return queue
    }()
    private var generation = 0
    var onSample: ((HeadSample) -> Void)?
    var onError: ((String) -> Void)?

    func start() {
        stop()
        let status = CMHeadphoneMotionManager.authorizationStatus()
        guard status != .denied && status != .restricted else {
            onError?("동작 접근이 거절됨. 시스템 설정에서 권한을 확인해 주세요.")
            return
        }
        guard manager.isDeviceMotionAvailable else {
            onError?("AirPods 동작 입력을 사용할 수 없음. 착용·Mac 연결을 확인해 주세요.")
            return
        }
        manager.startDeviceMotionUpdates(to: queue, withHandler: makeHandler(generation: generation))
    }

    func makeHandler(generation currentGeneration: Int) -> @Sendable (CMDeviceMotion?, (any Error)?) -> Void {
        // Core Motion은 별도 큐에서 호출함. MainActor 추론을 막고 UI 전달만 명시적으로 이동함.
        { @Sendable [weak self] motion, error in
            if let error {
                let message = error.localizedDescription
                Task { @MainActor [weak self] in
                    guard self?.generation == currentGeneration else { return }
                    self?.onError?(message)
                }
                return
            }
            guard let motion else { return }
            let sample = HeadSample(
                timestamp: motion.timestamp,
                receivedAt: ProcessInfo.processInfo.systemUptime,
                yaw: motion.attitude.yaw * 180 / .pi,
                acceleration: SIMD3(motion.userAcceleration.x, motion.userAcceleration.y, motion.userAcceleration.z),
                gravity: SIMD3(motion.gravity.x, motion.gravity.y, motion.gravity.z),
                source: motion.sensorLocation.rawValue
            )
            Task { @MainActor [weak self] in
                guard self?.generation == currentGeneration else { return }
                self?.onSample?(sample)
            }
        }
    }

    func stop() {
        generation += 1
        manager.stopDeviceMotionUpdates()
    }
}
