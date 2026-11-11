import AppKit
import CoreImage
import Metal
import ScreenCaptureKit
import Testing
@testable import PrivacyAirPods

@MainActor
@Test func metalOutputPreservesTopBottomColorsAndRetinaPixels() throws {
    let space = CGColorSpace(name: CGColorSpace.sRGB)!
    let presenter = try MetalPresenter(size: CGSize(width: 32, height: 24), scale: 2, colorSpace: space)
    #expect(presenter.layer.drawableSize == CGSize(width: 64, height: 48))
    #expect(presenter.layer.frame.size == CGSize(width: 32, height: 24))
    let device = try #require(presenter.layer.device)
    let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: 64, height: 48, mipmapped: false)
    descriptor.usage = [.shaderRead, .shaderWrite, .renderTarget]
    descriptor.storageMode = .shared
    let texture = try #require(device.makeTexture(descriptor: descriptor))
    let full = CGRect(x: 0, y: 0, width: 64, height: 48)
    let red = CIImage(color: CIColor(red: 1, green: 0, blue: 0)).cropped(to: full)
    let blue = CIImage(color: CIColor(red: 0, green: 0, blue: 1)).cropped(to: CGRect(x: 0, y: 0, width: 64, height: 24))
    let stripe = CIImage(color: CIColor(red: 0, green: 1, blue: 0)).cropped(to: CGRect(x: 31, y: 0, width: 1, height: 48))
    let input = stripe.composited(over: blue.composited(over: red))
    let image = try #require(BlurRenderer().outputImage(input, settings: RenderSettings(angle: 0)))
    let command = try presenter.encode(image, to: texture)
    try command.complete()
    #expect(command.command.status == .completed)
    var bytes = [UInt8](repeating: 0, count: 64 * 48 * 4)
    texture.getBytes(&bytes, bytesPerRow: 64 * 4, from: MTLRegionMake2D(0, 0, 64, 48), mipmapLevel: 0)
    func pixel(_ x: Int, _ y: Int) -> [UInt8] { Array(bytes[(y * 64 + x) * 4..<(y * 64 + x + 1) * 4]) }
    // Metal 첫 행은 화면 위쪽임. 독립 색상으로 상하 반전과 1px 경계 손실을 검출함.
    #expect(pixel(4, 2) == [0, 0, 255, 255])
    #expect(pixel(4, 45) == [255, 0, 0, 255])
    #expect(pixel(31, 2) == [0, 255, 0, 255])
    #expect(pixel(30, 2) == [0, 0, 255, 255])
    #expect(pixel(32, 2) == [0, 0, 255, 255])
}

@MainActor
@Test func metalRejectsMismatchedGeometryAndStoppedPresenterCannotPublish() throws {
    let presenter = try MetalPresenter(size: CGSize(width: 16, height: 16), scale: 1, colorSpace: CGColorSpaceCreateDeviceRGB())
    let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: 16, height: 16, mipmapped: false)
    let texture = try #require(presenter.layer.device?.makeTexture(descriptor: descriptor))
    let image = CIImage(color: .black).cropped(to: CGRect(x: 0, y: 0, width: 8, height: 16))
    #expect(throws: MetalPresenter.Failure.self) { try presenter.encode(image, to: texture) }
    presenter.stop()
    #expect(try presenter.present(image) == false)
}

@MainActor
@Test func streamFailureStopsGPUBeforeMainActorFailureNotificationRuns() throws {
    let presenter = try MetalPresenter(size: CGSize(width: 16, height: 16), scale: 1, colorSpace: CGColorSpaceCreateDeviceRGB())
    let output = ScreenOutput(settings: RenderSettings(), pointWidth: 16, presenter: presenter, onFrame: {}) { _ in }
    let stream = SCStream(filter: SCContentFilter(), configuration: SCStreamConfiguration(), delegate: nil)
    output.stream(stream, didStopWithError: NSError(domain: "SyntheticCaptureFailure", code: 1))
    // 현재 MainActor 작업을 양보하기 전에도 GPU 출력은 이미 닫혀 있어야 함.
    let image = CIImage(color: .red).cropped(to: CGRect(x: 0, y: 0, width: 16, height: 16))
    #expect(try presenter.present(image) == false)
}

@MainActor
@Test func spaceBoundaryRejectsOldFramesWithoutReplacingOrHidingTheLayer() throws {
    let presenter = try MetalPresenter(size: CGSize(width: 16, height: 16), scale: 1, colorSpace: CGColorSpaceCreateDeviceRGB())
    let parent = CALayer()
    parent.addSublayer(presenter.layer)
    let image = CIImage(color: .red).cropped(to: CGRect(x: 0, y: 0, width: 16, height: 16))
    presenter.invalidateFrames(before: 100)
    presenter.invalidateFrames(before: 90)
    #expect(try presenter.present(image, capturedAt: 99) == false)
    #expect(presenter.layer.superlayer === parent)
    #expect(!presenter.layer.isHidden)
    #expect(presenter.layer.opacity == 1)
}

@MainActor
@Test func streamRejectsOldAndReorderedFramesAcrossSpaceBoundaries() throws {
    let presenter = try MetalPresenter(size: CGSize(width: 16, height: 16), scale: 1, colorSpace: CGColorSpaceCreateDeviceRGB())
    let output = ScreenOutput(settings: RenderSettings(), pointWidth: 16, presenter: presenter, onFrame: {}) { _ in }
    defer { output.stopRendering() }
    let image = CIImage(color: .red).cropped(to: CGRect(x: 0, y: 0, width: 16, height: 16))
    output.invalidateFrames(before: 100)
    #expect(!output.accept(image, capturedAt: 99))
    #expect(output.accept(image, capturedAt: 150))
    #expect(!output.accept(image, capturedAt: 120))
    output.invalidateFrames(before: 200)
    output.stopRendering()
    #expect(!output.accept(image, capturedAt: 201))
}

@MainActor
@Test func spaceTransitionGetsAnEmptyTransparentLayerWithTheSamePixelGeometry() throws {
    let presenter = try MetalPresenter(size: CGSize(width: 32, height: 24), scale: 2, colorSpace: CGColorSpaceCreateDeviceRGB())
    let old = presenter.layer
    let fresh = presenter.replaceLayerForSpace(before: 100)
    #expect(fresh !== old)
    #expect(presenter.layer === fresh)
    #expect(fresh.frame == old.frame)
    #expect(fresh.drawableSize == CGSize(width: 64, height: 48))
    #expect(!fresh.isOpaque && fresh.backgroundColor == nil)
    let image = CIImage(color: .red).cropped(to: CGRect(x: 0, y: 0, width: 64, height: 48))
    #expect(try presenter.present(image, capturedAt: 99) == false)
}
