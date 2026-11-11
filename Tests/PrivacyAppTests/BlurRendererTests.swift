import Testing
import CoreImage
import CoreGraphics
@testable import PrivacyAirPods

@Test func realVariableBlurPreservesSharpSideAndBlursFarSide() throws {
    let size = 256
    var bytes = [UInt8](repeating: 0, count: size * size * 4)
    for y in 0..<size {
        for x in 0..<size {
            let value: UInt8 = ((x / 4 + y / 4) % 2) == 0 ? 255 : 0
            let index = (y * size + x) * 4
            bytes[index] = value
            bytes[index+1] = value
            bytes[index+2] = value
            bytes[index+3] = 255
        }
    }
    let input = CIImage(bitmapData: Data(bytes), bytesPerRow: size * 4, size: CGSize(width: size, height: size), format: .RGBA8, colorSpace: CGColorSpaceCreateDeviceRGB())
    let renderer = BlurRenderer()
    let clear = try #require(renderer.render(input, settings: RenderSettings(angle: 0)))
    let turned = try #require(renderer.render(input, settings: RenderSettings(angle: 35, start: 15, full: 55, radius: 20)))
    let covered = try #require(renderer.render(input, settings: RenderSettings(forceCovered: true)))
    let clearPixels = try pixels(clear)
    let turnedPixels = try pixels(turned)
    let coveredPixels = try pixels(covered)
    let baseline = contrast(clearPixels, start: 10, end: 35, width: size)
    let left = contrast(turnedPixels, start: 10, end: 35, width: size)
    let right = contrast(turnedPixels, start: 220, end: 245, width: size)
    #expect(baseline > 100)
    #expect(left < baseline * 0.4)
    #expect(right > left * 2)
    #expect(contrast(coveredPixels, start: 10, end: 245, width: size) < baseline * 0.4)
    let coveredMean = stride(from: 0, to: coveredPixels.count, by: 4).map { Double(coveredPixels[$0]) }.reduce(0, +) / Double(size * size)
    #expect(coveredMean > 50 && coveredMean < 230)
    #expect(clear.width == size && turned.height == size)
}

private func pixels(_ image: CGImage) throws -> [UInt8] {
    var result = [UInt8](repeating: 0, count: image.width * image.height * 4)
    try result.withUnsafeMutableBytes { pointer in
        let context = try #require(CGContext(data: pointer.baseAddress, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: image.width * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
    }
    return result
}

private func contrast(_ pixels: [UInt8], start: Int, end: Int, width: Int) -> Double {
    let values = (80..<160).flatMap { y in (start..<end).map { x in Double(pixels[(y * width + x) * 4]) } }
    let average = values.reduce(0, +) / Double(values.count)
    return sqrt(values.reduce(0) { $0 + ($1 - average) * ($1 - average) } / Double(values.count))
}

@Test func largeFrameOptimizationPreservesRetinaDetailOnClearSide() throws {
    let width = 1536
    let input = try #require(CIFilter(name: "CICheckerboardGenerator", parameters: ["inputWidth": 1])?.outputImage)
        .cropped(to: CGRect(x: 0, y: 0, width: width, height: 1400))
    let renderer = BlurRenderer()
    let baseline = try #require(renderer.render(input, settings: RenderSettings(angle: 0)))
    let result = try #require(renderer.render(input, settings: RenderSettings(angle: 35, start: 15, full: 55, radius: 40)))
    let original = try pixels(baseline)
    let actual = try pixels(result)
    #expect(result.width == width && result.height == 1400)
    let clearContrast = contrast(original, start: width - 40, end: width - 10, width: width)
    #expect(clearContrast > 40)
    #expect(contrast(actual, start: width - 40, end: width - 10, width: width) > clearContrast * 0.95)
    #expect(contrast(actual, start: 10, end: 40, width: width) < clearContrast * 0.4)
}
