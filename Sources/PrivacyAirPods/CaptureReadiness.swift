import Foundation

/// 모든 대상 화면의 첫 유효 프레임이 준비되기 전에 보호 중으로 안내하지 않음.
@MainActor
final class CaptureReadiness {
    private var remaining: Set<UInt32>
    private var outcome: Result<Void, any Error>?
    private var waiters: [CheckedContinuation<Void, any Error>] = []

    init(displays: Set<UInt32>) {
        remaining = displays
        if displays.isEmpty { outcome = .failure(Failure.noDisplays) }
    }

    func receivedFrame(display: UInt32) {
        guard outcome == nil, remaining.remove(display) != nil else { return }
        if remaining.isEmpty { finish(.success(())) }
    }

    func fail(_ error: any Error) { finish(.failure(error)) }

    func wait(timeout: Duration = .seconds(5)) async throws {
        if let outcome { return try outcome.get() }
        let deadline = Task { @MainActor in
            do { try await Task.sleep(for: timeout) }
            catch { return }
            fail(Failure.timedOut)
        }
        defer { deadline.cancel() }
        try await withCheckedThrowingContinuation { waiters.append($0) }
    }

    private func finish(_ result: Result<Void, any Error>) {
        guard outcome == nil else { return }
        outcome = result
        let pending = waiters
        waiters = []
        for waiter in pending { waiter.resume(with: result) }
    }

    enum Failure: LocalizedError {
        case noDisplays, timedOut, interrupted
        var errorDescription: String? {
            switch self {
            case .noDisplays: "블러를 적용할 화면이 없습니다."
            case .timedOut: "모든 화면의 첫 프레임을 받지 못했습니다. 화면 권한과 연결을 확인해 주세요."
            case .interrupted: "첫 화면을 준비하는 중 입력 또는 화면 처리가 중단됐습니다."
            }
        }
    }
}
