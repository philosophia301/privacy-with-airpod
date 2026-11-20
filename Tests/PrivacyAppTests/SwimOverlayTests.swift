import AppKit
import ImageIO
import PrivacyCore
import Testing
import UniformTypeIdentifiers
@testable import PrivacyAirPods

/// 왼쪽을 보는 원본의 코 쪽은 빨강, 꼬리 쪽은 파랑으로 칠해 헤엄 방향을 픽셀에서 구분함.
/// 깊은 물의 진한 칸은 페이지마다 파랑이 달라 물 시계가 넘긴 페이지를 픽셀에서 구분함.
@MainActor
private func withSwimSheets(invalidLastPage: Bool = false, prefetches: Bool = false,
                            _ body: (SwimSheets) async throws -> Void) async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let url = directory.appendingPathComponent("swim.tiff")
    let destination = try #require(CGImageDestinationCreateWithURL(url as CFURL, UTType.tiff.identifier as CFString, 12, nil))
    for i in 0..<12 {
        let width = invalidLastPage && i == 11 ? 79 : 80
        let context = try #require(CGContext(data: nil, width: width, height: 28, bitsPerComponent: 8, bytesPerRow: 320,
                              space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(red: 0.1, green: 0.6, blue: 0.7, alpha: 1)
        context.fill(CGRect(x: 6, y: 0, width: 50, height: 28))
        context.setFillColor(red: 0.1, green: 0.3, blue: 0.4 + 0.04 * CGFloat(i), alpha: 1)
        context.fill(CGRect(x: 20, y: 0, width: 36, height: 28))
        let green = CGFloat(i + 1) / 13
        context.setFillColor(red: 1, green: green, blue: 0, alpha: 1)
        context.fill(CGRect(x: 58, y: 8, width: 8, height: 14))
        context.setFillColor(red: 0, green: green, blue: 1, alpha: 1)
        context.fill(CGRect(x: 68, y: 8, width: 8, height: 14))
        CGImageDestinationAddImage(destination, try #require(context.makeImage()), nil)
    }
    #expect(CGImageDestinationFinalize(destination))
    try await body(try #require(SwimSheets(directory: directory, prefetches: prefetches)))
}

/// 시험용 화면. 물 시계는 손으로만 넘어감.
@MainActor
private final class Screen {
    let clock = SwimWaterClock()
    let overlay: SwimOverlay
    let size: CGSize
    private let root = CALayer()

    init(_ sheets: SwimSheets, size: CGSize = CGSize(width: 320, height: 180)) throws {
        overlay = try #require(SwimOverlay(sheets: sheets, clock: clock))
        self.size = size
        root.frame = CGRect(origin: .zero, size: size)
        root.addSublayer(overlay.layer)
    }

    func draw(_ settings: RenderSettings) throws -> [UInt8] {
        overlay.update(settings: settings, size: size)
        return try pixels()
    }

    func pixels() throws -> [UInt8] {
        let width = Int(size.width), height = Int(size.height)
        let context = try #require(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                             bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                                             bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        root.render(in: context)
        let bytes = try #require(context.data?.assumingMemoryBound(to: UInt8.self))
        return Array(UnsafeBufferPointer(start: bytes, count: width * height * 4))
    }
}

private func isNose(_ pixels: [UInt8], _ i: Int) -> Bool { pixels[i] > 245 && pixels[i + 2] < 6 }
private func isTail(_ pixels: [UInt8], _ i: Int) -> Bool { pixels[i] < 6 && pixels[i + 2] > 245 }

private func facePoints(_ direction: SwimStage.Side, in pixels: [UInt8], width: Int) -> Bool {
    let indices = stride(from: 0, to: pixels.count, by: 4)
    let nose = indices.filter { isNose(pixels, $0) }
    let tail = indices.filter { isTail(pixels, $0) }
    let (left, right) = direction == .left ? (nose, tail) : (tail, nose)
    guard let leftEnd = left.map({ $0 / 4 % width }).max(),
          let rightStart = right.map({ $0 / 4 % width }).min() else { return false }
    return leftEnd < rightStart
}

private func faceFrameInk(_ pixels: [UInt8]) throws -> UInt8 {
    let reds = stride(from: 0, to: pixels.count, by: 4).filter { isNose(pixels, $0) }
    let green = reds.map { pixels[$0 + 1] }.sorted()
    return try #require(green.isEmpty ? nil : green[green.count / 2])
}

/// 블러 강도가 level을 지나는 화면 위치(0~1). 강도가 한쪽으로만 커지는 구간을 이분해 찾음.
private func crossing(_ settings: RenderSettings, level: Double, from a: Double, to b: Double) -> Double {
    var low = a, high = b
    let rising = settings.strength(at: b) > settings.strength(at: a)
    for _ in 0..<60 {
        let middle = (low + high) / 2
        if (settings.strength(at: middle) < level) == rising { low = middle } else { high = middle }
    }
    return (low + high) / 2
}

/// 위에서 row번째 줄에서 불투명과 투명이 바뀌는 첫 열(픽셀 경계).
private func alphaStep(_ pixels: [UInt8], row: Int, width: Int) -> Int? {
    let start = row * width * 4
    let opaque = (0..<width).map { pixels[start + $0 * 4 + 3] >= 128 }
    return (1..<width).first { opaque[$0] != opaque[$0 - 1] }
}

/// 각도가 화면 위치에 고르게 퍼진 시험용 화면. 실제 화면 각도표의 끝 기울기 차이를 빼고 위치를 각도로 바로 되돌림.
private func linear(id: UInt32, _ low: Double, _ high: Double, elevation: ClosedRange<Double>) -> CompiledDisplayAngles {
    CompiledDisplayAngles(id: id, angles: (0..<256).map { low + (high - low) * Double($0) / 255 }, elevation: elevation)
}

@MainActor
@Test func swimmerAndWaveRestoreIdenticalPixelsAfterAnEarlyReversal() async throws {
    try await withSwimSheets { sheets in
        let screen = try Screen(sheets)
        let partial = try screen.draw(.hinge(angle: 35))
        let atMiddle = 90 * 1280
        #expect(partial[atMiddle + 3] == 255)
        #expect(partial[atMiddle + 319 * 4 + 3] == 0)
        #expect(facePoints(.right, in: partial, width: 320))
        #expect(try faceFrameInk(screen.draw(.hinge(angle: 31))) != faceFrameInk(partial))
        #expect(try screen.draw(.hinge(angle: 39)) != partial)
        #expect(try screen.draw(.hinge(angle: 35)) == partial)
        #expect(try screen.draw(.hinge(angle: 35)) == partial)
        let opposite = try screen.draw(.hinge(angle: -35))
        #expect(opposite[atMiddle + 3] == 0)
        #expect(opposite[atMiddle + 319 * 4 + 3] == 255)
        #expect(facePoints(.left, in: opposite, width: 320))
        #expect(try screen.draw(.hinge(angle: -39)) != opposite)
        #expect(try screen.draw(.hinge(angle: -35)) == opposite)
        #expect(try screen.draw(.hinge(angle: -35)) == opposite)
        let clear = try screen.draw(.hinge(angle: 0))
        #expect(clear.allSatisfy { $0 == 0 })
        let full = try screen.draw(.hinge(angle: 65))
        #expect(stride(from: 3, to: full.count, by: 4).allSatisfy { full[$0] == 255 })
        let water = stride(from: 1, to: full.count, by: 4).map { full[$0] }
        #expect(Int(try #require(water.max())) - Int(try #require(water.min())) > 30)
    }
}

@MainActor
@Test func waterKeepsMovingWhileTheHeadIsStillAndCheekyStaysPut() async throws {
    try await withSwimSheets { sheets in
        let screen = try Screen(sheets)
        #expect(try screen.draw(.hinge(angle: 0)).allSatisfy { $0 == 0 })
        #expect(screen.clock.listenerCount == 0)
        let before = try screen.draw(.hinge(angle: 35))
        #expect(screen.clock.listenerCount == 1)
        screen.clock.advance(by: 3)
        let after = try screen.pixels()
        #expect(after != before)
        // 물가 모양과 치키는 고개 값만 따름.
        for i in stride(from: 0, to: before.count, by: 4) {
            #expect(after[i + 3] == before[i + 3])
            if isNose(before, i) || isTail(before, i) { #expect(Array(after[i..<i + 4]) == Array(before[i..<i + 4])) }
        }
        // 마지막 페이지에서 되돌아와 같은 그림으로 이어짐.
        screen.clock.advance(by: 2 * 11 - 3)
        #expect(try screen.pixels() == before)
        screen.overlay.suspend()
        #expect(screen.clock.listenerCount == 0)
    }
}

@MainActor
@Test func theNextWaterPageIsReadOffTheMainThreadWhileThePreviousOneStays() async throws {
    try await withSwimSheets(prefetches: true) { sheets in
        let screen = try Screen(sheets)
        let first = try screen.draw(.hinge(angle: 35))
        // 미리 읽은 다음 페이지는 바로 바뀜.
        for _ in 0..<200 where sheets.cachedWater(index: 1) == nil { try await Task.sleep(for: .milliseconds(10)) }
        screen.clock.advance()
        let second = try screen.pixels()
        #expect(second != first)
        // 미리 읽지 않은 페이지로 건너뛰면 읽는 동안 앞 그림을 두고, 다 읽으면 다시 그림.
        screen.clock.advance(by: 5)
        #expect(try screen.pixels() == second)
        for _ in 0..<200 where try screen.pixels() == second { try await Task.sleep(for: .milliseconds(10)) }
        let later = try screen.pixels()
        #expect(later != second && later != first)
        #expect(Array(stride(from: 3, to: later.count, by: 4).map { later[$0] }) ==
                Array(stride(from: 3, to: first.count, by: 4).map { first[$0] }))
    }
}

@MainActor
@Test func foamEdgeSitsWhereTheBlurReachesTenPercent() async throws {
    try await withSwimSheets { sheets in
        let screen = try Screen(sheets)
        for settings in [RenderSettings.hinge(angle: 35), .hinge(angle: -52, start: 35, full: 75), .hinge(angle: 24)] {
            // 치키가 지나지 않는 맨 윗줄에서 물가 칸의 투명한 반쪽과 불투명한 반쪽이 만나는 곳을 잼.
            let step = try #require(alphaStep(try screen.draw(settings), row: 1, width: 320))
            let edge = crossing(settings, level: SwimStage.edgeLevel, from: 0, to: 1)
            #expect(abs(Double(step) / 320 - edge) < 2.0 / 320)
        }
    }
}

@MainActor
@Test func aPartlyBlurredWholeScreenStillShowsCheekyInItsOwnColors() async throws {
    try await withSwimSheets { sheets in
        let screen = try Screen(sheets)
        let settings = RenderSettings.hinge(angle: 37)
        #expect((0...255).map { settings.strength(at: Double($0) / 255) }.allSatisfy { $0 > 0 })
        let pixels = try screen.draw(settings)
        // 화면 전체가 조금 흐려도 물 그림을 위에 한 겹 더 덮지 않음.
        #expect(stride(from: 0, to: pixels.count, by: 4).contains { pixels[$0] == 255 && pixels[$0 + 2] == 0 })
    }
}

@MainActor
@Test func anUnreadableWaterPageHidesOnlyTheSeaAndTheNextPageBringsItBack() async throws {
    try await withSwimSheets(invalidLastPage: true) { sheets in
        let clock = SwimWaterClock()
        let view = try SpaceTransitionBackdrop(frame: CGRect(x: 0, y: 0, width: 320, height: 180),
                                               settings: .hinge(angle: -35), swimSheets: sheets, swimClock: clock)
        #expect(view.showsSwim)
        clock.advance(by: 11)
        #expect(!view.showsSwim && !view.emergencyCovered && view.submissionCount == 0)
        clock.advance()
        #expect(view.showsSwim && view.submissionCount == 0)
        try view.update(.hinge(angle: -36))
        #expect(view.showsSwim && view.submissionCount == 1)
    }
}

@MainActor
@Test func emergencyCoverDetachesSwimAndMissingArtKeepsBackdropActive() async throws {
    try await withSwimSheets { sheets in
        let frame = CGRect(x: 0, y: 0, width: 320, height: 180)
        let clock = SwimWaterClock()
        let visible = try SpaceTransitionBackdrop(frame: frame, settings: .hinge(angle: -35), swimSheets: sheets,
                                                  swimClock: clock)
        #expect(visible.showsSwim && clock.listenerCount == 1)
        visible.coverForOutputFailure()
        try visible.update(.hinge(angle: 20))
        #expect(!visible.showsSwim && visible.emergencyCovered && clock.listenerCount == 0)
        #expect(visible.layer?.backgroundColor == NSColor.black.cgColor)
        let fallback = try SpaceTransitionBackdrop(frame: frame, settings: .hinge(angle: 0), swimSheets: nil)
        try fallback.update(.hinge(angle: 35))
        #expect(!fallback.showsSwim && !fallback.emergencyCovered)
        #expect(fallback.submissionCount == 1)
    }
}

@MainActor
@Test func lateOrMissingInputKeepsFullNativeBlurEvenWhenTheGazeMaskWasAlreadyFull() async throws {
    try await withSwimSheets { sheets in
        let lookingAway = RenderSettings.hinge(angle: 65)
        let clock = SwimWaterClock()
        let view = try SpaceTransitionBackdrop(frame: CGRect(x: 0, y: 0, width: 320, height: 180),
                                               settings: lookingAway, swimSheets: sheets, swimClock: clock)
        let fullMask = view.maskImage
        #expect(view.showsSwim)
        try view.update(.covered())
        #expect(!view.showsSwim && view.maskImage === fullMask && clock.listenerCount == 0)
        var late = lookingAway
        late.coverage = 1
        try view.update(late)
        #expect(!view.showsSwim && view.maskImage === fullMask && clock.listenerCount == 0)
        try view.update(lookingAway)
        #expect(view.showsSwim && view.maskImage === fullMask)
        #expect(view.submissionCount == 0)
    }
}

@Test func bothEdgesOfWideDisplayKeepSeparateSeasAndAClearCenter() throws {
    let wide = linear(id: 1, -60, 60, elevation: -20...20)
    let layout = CompiledLayout(tables: [wide])
    let settings = RenderSettings.spatial(wide, in: layout, gaze: 0, start: 13, transitionFraction: 0.2, radius: 30)
    let stage = SwimStage(settings: settings, size: CGSize(width: 1600, height: 900))
    #expect(stage.fronts.map(\.side) == [.left, .right])
    #expect(settings.strength(at: 0.5) == 0)
    for front in stage.fronts {
        let x = front.side == .left ? 1 - front.edge : front.edge
        #expect(abs(settings.strength(at: x) - SwimStage.edgeLevel) < 1e-6)
        #expect(front.side == .left ? x < 0.4 : x > 0.6)
    }
}

/// 사용자의 실제 배치처럼 크기와 높이가 다른 두 화면을 붙여 둠. 시선을 돌리며 경계 양쪽 계산을 맞춰 봄.
@Test func oneSeaAndOneCheekyCrossTheBezelBetweenDifferentMonitors() throws {
    let left = linear(id: 1, -40, 0, elevation: -14...(-1))
    let right = linear(id: 2, 0, 30, elevation: -8...10)
    let layout = CompiledLayout(tables: [left, right])
    // 픽셀 비율을 각도 비율에 맞춰 치키 칸이 두 화면에서 같은 정사각형이 되게 함.
    let sizes = [CGSize(width: 1600, height: 520), CGSize(width: 1500, height: 900)]
    var straddles = Set<SwimStage.Side>()
    for gaze in stride(from: -90.0, through: 90, by: 0.25) {
        let stages = zip([left, right], sizes).map { table, size in
            SwimStage(settings: .spatial(table, in: layout, gaze: gaze, start: 13, transitionFraction: 0.25, radius: 30),
                      size: size)
        }
        for side in SwimStage.Side.allCases {
            guard let a = stages[0].fronts.first(where: { $0.side == side }),
                  let b = stages[1].fronts.first(where: { $0.side == side }) else { continue }
            // 왼쪽 화면의 오른쪽 끝과 오른쪽 화면의 왼쪽 끝은 물가에서 같은 깊이임.
            let depthA = side == .right ? 1 - a.edge : -a.edge
            let depthB = side == .right ? -b.edge : 1 - b.edge
            #expect(abs(depthA - depthB) < 1e-9)
            #expect(a.travel == b.travel)
            guard let actorA = a.actor, let actorB = b.actor else { continue }
            straddles.insert(side)
            func angle(_ actor: SwimStage.Actor, _ low: Double, _ width: Double) -> Double {
                low - gaze + width * (side == .right ? actor.x : 1 - actor.x)
            }
            #expect(abs(angle(actorA, -40, 40) - angle(actorB, 0, 30)) < 1e-9)
            #expect(abs(actorA.size * 40 - actorB.size * 30) < 1e-9)
            #expect(abs((-14 + actorA.y * 13) - (-8 + actorB.y * 18)) < 1e-9)
        }
    }
    #expect(straddles == [.left, .right])
}
