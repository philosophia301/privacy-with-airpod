import Foundation
import CoreImage
import Metal

@main
struct RendererBenchmark {
    @MainActor static func main() throws {
        guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue() else {
            throw NSError(domain: "RendererBenchmark", code: 1, userInfo: [NSLocalizedDescriptionKey: "Metal unavailable"])
        }
        let size = CGSize(width: 3456, height: 2234)
        _ = queue
        let presenter = try MetalPresenter(size: size, scale: 1, colorSpace: CGColorSpaceCreateDeviceRGB())
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: Int(size.width), height: Int(size.height), mipmapped: false)
        descriptor.usage = [.shaderRead, .shaderWrite, .renderTarget]
        descriptor.storageMode = .private
        guard let texture = device.makeTexture(descriptor: descriptor) else {
            throw NSError(domain: "RendererBenchmark", code: 2, userInfo: [NSLocalizedDescriptionKey: "Texture unavailable"])
        }
        let renderer = BlurRenderer()
        let generator = CIFilter(name: "CICheckerboardGenerator", parameters: ["inputWidth": 8])!.outputImage!
        print("GPU: \(device.name); synthetic 3456x2234; 2 warmups + 16 alternating samples; GPU completion included; presentation excluded")
        for scenario in ["clear", "partial", "full"] {
            var results = ["CGImage": [Double](), "MetalTexture": [Double]()]
            for index in 0..<18 {
                for mode in (index.isMultiple(of: 2) ? ["CGImage", "MetalTexture"] : ["MetalTexture", "CGImage"]) {
                    try autoreleasepool {
                        let input = generator.transformed(by: CGAffineTransform(translationX: Double(index), y: 0))
                            .cropped(to: CGRect(origin: .zero, size: size))
                        let settings = RenderSettings(angle: scenario == "clear" ? 0 : 35 + Double(index % 3), start: 15, full: 55, radius: 62.5, forceCovered: scenario == "full")
                        let start = CFAbsoluteTimeGetCurrent()
                        if mode == "CGImage" {
                            guard let image = renderer.render(input, settings: settings) else {
                                throw NSError(domain: "RendererBenchmark", code: 3)
                            }
                            _ = image.dataProvider?.data
                        } else {
                            guard let image = renderer.outputImage(input, settings: settings) else {
                                throw NSError(domain: "RendererBenchmark", code: 4)
                            }
                            let command = try presenter.encode(image, to: texture)
                            try command.complete()
                        }
                        if index >= 2 { results[mode]!.append((CFAbsoluteTimeGetCurrent() - start) * 1000) }
                    }
                }
            }
            for mode in ["CGImage", "MetalTexture"] {
                let values = results[mode]!.sorted()
                print(String(format: "%@ %@: median %.2f ms; min %.2f; max %.2f", scenario, mode, (values[7] + values[8]) / 2, values.first!, values.last!))
            }
        }
    }
}
