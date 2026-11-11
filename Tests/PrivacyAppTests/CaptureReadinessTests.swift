import Testing
@testable import PrivacyAirPods

@MainActor
struct CaptureReadinessTests {
    enum Fault: Error { case interrupted }

    @Test func firstFrameFromEveryDisplayIsRequired() async throws {
        let gate = CaptureReadiness(displays: [1, 2])
        gate.receivedFrame(display: 1)
        gate.receivedFrame(display: 1)
        gate.receivedFrame(display: 99)
        gate.fail(Fault.interrupted)
        await #expect(throws: Fault.self) { try await gate.wait() }
    }

    @Test func framesArrivingBeforeWaitAreNotLost() async throws {
        let gate = CaptureReadiness(displays: [1, 2])
        gate.receivedFrame(display: 2)
        gate.receivedFrame(display: 1)
        try await gate.wait()
    }

    @Test func pendingWaitFinishesWhenLastFrameArrives() async throws {
        let gate = CaptureReadiness(displays: [1, 2])
        gate.receivedFrame(display: 1)
        Task { @MainActor in gate.receivedFrame(display: 2) }
        try await gate.wait()
    }

    @Test func failureUnblocksWaitAndLateFramesCannotChangeIt() async {
        let gate = CaptureReadiness(displays: [1])
        Task { @MainActor in
            gate.fail(Fault.interrupted)
            gate.receivedFrame(display: 1)
        }
        await #expect(throws: Fault.self) { try await gate.wait() }
    }

    @Test func missingFirstFrameTimesOutInsteadOfReportingProtected() async {
        let gate = CaptureReadiness(displays: [1, 2])
        gate.receivedFrame(display: 1)
        do {
            try await gate.wait(timeout: .zero)
            Issue.record("준비되지 않은 화면을 시작 완료로 처리함")
        } catch CaptureReadiness.Failure.timedOut {
        } catch {
            Issue.record("예상하지 않은 오류: \(error)")
        }
    }

    @Test func cancellationAndEmptyTargetsCannotReportReady() async {
        let cancelled = CaptureReadiness(displays: [1])
        cancelled.fail(CancellationError())
        await #expect(throws: CancellationError.self) { try await cancelled.wait() }
        let empty = CaptureReadiness(displays: [])
        await #expect(throws: CaptureReadiness.Failure.self) { try await empty.wait() }
    }
}
