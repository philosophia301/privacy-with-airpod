import Foundation
@preconcurrency import CoreMotion

struct HeadSample: Sendable {
    let timestamp: Double
    let receivedAt: TimeInterval
    let yaw: Double
    let acceleration: SIMD3<Double>
    let gravity: SIMD3<Double>
    let source: Int

    /// 이보다 덜 된 입력은 제때 온 것으로 봄(초). 넘으면 늦은 입력으로 보고 보호 화면을 서서히 전체 블러로 덮음.
    static let onTimeAge: TimeInterval = 0.75
    /// 이만큼 새 입력이 없으면 입력이 끊긴 것으로 봄(초). 실측 2차에서 표본이 최대 1.71초 늦게 왔으므로
    /// 여유를 둔 값임(2026-11-20 사용자 결정). 그 사이의 늦은 입력은 끊김이 아니라 지연임.
    static let lossAge: TimeInterval = 2.5

    /// AirPods 센서 시각이 Mac 시각보다 앞서도 받아 주는 폭(초). 실측 2차에서 표본 59개가 받은 시각보다
    /// 최대 0.01초 앞선 센서 시각으로 왔음. 이 폭이 없으면 그 표본에서 입력 중단으로 보고 보호를 끔.
    static let clockSkew: TimeInterval = 0.1

    /// 측정 시각과 도착 시각 중 더 오래된 쪽에서 지금까지 지난 초. 시각이 깨졌거나 `clockSkew`보다 더 뒤면 nil.
    func age(at now: TimeInterval) -> TimeInterval? {
        let age = now - timestamp
        let deliveryAge = now - receivedAt
        guard age.isFinite, age >= -Self.clockSkew, deliveryAge.isFinite, deliveryAge >= 0 else { return nil }
        return max(0, age, deliveryAge)
    }

    /// 제때 온 입력임. 정면 맞추기는 이 입력에서만 하고, 보호 화면은 이 입력일 때만 고개를 그대로 따라감.
    func isFresh(at now: TimeInterval) -> Bool { freshnessRemaining(at: now) > 0 }

    /// 제때 온 입력으로 남은 초. Blur Lab 진단 앱이 이 끝에서 다시 확인함.
    func freshnessRemaining(at now: TimeInterval) -> TimeInterval {
        age(at: now).map { max(0, Self.onTimeAge - $0) } ?? 0
    }

    /// 늦었어도 아직 끊김으로 보지 않는 입력임.
    func isAlive(at now: TimeInterval) -> Bool { age(at: now).map { $0 < Self.lossAge } ?? false }
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
    /// 동작 접근 거절을 알리는 문구. 거절 여부 판별은 AppModel이 이 문구를 비교하는 한 곳에서만 함.
    static let accessDeniedMessage = "동작 접근이 거절됨. 시스템 설정에서 권한을 확인해 주세요."

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
            onError?(Self.accessDeniedMessage)
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
