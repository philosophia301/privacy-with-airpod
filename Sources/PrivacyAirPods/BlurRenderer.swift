import CoreImage
import CoreGraphics
import PrivacyCore

struct RenderSettings: Sendable, Equatable {
    var angle: Double = 0
    var start: Double = 15
    var full: Double = 55
    var radius: Double = 45
    var forceCovered = false
    var panorama: PanoramaSlice?
    var spatial: CompiledDisplayAngles?
    var gaze = 0.0
    var spatialStart = 35.0
    var spatialTransition = 20.0

    func strength(at x: Double) -> Double {
        if forceCovered { return 1 }
        if let spatial { return spatial.strength(at: x, gaze: gaze, start: spatialStart, transition: spatialTransition) }
        if let panorama { return panorama.strength(at: x) }
        return BlurProfile(startDegrees: start, fullDegrees: full).strength(angle: angle, horizontalPosition: x)
    }

}

/// 렌더 큐 하나에서 사용함. 가장자리 확장으로 블러 경계의 투명 여백을 막음.
final class BlurRenderer {
    private lazy var context = CIContext(options: [.cacheIntermediates: false])

    func render(_ input: CIImage, settings: RenderSettings) -> CGImage? {
        guard let output = outputImage(input, settings: settings) else { return nil }
        return context.createCGImage(output, from: output.extent)
    }

    func outputImage(_ input: CIImage, settings: RenderSettings) -> CIImage? {
        let extent = input.extent
        guard extent.width > 0, extent.height > 0, extent.width.isFinite, extent.height.isFinite else { return nil }
        let width = 256
        let bytes = (0..<width).map { index -> UInt8 in
            let value = settings.strength(at: Double(index) / Double(width - 1))
            return UInt8((value * 255).rounded())
        }
        if !bytes.contains(where: { $0 > 0 }) || settings.radius <= 0 {
            return input
        }
        func maskImage(_ values: [UInt8]) -> CIImage {
            CIImage(bitmapData: Data(values), bytesPerRow: width, size: CGSize(width: width, height: 1), format: .L8, colorSpace: CGColorSpaceCreateDeviceGray())
                .transformed(by: CGAffineTransform(scaleX: extent.width / Double(width), y: extent.height))
                .transformed(by: CGAffineTransform(translationX: extent.minX, y: extent.minY))
        }
        let mask = maskImage(bytes)
        // 고해상도 원본은 유지하고 이미 흐려질 분기만 축소해 처리함.
        let scale = extent.width * extent.height > 2_000_000 ? 0.5 : 1.0
        let transform = CGAffineTransform(scaleX: scale, y: scale)
        guard let filter = CIFilter(name: "CIMaskedVariableBlur") else { return nil }
        filter.setValue(input.transformed(by: transform).clampedToExtent(), forKey: kCIInputImageKey)
        filter.setValue(mask.transformed(by: transform).clampedToExtent(), forKey: "inputMask")
        filter.setValue(settings.radius * scale, forKey: kCIInputRadiusKey)
        guard var output = filter.outputImage?.cropped(to: extent.applying(transform)) else { return nil }
        if scale < 1 {
            output = output.transformed(by: CGAffineTransform(scaleX: 1 / scale, y: 1 / scale))
            let blend = bytes.map { UInt8((min(1, Double($0) / 255 * settings.radius / 2) * 255).rounded()) }
            output = output.applyingFilter("CIBlendWithMask", parameters: [
                kCIInputBackgroundImageKey: input, "inputMaskImage": maskImage(blend)
            ])
        }
        return output.cropped(to: extent)
    }
}
