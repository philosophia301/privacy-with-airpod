import AppKit
@preconcurrency import ScreenCaptureKit
import CoreImage
import CoreMedia

// 이전 캡처 출력의 비교 진단용. 실제 화면 보호는 ScreenCover의 native 경로만 사용함.
/// 요청 시각이나 sample PTS를 표시 시각으로 대신 쓰지 않음. 시각 근거 없는 프레임은 폐기함.
struct CapturedScreenFrame {
    let image: CIImage
    let displayTime: UInt64

    init?(_ sample: CMSampleBuffer) {
        guard sample.isValid,
              let attachments = CMSampleBufferGetSampleAttachmentsArray(sample, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
              let status = attachments.first?[.status] as? Int,
              SCFrameStatus(rawValue: status) == .complete,
              let time = attachments.first?[.displayTime] as? UInt64,
              let buffer = sample.imageBuffer else { return nil }
        image = CIImage(cvPixelBuffer: buffer)
        displayTime = time
    }
}

/// 캡처 큐는 최신 입력만 넘기며 무거운 렌더링은 별도 직렬 큐에서 수행함.
final class ScreenOutput: NSObject, SCStreamOutput, SCStreamDelegate, @unchecked Sendable {
    let queue = DispatchQueue(label: "Privacy screen renderer", qos: .userInteractive)
    private let renderer = BlurRenderer()
    private let renderQueue = DispatchQueue(label: "Privacy latest frame renderer", qos: .userInteractive)
    private let stateLock = NSLock()
    private struct Job: Sendable {
        let image: CIImage
        let settings: RenderSettings
        let capturedAt: UInt64
    }
    private let work = LatestRenderWork<Job>()
    private var settings: RenderSettings
    private var lastImage: (image: CIImage, capturedAt: UInt64)?
    private var minimumFrameTime: UInt64 = 0
    private var stopped = false
    private let pointWidth: CGFloat
    private let delivery: LatestFrameDelivery<Bool>
    private let presentedDelivery: LatestFrameDelivery<UInt64>
    private var announcedPresentation = true
    private let presenter: MetalPresenter
    private var announcedFirstFrame = false
    private let onFailure: @MainActor @Sendable (String) -> Void

    init(settings: RenderSettings, pointWidth: CGFloat, presenter: MetalPresenter, onFrame: @escaping @MainActor @Sendable () -> Void, onPresented: @escaping @MainActor @Sendable (UInt64) -> Void = { _ in }, onFailure: @escaping @MainActor @Sendable (String) -> Void) {
        self.settings = settings
        self.pointWidth = pointWidth
        self.presenter = presenter
        self.delivery = LatestFrameDelivery { _ in onFrame() }
        self.presentedDelivery = LatestFrameDelivery(onValue: onPresented)
        self.onFailure = onFailure
    }

    func update(_ settings: RenderSettings) {
        stateLock.withLock {
            guard !stopped, self.settings != settings else { return }
            self.settings = settings
            if let image = lastImage { submit(image.image, settings: settings, capturedAt: image.capturedAt) }
        }
    }

    func invalidateFrames(before time: UInt64) {
        stateLock.withLock {
            minimumFrameTime = max(minimumFrameTime, time)
            lastImage = nil
            announcedPresentation = false
            work.discardPending()
            presenter.invalidateFrames(before: time)
        }
    }

    func stopRendering() {
        stateLock.withLock { stopped = true; work.close(); lastImage = nil }
        presenter.stop()
        delivery.close()
        presentedDelivery.close()
    }

    private func submit(_ image: CIImage, settings: RenderSettings, capturedAt: UInt64) {
        guard work.submit(Job(image: image, settings: settings, capturedAt: capturedAt)) else { return }
        renderQueue.async { [self] in
            while let job = work.take() {
                autoreleasepool { render(job.image, settings: job.settings, capturedAt: job.capturedAt) }
            }
        }
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen, let frame = CapturedScreenFrame(sampleBuffer) else { return }
        accept(frame.image, capturedAt: frame.displayTime)
    }

    @discardableResult
    func accept(_ image: CIImage, capturedAt: UInt64) -> Bool {
        stateLock.withLock {
            guard !stopped, capturedAt >= minimumFrameTime,
                  capturedAt >= (lastImage?.capturedAt ?? 0) else { return false }
            lastImage = (image, capturedAt)
            submit(image, settings: settings, capturedAt: capturedAt)
            return true
        }
    }

    private func render(_ image: CIImage, settings: RenderSettings, capturedAt: UInt64) {
        var pixelSettings = settings
        // Retina에서도 화면상 블러 폭을 유지하도록 포인트 강도를 픽셀로 환산함.
        pixelSettings.radius *= image.extent.width / pointWidth
        guard let rendered = renderer.outputImage(image, settings: pixelSettings) else {
            stopRendering()
            Task { @MainActor [onFailure] in onFailure("화면 블러 렌더링에 실패했습니다.") }
            return
        }
        do {
            if try presenter.present(rendered, capturedAt: capturedAt, onPresented: { [weak self] in self?.didPresent(capturedAt) }), !announcedFirstFrame {
                announcedFirstFrame = true
                delivery.submit(true)
            }
        } catch {
            stopRendering()
            let message = error.localizedDescription
            Task { @MainActor [onFailure] in onFailure(message) }
        }
    }

    private func didPresent(_ capturedAt: UInt64) {
        let announce = stateLock.withLock {
            guard !stopped, capturedAt >= minimumFrameTime, !announcedPresentation else { return false }
            announcedPresentation = true
            return true
        }
        if announce { presentedDelivery.submit(capturedAt) }
    }

    func stream(_ stream: SCStream, didStopWithError error: any Error) {
        stopRendering()
        let message = error.localizedDescription
        Task { @MainActor [onFailure] in onFailure(message) }
    }
}

enum CoverGeometry {
    static func captureConfiguration(size: CGSize, scale: CGFloat) -> SCStreamConfiguration {
        let configuration = SCStreamConfiguration()
        configuration.width = Int((size.width * scale).rounded())
        configuration.height = Int((size.height * scale).rounded())
        return configuration
    }

}
