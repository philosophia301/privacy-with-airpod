import AppKit
import CoreImage
import Metal
import QuartzCore

/// 레이어 배치는 MainActor에서 한 번 고정함. 렌더/표시는 ScreenOutput의 직렬 큐에서만 수행함.
final class MetalPresenter: @unchecked Sendable {
    private var currentLayer: CAMetalLayer
    var layer: CAMetalLayer { lock.withLock { currentLayer } }
    private let commandQueue: any MTLCommandQueue
    private let context: CIContext
    private let colorSpace: CGColorSpace
    private let lock = NSLock()
    private var stopped = false
    private var minimumFrameTime: UInt64 = 0

    @MainActor
    init(size: CGSize, scale: CGFloat, colorSpace: CGColorSpace) throws {
        guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue() else {
            throw Failure.unavailable
        }
        self.commandQueue = queue
        self.context = CIContext(mtlCommandQueue: queue, options: [.cacheIntermediates: false])
        self.colorSpace = colorSpace
        let layer = CAMetalLayer()
        layer.device = device
        layer.pixelFormat = .bgra8Unorm
        layer.framebufferOnly = false
        layer.frame = CGRect(origin: .zero, size: size)
        layer.contentsScale = scale
        layer.drawableSize = CGSize(width: (size.width * scale).rounded(), height: (size.height * scale).rounded())
        layer.colorspace = colorSpace
        layer.isOpaque = true
        layer.backgroundColor = CGColor(gray: 0, alpha: 1)
        layer.maximumDrawableCount = 2
        layer.allowsNextDrawableTimeout = true
        self.currentLayer = layer
    }

    @MainActor
    func replaceLayerForSpace(before time: UInt64) -> CAMetalLayer {
        lock.withLock {
            let old = currentLayer
            let fresh = CAMetalLayer()
            fresh.device = old.device
            fresh.pixelFormat = old.pixelFormat
            fresh.framebufferOnly = false
            fresh.frame = old.frame
            fresh.contentsScale = old.contentsScale
            fresh.drawableSize = old.drawableSize
            fresh.colorspace = old.colorspace
            fresh.isOpaque = false
            fresh.maximumDrawableCount = 2
            fresh.allowsNextDrawableTimeout = true
            minimumFrameTime = max(minimumFrameTime, time)
            currentLayer = fresh
            return fresh
        }
    }

    func invalidateFrames(before time: UInt64) {
        lock.withLock { minimumFrameTime = max(minimumFrameTime, time) }
    }

    func stop() { lock.withLock { stopped = true } }

    /// 대기는 GPU 전용 직렬 큐에 한정함. 출력 버퍼를 CPU 이미지로 읽어오지 않음.
    func present(_ image: CIImage, capturedAt: UInt64 = mach_absolute_time(), onPresented: (@Sendable () -> Void)? = nil) throws -> Bool {
        guard lock.withLock({ !stopped && capturedAt >= minimumFrameTime }) else { return false }
        let target = layer
        guard let drawable = target.nextDrawable() else { throw Failure.drawableUnavailable }
        guard lock.withLock({ !stopped && capturedAt >= minimumFrameTime }) else { return false }
        let frame = try encode(image, to: drawable.texture)
        try frame.complete()
        return lock.withLock {
            guard !stopped, capturedAt >= minimumFrameTime else { return false }
            // GPU 완료 중 Space가 바뀌거나 stop되면 그 결과를 표시하지 않음.
            if let onPresented { drawable.addPresentedHandler { _ in onPresented() } }
            drawable.present()
            return true
        }
    }

    /// 동일 경로를 실제 GPU 텍스처로 검사할 수 있도록 인코딩 경계를 분리함.
    func encode(_ image: CIImage, to texture: any MTLTexture) throws -> EncodedFrame {
        guard image.extent.origin == .zero,
              Int(image.extent.width) == texture.width, Int(image.extent.height) == texture.height else {
            throw Failure.geometryChanged
        }
        guard let command = commandQueue.makeCommandBuffer() else { throw Failure.unavailable }
        let destination = CIRenderDestination(mtlTexture: texture, commandBuffer: command)
        destination.colorSpace = colorSpace
        destination.isFlipped = true
        let task = try context.startTask(toRender: image, to: destination)
        return EncodedFrame(command: command, task: task)
    }

    struct EncodedFrame {
        let command: any MTLCommandBuffer
        let task: CIRenderTask

        func complete() throws {
            command.commit()
            command.waitUntilCompleted()
            guard command.status == .completed else { throw command.error ?? Failure.renderFailed }
            _ = try task.waitUntilCompleted()
        }
    }

    enum Failure: LocalizedError {
        case unavailable, drawableUnavailable, geometryChanged, renderFailed
        var errorDescription: String? {
            switch self {
            case .unavailable: "GPU 화면 출력을 준비하지 못했습니다."
            case .drawableUnavailable: "GPU 화면 출력 버퍼를 받지 못했습니다."
            case .geometryChanged: "캡처와 화면의 픽셀 크기가 달라 보호를 중단했습니다."
            case .renderFailed: "GPU 화면 처리에 실패했습니다."
            }
        }
    }
}
