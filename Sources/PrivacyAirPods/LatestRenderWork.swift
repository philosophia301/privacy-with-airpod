import Foundation

/// 처리 중인 작업 하나와 가장 최신 대기 작업 하나만 유지함.
final class LatestRenderWork<Value: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var pending: Value?
    private var running = false
    private var closed = false

    func submit(_ value: Value) -> Bool {
        lock.withLock {
            guard !closed else { return false }
            pending = value
            guard !running else { return false }
            running = true
            return true
        }
    }

    func take() -> Value? {
        lock.withLock {
            guard let value = pending else { running = false; return nil }
            pending = nil
            return value
        }
    }

    func close() {
        lock.withLock { closed = true; pending = nil }
    }
}
