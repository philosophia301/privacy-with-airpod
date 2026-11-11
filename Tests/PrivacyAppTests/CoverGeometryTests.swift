import AppKit
import Testing
import QuartzCore
import CoreGraphics
import CoreFoundation
@testable import PrivacyAirPods

@MainActor
private func builtInScreen() throws -> NSScreen {
    try #require(NSScreen.screens.first { CGDisplayIsBuiltin($0.displayID) != 0 })
}

private func rgbaBytes(of image: CGImage) throws -> [UInt8] {
    let providerData = try #require(image.dataProvider?.data)
    let count = CFDataGetLength(providerData)
    let pointer = try #require(CFDataGetBytePtr(providerData))
    return Array(UnsafeBufferPointer(start: pointer, count: count))
}

@MainActor
@Test func coverIncludesNotchSidesWithoutCroppingAndPassesClicksBelowPopUpMenus() throws {
    let screen = try builtInScreen()
    let panel = try ScreenCover().makePanel(screen: screen)
    defer { panel.close() }
    let view = try #require(panel.contentView)
    let layer = try #require(view.layer)
    #expect(panel.frame == screen.frame)
    #expect(view.bounds.size == screen.frame.size)
    #expect(layer.contentsRect == CGRect(x: 0, y: 0, width: 1, height: 1))
    #expect(panel.ignoresMouseEvents)
    #expect(panel.level.rawValue > Int(CGWindowLevelForKey(.mainMenuWindow)))
    #expect(panel.level.rawValue < Int(CGWindowLevelForKey(.popUpMenuWindow)))
    #expect(layer.contentsScale == screen.backingScaleFactor)
}

@Test func retinaCapturePreservesBackingPixelsInsteadOfUpscalingPointResolution() {
    let retina = CoverGeometry.captureConfiguration(size: CGSize(width: 1728, height: 1117), scale: 2)
    #expect(retina.width == 3456)
    #expect(retina.height == 2234)
    let standard = CoverGeometry.captureConfiguration(size: CGSize(width: 1920, height: 1080), scale: 1)
    #expect(standard.width == 1920)
    #expect(standard.height == 1080)
}

@MainActor
@Test func independentProtectionKeepsOneLiveSurfaceInOwnedOutputAndClosesOnStop() async throws {
    let screen = try builtInScreen()
    let cover = ScreenCover()
    try await cover.start(settings: [screen.displayID: RenderSettings(forceCovered: true)])
    defer { cover.stop() }
    let panel = try #require(cover.outputWindows.first)
    #expect(cover.outputWindows.allSatisfy { panel in
        guard let panelScreen = panel.screen else { return false }
        return CGDisplayIsBuiltin(panelScreen.displayID) != 0
    })
    let backdrop = try #require(panel.contentView as? SpaceTransitionBackdrop)
    #expect(panel.collectionBehavior.contains(.fullScreenNone))
    #expect(!panel.collectionBehavior.contains(.canJoinAllSpaces))
    #expect(panel.ignoresMouseEvents)
    #expect(panel.isVisible)
    cover.update([screen.displayID: RenderSettings(forceCovered: true)])
    #expect(panel.contentView === backdrop)
    #expect(cover.outputWindows.count == 1)
    cover.stop()
    #expect(!panel.isVisible)
    // 늦게 도착한 각도 갱신이 종료된 보호를 다시 켜지 않아야 함.
    cover.update([screen.displayID: RenderSettings(forceCovered: true)])
    #expect(!panel.isVisible)
    #expect(cover.outputWindows.isEmpty)
}

@MainActor
@Test func invalidDisplayDoesNotLeavePartialProtection() async throws {
    let cover = ScreenCover()
    let screen = try builtInScreen()
    await #expect(throws: ScreenCover.CoverError.self) {
        try await cover.start(settings: [screen.displayID: RenderSettings(), UInt32.max: RenderSettings()])
    }
    #expect(cover.outputWindows.isEmpty)
}

@MainActor
@Test func variableMaskHasExactRGBAValuesAndRadiusOnlyUpdateReusesCachedMask() throws {
    let view = try SpaceTransitionBackdrop(frame: CGRect(x: 0, y: 0, width: 256, height: 100), settings: RenderSettings(angle: 0))
    let initial = try #require(view.maskImage)
    let initialBytes = try rgbaBytes(of: initial)
    func pixel(_ bytes: [UInt8], _ x: Int) -> [UInt8] {
        Array(bytes[(x * 4)..<(x * 4 + 4)])
    }
    // RGB는 불투명 흰색이고, 정면에서는 마스크 알파만 투명함.
    #expect(pixel(initialBytes, 0) == [255, 255, 255, 0])
    #expect(pixel(initialBytes, 128) == [255, 255, 255, 0])
    #expect(pixel(initialBytes, 255) == [255, 255, 255, 0])

    // 35° is halfway through the configured 15°→55° transition, so the
    // center sample is exactly half strength while the far side is clear.
    try view.update(RenderSettings(angle: 35, radius: 40))
    let angled = try #require(view.maskImage)
    let angledBytes = try rgbaBytes(of: angled)
    #expect(pixel(angledBytes, 0) == [255, 255, 255, 255])
    #expect(pixel(angledBytes, 127) == [255, 255, 255, 128])
    #expect(pixel(angledBytes, 255) == [255, 255, 255, 0])
    #expect(view.submissionCount == 1)

    try view.update(RenderSettings(angle: 35, radius: 80))
    #expect(view.maskImage === angled)
    #expect(view.submissionCount == 2)
    try view.update(RenderSettings(angle: 35, radius: 80))
    #expect(view.submissionCount == 2)
}

@MainActor
@Test func invalidRadiusEmergencyCallsBackOnceUnderReentrantUpdateAndStopClosesOutput() async throws {
    let screen = try builtInScreen()
    let cover = ScreenCover()
    try await cover.start(settings: [screen.displayID: RenderSettings(radius: 20)])
    defer { cover.stop() }
    let panel = try #require(cover.outputWindows.first)
    let backdrop = try #require(panel.contentView as? SpaceTransitionBackdrop)
    var failureCount = 0
    cover.onFailure = { _ in
        failureCount += 1
        // The callback is allowed to synchronously try a second update. It must
        // be absorbed by the failed-output gate rather than recurse.
        cover.update([screen.displayID: RenderSettings(radius: .nan)])
    }

    cover.update([screen.displayID: RenderSettings(radius: .nan)])
    #expect(failureCount == 1)
    #expect(backdrop.emergencyCovered)
    #expect(panel.isVisible)
    #expect(cover.maskUpdateCount == 0)

    cover.update([screen.displayID: RenderSettings(radius: 20)])
    #expect(failureCount == 1)
    #expect(backdrop.emergencyCovered)

    cover.stop()
    #expect(cover.outputWindows.isEmpty)
    #expect(!panel.isVisible)
}
