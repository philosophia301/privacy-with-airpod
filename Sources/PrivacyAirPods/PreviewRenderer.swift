import AppKit
import CoreImage

/// 설정 창이 보일 때만 예제 이미지를 렌더링하고, 오래된 결과는 표시하지 않음.
@MainActor
final class PreviewRenderer {
    struct Frame: Sendable {
        let image: CGImage
        let settings: RenderSettings
    }

    var onFailure: @MainActor @Sendable () -> Void = {}
    var onFrame: @MainActor @Sendable (Frame) -> Void = { _ in }

    private struct Job: Sendable {
        let image: CIImage
        let settings: RenderSettings
    }

    /// 직렬 큐에서만 사용하며 CIContext를 프레임마다 다시 만들지 않음.
    private final class Rendering: @unchecked Sendable {
        let renderer = BlurRenderer()
    }
    private let rendering = Rendering()
    private let renderQueue = DispatchQueue(label: "Privacy preview renderer", qos: .userInitiated)
    private var work: LatestRenderWork<Job>?
    private var delivery: LatestFrameDelivery<Frame>?
    private var generation = 0
    private var visible = false
    private var lastSettings: RenderSettings?

    func setVisible(_ visible: Bool) {
        guard self.visible != visible else { return }
        self.visible = visible
        generation += 1
        lastSettings = nil

        if visible {
            startSession(generation: generation)
        } else {
            work?.close()
            delivery?.close()
            work = nil
            delivery = nil
        }
    }

    func request(_ image: CIImage, settings: RenderSettings) {
        guard visible, let work, let delivery, lastSettings != settings else { return }
        lastSettings = settings
        guard work.submit(Job(image: image, settings: settings)) else { return }

        let attempt = generation
        renderQueue.async { [work, delivery, rendering, weak self] in
            while let job = work.take() {
                autoreleasepool {
                    guard let rendered = rendering.renderer.render(job.image, settings: job.settings) else {
                        NSLog("Privacy preview render failed")
                        Task { @MainActor [weak self] in
                            guard let self, self.visible, self.generation == attempt else { return }
                            self.onFailure()
                        }
                        return
                    }
                    delivery.submit(Frame(image: rendered, settings: job.settings))
                }
            }
        }
    }

    func stop() {
        setVisible(false)
    }

    private func startSession(generation: Int) {
        let work = LatestRenderWork<Job>()
        let delivery = LatestFrameDelivery<Frame> { [weak self] frame in
            guard let self, self.visible, self.generation == generation else { return }
            self.onFrame(frame)
        }
        self.work = work
        self.delivery = delivery
    }
}
