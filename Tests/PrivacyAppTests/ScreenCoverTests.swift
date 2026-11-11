import AppKit
import Testing
import QuartzCore
import CoreGraphics
import CoreFoundation
@testable import PrivacyAirPods

/// 실제 WindowServer 출력 검사. 내장 화면 여부와 무관하게 주 화면 하나를 사용함.
@MainActor
private func anyScreen() throws -> NSScreen {
    try #require(NSScreen.screens.first)
}

private func rgbaBytes(of image: CGImage) throws -> [UInt8] {
    let providerData = try #require(image.dataProvider?.data)
    let count = CFDataGetLength(providerData)
    let pointer = try #require(CFDataGetBytePtr(providerData))
    return Array(UnsafeBufferPointer(start: pointer, count: count))
}

@MainActor
@Test func coverIncludesNotchSidesWithoutCroppingAndPassesClicksBelowPopUpMenus() throws {
    let screen = try anyScreen()
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

@MainActor
@Test func independentProtectionKeepsOneLiveSurfaceInOwnedOutputAndClosesOnStop() async throws {
    let screen = try anyScreen()
    let cover = ScreenCover()
    try await cover.start(settings: [screen.displayID: .covered()])
    defer { cover.stop() }
    let panel = try #require(cover.outputWindows.first)
    #expect(cover.outputWindows.allSatisfy { $0.screen?.displayID == screen.displayID })
    let backdrop = try #require(panel.contentView as? SpaceTransitionBackdrop)
    #expect(panel.collectionBehavior.contains(.fullScreenNone))
    #expect(!panel.collectionBehavior.contains(.canJoinAllSpaces))
    #expect(panel.ignoresMouseEvents)
    #expect(panel.isVisible)
    cover.update([screen.displayID: .covered()])
    #expect(panel.contentView === backdrop)
    #expect(cover.outputWindows.count == 1)
    cover.stop()
    #expect(!panel.isVisible)
    // 늦게 도착한 각도 갱신이 종료된 보호를 다시 켜지 않아야 함.
    cover.update([screen.displayID: .covered()])
    #expect(!panel.isVisible)
    #expect(cover.outputWindows.isEmpty)
}

@MainActor
@Test func invalidDisplayDoesNotLeavePartialProtection() async throws {
    let cover = ScreenCover()
    let screen = try anyScreen()
    await #expect(throws: ScreenCover.CoverError.self) {
        try await cover.start(settings: [screen.displayID: .covered(), UInt32.max: .covered()])
    }
    #expect(cover.outputWindows.isEmpty)
}

@MainActor
@Test func variableMaskHasExactRGBAValuesAndRadiusOnlyUpdateReusesCachedMask() throws {
    let view = try SpaceTransitionBackdrop(frame: CGRect(x: 0, y: 0, width: 256, height: 100), settings: .hinge(angle: 0))
    let initial = view.maskImage
    let initialBytes = try rgbaBytes(of: initial)
    func pixel(_ bytes: [UInt8], _ x: Int) -> [UInt8] {
        Array(bytes[(x * 4)..<(x * 4 + 4)])
    }
    // RGB는 불투명 흰색이고, 정면에서는 마스크 알파만 투명함.
    #expect(pixel(initialBytes, 0) == [255, 255, 255, 0])
    #expect(pixel(initialBytes, 128) == [255, 255, 255, 0])
    #expect(pixel(initialBytes, 255) == [255, 255, 255, 0])

    // 35°는 15°~55° 전환의 중간이므로 가운데는 정확히 절반 강도, 먼 쪽은 선명함.
    try view.update(.hinge(angle: 35, radius: 40))
    let angled = view.maskImage
    let angledBytes = try rgbaBytes(of: angled)
    #expect(pixel(angledBytes, 0) == [255, 255, 255, 255])
    #expect(pixel(angledBytes, 127) == [255, 255, 255, 128])
    #expect(pixel(angledBytes, 255) == [255, 255, 255, 0])
    #expect(view.submissionCount == 1)

    try view.update(.hinge(angle: 35, radius: 80))
    #expect(view.maskImage === angled)
    #expect(view.submissionCount == 2)
    try view.update(.hinge(angle: 35, radius: 80))
    #expect(view.submissionCount == 2)
}

@MainActor
@Test func invalidRadiusEmergencyCallsBackOnceUnderReentrantUpdateAndStopClosesOutput() async throws {
    let screen = try anyScreen()
    let cover = ScreenCover()
    try await cover.start(settings: [screen.displayID: .hinge(angle: 0, radius: 20)])
    defer { cover.stop() }
    let panel = try #require(cover.outputWindows.first)
    let backdrop = try #require(panel.contentView as? SpaceTransitionBackdrop)
    var failureCount = 0
    cover.onFailure = { _ in
        failureCount += 1
        // callback 안에서 동기적으로 다시 갱신해도 실패 출력 차단에 흡수되고 재귀하지 않아야 함.
        cover.update([screen.displayID: .hinge(angle: 0, radius: .nan)])
    }

    cover.update([screen.displayID: .hinge(angle: 0, radius: .nan)])
    #expect(failureCount == 1)
    #expect(backdrop.emergencyCovered)
    #expect(panel.isVisible)
    #expect(cover.maskUpdateCount == 0)

    cover.update([screen.displayID: .hinge(angle: 0, radius: 20)])
    #expect(failureCount == 1)
    #expect(backdrop.emergencyCovered)

    cover.stop()
    #expect(cover.outputWindows.isEmpty)
    #expect(!panel.isVisible)
}

@MainActor
@Test func settingsWindowRisesAboveCoverOnlyWhileProtecting() {
    let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 200, height: 120), styleMask: [.titled],
                          backing: .buffered, defer: true)
    window.isReleasedWhenClosed = false
    defer { window.close() }
    let view = WindowLevel.LevelView()
    view.aboveCover = true
    // SwiftUI가 첫 갱신을 창 연결 전에 호출해도 창에 붙는 시점에 적용돼야 함.
    window.contentView = view
    #expect(window.level.rawValue > WindowLevels.cover.rawValue)
    #expect(!window.hidesOnDeactivate)
    view.aboveCover = false
    view.apply()
    #expect(window.level == .normal)
}
