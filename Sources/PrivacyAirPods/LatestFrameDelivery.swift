import Foundation

/// 메인 액터가 바쁠 때 표시할 프레임을 쌓지 않고 최신 결과 하나만 전달함.
final class LatestFrameDelivery<Value: Sendable>: Sendable {
    private let pending = LatestRenderWork<Value>()
    private let onValue: @MainActor @Sendable (Value) -> Void

    init(onValue: @escaping @MainActor @Sendable (Value) -> Void) {
        self.onValue = onValue
    }

    func submit(_ value: Value) {
        guard pending.submit(value) else { return }
        Task { @MainActor [pending, onValue] in
            while let latest = pending.take() { onValue(latest) }
        }
    }

    func close() { pending.close() }
}
