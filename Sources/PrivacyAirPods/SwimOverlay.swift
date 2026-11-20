import AppKit
import ImageIO

/// TIFF의 각 페이지에는 물가, 깊은 물, 뒤집지 않은 치키가 따로 있음.
///
/// 물은 고개와 무관하게 시계로 넘기므로, 다음 물 페이지를 메인 스레드 밖에서 미리 읽어 둠. 페이지를 읽는 일은
/// 모두 한 줄(queue)에서 하고, 메인 스레드가 바로 필요한 그림(처음 그림, 치키 자세)만 그 줄을 기다림.
@MainActor
final class SwimSheets {
    /// 한 페이지의 물 그림. 만든 뒤 바뀌지 않음.
    final class Water: @unchecked Sendable {
        /// 깊은 물 그림 끝에 이어 반복할 구간의 시작 깊이. 물가 쪽 밝은 물을 빼고 바다 쪽 끝부분만 씀.
        static let farStart = 0.55
        /// 반복 구간 끝을 처음과 섞는 폭(깊이). 이음매가 한 줄로 보이지 않게 함.
        static let blendWidth = 0.15

        let coast: CGImage
        /// 끝부분을 반복 구간 처음과 섞은 깊은 물. 끝 열이 far 첫 열 바로 앞 열과 같아 이어짐.
        let deep: CGImage
        /// 끝과 처음이 맞물려 몇 번이고 이어 붙일 수 있는 바다 쪽 물.
        let far: CGImage

        init?(page image: CGImage) {
            guard let unit = Self.unit(of: image),
                  let coast = image.cropping(to: CGRect(x: 0, y: 0, width: 6 * unit, height: 14 * unit)),
                  let source = image.cropping(to: CGRect(x: 6 * unit, y: 0, width: 22 * unit, height: 14 * unit)),
                  let (deep, far) = Self.tiled(source)
            else { return nil }
            self.coast = coast
            self.deep = deep
            self.far = far
        }

        static func actor(page image: CGImage) -> CGImage? {
            guard let unit = unit(of: image) else { return nil }
            return image.cropping(to: CGRect(x: 28 * unit, y: 0, width: 12 * unit, height: 12 * unit))
        }

        private static func unit(of image: CGImage) -> Int? {
            let unit = image.width / 40
            return unit > 0 && image.width == 40 * unit && image.height == 14 * unit ? unit : nil
        }

        /// 바다 쪽 반복 물(far)과, 끝이 far 첫 열로 이어지는 깊은 물(deep)을 만듦.
        ///
        /// 원본 깊은 물은 물가에서 멀수록 어두워짐. far는 farStart부터 끝까지를 끝 열 밝기로 고르게 낮춰 반복해도 띠가
        /// 생기지 않게 하고, 끝 blendWidth 구간을 한 주기 앞의 열과 서서히 섞어 끝과 처음이 맞물리게 함. 거울로 뒤집어
        /// 잇는 방식보다 대칭 무늬가 덜 드러남. deep의 끝도 같은 방식으로 섞어 마지막 열이 far 첫 열 바로 앞 열이 됨.
        private static func tiled(_ deep: CGImage) -> (CGImage, CGImage)? {
            let width = deep.width, height = deep.height
            let span = 1 - SwimStage.shore
            let start = Int((Double(width) * (farStart - SwimStage.shore) / span).rounded())
            let period = width - start
            let blend = min(start, period - 1, Int((Double(width) * blendWidth / span).rounded()))
            guard period > 1, blend > 0 else { return nil }
            // 물가 칸, 치키와 같은 색 공간에 그대로 둬야 이음매에서 색이 달라지지 않음.
            let space = deep.colorSpace.flatMap { $0.model == .rgb ? $0 : nil } ?? CGColorSpaceCreateDeviceRGB()
            let ramp = (0..<blend).map { UInt8((Double($0 + 1) / Double(blend) * 255).rounded()) }
            func canvas(_ width: Int, _ height: Int) -> CGContext? {
                CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                          space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            }
            guard let rampProvider = CGDataProvider(data: Data(ramp) as CFData),
                  let mask = CGImage(width: blend, height: 1, bitsPerComponent: 8, bitsPerPixel: 8, bytesPerRow: blend,
                                     space: CGColorSpaceCreateDeviceGray(), bitmapInfo: [], provider: rampProvider,
                                     decode: nil, shouldInterpolate: true, intent: .defaultIntent),
                  let level = Self.leveled(deep, from: start - blend, space: space),
                  let deepContext = canvas(width, height), let farContext = canvas(period, height)
            else { return nil }
            // level의 0열은 원본 start - blend열임. 끝 구간 각 열에 한 주기 앞 열을 겹치는 자리에 놓음.
            let tall = CGFloat(height)
            deepContext.draw(deep, in: CGRect(x: 0, y: 0, width: width, height: height))
            deepContext.clip(to: CGRect(x: width - blend, y: 0, width: blend, height: height), mask: mask)
            deepContext.draw(level, in: CGRect(x: CGFloat(width - blend), y: 0, width: CGFloat(level.width), height: tall))
            farContext.draw(level, in: CGRect(x: -CGFloat(blend), y: 0, width: CGFloat(level.width), height: tall))
            farContext.clip(to: CGRect(x: period - blend, y: 0, width: blend, height: height), mask: mask)
            farContext.draw(level, in: CGRect(x: CGFloat(period - blend), y: 0, width: CGFloat(level.width), height: tall))
            guard let blended = deepContext.makeImage(), let far = farContext.makeImage() else { return nil }
            return (blended, far)
        }

        /// 원본 from열부터 끝까지를 잘라, 열마다 평균 색을 끝 열 근처 평균에 맞춰 낮춤. 물결 무늬는 남기고 밝기 기울기만 뺌.
        private static func leveled(_ deep: CGImage, from: Int, space: CGColorSpace) -> CGImage? {
            let width = deep.width - from, height = deep.height
            guard width > 0,
                  let strip = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                        bytesPerRow: width * 4, space: space,
                                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
                  let row = CGContext(data: nil, width: width, height: 1, bitsPerComponent: 8, bytesPerRow: width * 4,
                                      space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            else { return nil }
            strip.draw(deep, in: CGRect(x: -from, y: 0, width: deep.width, height: height))
            guard let raw = strip.makeImage() else { return nil }
            // 한 줄로 줄여 열 평균을 얻음.
            row.interpolationQuality = .high
            row.draw(raw, in: CGRect(x: 0, y: 0, width: width, height: 1))
            guard let data = row.data else { return nil }
            let bytes = data.assumingMemoryBound(to: UInt8.self)
            let radius = 24, tail = min(16, width)
            var gains = [UInt8](repeating: 255, count: width * 4)
            for channel in 0..<3 {
                let means = (0..<width).map { Double(bytes[$0 * 4 + channel]) }
                var prefix = [0.0]
                for value in means { prefix.append(prefix[prefix.count - 1] + value) }
                let target = (prefix[width] - prefix[width - tail]) / Double(tail)
                for x in 0..<width {
                    let low = max(0, x - radius), high = min(width, x + radius + 1)
                    let mean = (prefix[high] - prefix[low]) / Double(high - low)
                    gains[x * 4 + channel] = UInt8((min(1, mean > 0 ? target / mean : 1) * 255).rounded())
                }
            }
            guard let provider = CGDataProvider(data: Data(gains) as CFData),
                  let gain = CGImage(width: width, height: 1, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
                                     space: space, bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                                     provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
            else { return nil }
            strip.setBlendMode(.multiply)
            strip.interpolationQuality = .none
            strip.draw(gain, in: CGRect(x: 0, y: 0, width: width, height: height))
            return strip.makeImage()
        }
    }

    /// 그림 파일을 읽는 곳. 물은 queue에서만, 치키는 메인 스레드에서만 읽고 각자 따로 연 파일을 써서
    /// 고개를 돌릴 때 치키 자세가 물 미리 읽기를 기다리지 않음. 고정된 값과 스레드 안전한 캐시만 가짐.
    private final class Reader: @unchecked Sendable {
        let count: Int
        private let waterSource: CGImageSource
        private let actorSource: CGImageSource
        private let queue = DispatchQueue(label: "PrivacyAirPods.SwimSheets", qos: .userInitiated)
        private let waters = NSCache<NSNumber, Water>()
        private let actors = NSCache<NSNumber, CGImage>()

        init?(url: URL) {
            let options = [kCGImageSourceShouldCache: false] as CFDictionary
            guard let waterSource = CGImageSourceCreateWithURL(url as CFURL, options),
                  let actorSource = CGImageSourceCreateWithURL(url as CFURL, options) else { return nil }
            self.waterSource = waterSource
            self.actorSource = actorSource
            count = CGImageSourceGetCount(waterSource)
            // 모든 화면이 같은 페이지를 공유함. 앞뒤 물 몇 장과 양쪽 치키 자세만 두고 전체를 메모리에 두지 않음.
            waters.countLimit = 6
            actors.countLimit = 6
        }

        func cachedWater(_ index: Int) -> Water? { waters.object(forKey: NSNumber(value: index)) }

        func water(_ index: Int) -> Water? {
            cachedWater(index) ?? queue.sync { readWater(index) }
        }

        /// 메인 스레드에서만 부름.
        func actor(_ index: Int) -> CGImage? {
            if let cached = actors.object(forKey: NSNumber(value: index)) { return cached }
            guard let page = page(index, from: actorSource), let actor = Water.actor(page: page) else { return nil }
            actors.setObject(actor, forKey: NSNumber(value: index))
            return actor
        }

        func prefetch(_ index: Int, done: @escaping @Sendable (Bool) -> Void) {
            queue.async { [self] in done(readWater(index) != nil) }
        }

        /// queue 안에서만 부름.
        private func readWater(_ index: Int) -> Water? {
            if let cached = cachedWater(index) { return cached }
            guard let page = page(index, from: waterSource), let water = Water(page: page) else { return nil }
            waters.setObject(water, forKey: NSNumber(value: index))
            return water
        }

        private func page(_ index: Int, from source: CGImageSource) -> CGImage? {
            CGImageSourceCreateImageAtIndex(source, index, [kCGImageSourceShouldCacheImmediately: true] as CFDictionary)
        }
    }

    static let bundled = Bundle.main.resourceURL.flatMap {
        SwimSheets(directory: $0.appendingPathComponent("Swim", isDirectory: true))
    }
    var count: Int { reader.count }
    /// false면 모든 물 페이지를 그 자리에서 읽음. 시험이 페이지 순서를 그대로 확인할 때 씀.
    let prefetches: Bool
    private let reader: Reader
    private var waiting = [Int: [@MainActor @Sendable (Bool) -> Void]]()

    init?(directory: URL, prefetches: Bool = true) {
        let url = directory.appendingPathComponent("swim.tiff")
        guard FileManager.default.fileExists(atPath: url.path), let reader = Reader(url: url), reader.count >= 2
        else { return nil }
        self.reader = reader
        self.prefetches = prefetches
        guard water(index: 0) != nil, actor(index: 0) != nil else { return nil }
    }

    func cachedWater(index: Int) -> Water? { reader.cachedWater(clamp(index)) }
    func water(index: Int) -> Water? { reader.water(clamp(index)) }
    func actor(index: Int) -> CGImage? { reader.actor(clamp(index)) }

    /// 물 페이지를 메인 스레드 밖에서 읽고, 끝나면 메인 스레드에서 done을 부름. 같은 페이지 요청은 한 번만 읽음.
    func prefetchWater(index: Int, done: @escaping @MainActor @Sendable (Bool) -> Void) {
        let index = clamp(index)
        guard waiting[index] == nil else { waiting[index]?.append(done); return }
        waiting[index] = [done]
        reader.prefetch(index) { [weak self] ready in
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    for done in self?.waiting.removeValue(forKey: index) ?? [] { done(ready) }
                }
            }
        }
    }

    private func clamp(_ index: Int) -> Int { min(count - 1, max(0, index)) }
}

/// 물 무늬 페이지를 고개와 무관하게 넘기는 시계. 모든 화면이 같은 시계를 들어 경계 양쪽의 물이 같이 움직임.
/// 물이 보이는 화면이 하나도 없으면 멈춤. 시험은 타이머 없는 시계를 advance로 넘김.
@MainActor
final class SwimWaterClock {
    private final class Listener {
        weak var overlay: SwimOverlay?
        init(_ overlay: SwimOverlay) { self.overlay = overlay }
    }

    static let shared = SwimWaterClock(automatic: true)
    /// 페이지를 넘기는 빠르기. 원본 물 영상(24fps) 2초를 약 3.4초에 정방향으로 지나고 거꾸로 돌아옴.
    static let pagesPerSecond = 14.0

    private let automatic: Bool
    private var step = 0
    private var timer: Timer?
    private var listeners = [ObjectIdentifier: Listener]()

    init(automatic: Bool = false) {
        self.automatic = automatic
    }

    /// 지금(ahead만큼 뒤) 보일 페이지. 끝에서 되돌아와 이음매 없이 반복함.
    func page(count: Int, ahead: Int = 0) -> Int {
        guard count > 1 else { return 0 }
        let cycle = 2 * (count - 1)
        let phase = (step + max(0, ahead)) % cycle
        return phase < count ? phase : cycle - phase
    }

    func advance(by steps: Int = 1) {
        step = (step + max(0, steps)) % (1 << 30)
        let current = listeners.values.compactMap(\.overlay)
        for overlay in current { overlay.waterDidAdvance() }
        listeners = listeners.filter { $0.value.overlay != nil }
        if listeners.isEmpty { stopTimer() }
    }

    func listen(_ overlay: SwimOverlay) {
        listeners[ObjectIdentifier(overlay)] = Listener(overlay)
        guard automatic, timer == nil else { return }
        // 메인 run loop의 common 모드에 넣어 설정 창 슬라이더를 끄는 동안에도 물이 움직임.
        let timer = Timer(timeInterval: 1 / Self.pagesPerSecond, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.advance() }
        }
        timer.tolerance = 0.2 / Self.pagesPerSecond
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func ignore(_ overlay: SwimOverlay) {
        listeners[ObjectIdentifier(overlay)] = nil
        if listeners.isEmpty { stopTimer() }
    }

    var listenerCount: Int { listeners.values.filter { $0.overlay != nil }.count }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }
}

@MainActor
final class SwimOverlay {
    /// 반복 구간 하나의 폭(깊이). 그림 한 장 안의 farStart부터 끝까지와 같음.
    private static var farWidth: Double { 1 - SwimSheets.Water.farStart }
    /// 고개를 멈춰도 치키가 물에 떠 있는 느낌을 주는 위아래 흔들림. 모든 화면이 같은 시각 기준을 써서 경계에 걸친 치키가 같이 움직임.
    private static let bobEpoch = CACurrentMediaTime()
    private static let bobPeriod = 2.4
    private static let bobAmplitude = 0.03

    @MainActor
    private final class Bank {
        let water = CALayer()
        let coast = CALayer()
        let deep = CALayer()
        let far = (0..<4).map { _ in CALayer() }
        let actor = CALayer()
        private let side: SwimStage.Side
        private var bobCell: CGFloat = 0

        init(side: SwimStage.Side) {
            self.side = side
            // 원본은 왼쪽을 봄. 바다가 들어오는 쪽으로 방향을 정해 복귀 중에도 유지함.
            let facing = CGAffineTransform(scaleX: side == .left ? -1 : 1, y: 1)
            water.setAffineTransform(facing)
            actor.setAffineTransform(facing)
            water.addSublayer(deep)
            for layer in far { water.addSublayer(layer) }
            water.addSublayer(coast)
            actor.contentsGravity = .resizeAspect
        }

        /// 기준틀에서 바다는 오른쪽에서 들어옴. 물가 칸, 깊은 물, 반복 구간 순으로 바다 쪽으로 이어짐.
        func layoutWater(edge: Double, size: CGSize) {
            let w = size.width
            let shore = SwimStage.shore
            water.bounds = CGRect(origin: .zero, size: size)
            water.position = CGPoint(x: w / 2, y: size.height / 2)
            place(coast, from: edge - shore, to: edge + shore, size: size)
            // 이음매마다 같은 물 그림의 이웃 열을 한 픽셀씩 더 그려, 두 층 끝이 한 픽셀 안에서 소수점으로 만나도 틈이 없음.
            let overlap = 1 / w
            place(deep, from: edge + shore - overlap, to: edge + 1 + overlap, size: size)
            let farWidth = SwimOverlay.farWidth
            let first = max(0, Int(((-(edge + 1)) / farWidth).rounded(.down)))
            for (offset, layer) in far.enumerated() {
                let index = first + offset
                let start = edge + 1 + Double(index) * farWidth
                place(layer, from: start - overlap, to: start + farWidth + overlap, size: size)
            }
        }

        func paint(_ water: SwimSheets.Water) {
            coast.contents = water.coast
            deep.contents = water.deep
            for layer in far { layer.contents = water.far }
        }

        func placeActor(_ actor: SwimStage.Actor, image: CGImage, size: CGSize) {
            let w = size.width, h = size.height
            let cell = actor.size * w
            let x = side == .left ? (1 - actor.x) * w : actor.x * w
            self.actor.bounds = CGRect(x: 0, y: 0, width: cell, height: cell)
            self.actor.position = CGPoint(x: x, y: actor.y * h)
            self.actor.contents = image
            guard abs(cell - bobCell) > 0.5 else { return }
            bobCell = cell
            let bob = CABasicAnimation(keyPath: "position.y")
            bob.isAdditive = true
            bob.fromValue = -SwimOverlay.bobAmplitude * cell
            bob.toValue = SwimOverlay.bobAmplitude * cell
            bob.duration = SwimOverlay.bobPeriod / 2
            bob.autoreverses = true
            bob.repeatCount = .infinity
            bob.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            bob.beginTime = SwimOverlay.bobEpoch
            self.actor.add(bob, forKey: "bob")
        }

        /// 기준틀의 [from, to] 구간에 층을 놓음. 화면 밖이면 숨김.
        private func place(_ layer: CALayer, from: Double, to: Double, size: CGSize) {
            layer.isHidden = to <= 0 || from >= 1 || to <= from
            guard !layer.isHidden else { return }
            layer.frame = CGRect(x: from * size.width, y: 0, width: (to - from) * size.width, height: size.height)
        }
    }

    let layer = CALayer()
    private let sheets: SwimSheets
    private let clock: SwimWaterClock
    private let banks = SwimStage.Side.allCases.map { Bank(side: $0) }
    private var stage: SwimStage?
    private var size = CGSize.zero
    /// 마지막으로 그릴 때의 시계 페이지와, 실제로 화면에 올라간 물 그림.
    private var waterPage: Int?
    private var shown: (page: Int, water: SwimSheets.Water)?
    /// 미리 읽기에 실패한 페이지. 시계가 다른 페이지로 넘어가면 다시 시도함.
    private var failedPage: Int?

    init?(sheets: SwimSheets? = .bundled, clock: SwimWaterClock = .shared) {
        guard let sheets else { return nil }
        self.sheets = sheets
        self.clock = clock
        layer.masksToBounds = true
        for bank in banks { layer.addSublayer(bank.water) }
        for bank in banks { layer.addSublayer(bank.actor) }
    }

    /// 전체 블러 쪽 가림(늦은 입력)은 바다를 흐리게 하고 바다 자리는 시선 기준 설정에서 정함.
    func update(settings: RenderSettings, size: CGSize) {
        let cover = settings.coverage.isFinite ? min(1, max(0, settings.coverage)) : 1
        let opacity: Float = if case .covered = settings.field { 0 } else { Float(1 - cover) }
        let stage = opacity > 0 ? SwimStage(settings: settings, size: size) : nil
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }
        layer.opacity = opacity
        guard stage != self.stage || size != self.size else { return }
        self.stage = stage
        self.size = size
        layer.frame = CGRect(origin: .zero, size: size)
        draw()
    }

    /// 화면에서 뗄 때 씀. 물 시계를 놓고, 다음 update에서 다시 그림.
    func suspend() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        stage = nil
        size = .zero
        layer.isHidden = true
        clock.ignore(self)
        CATransaction.commit()
    }

    fileprivate func waterDidAdvance() {
        guard clock.page(count: sheets.count) != waterPage else { return }
        failedPage = nil
        redraw()
    }

    private func waterArrived(_ page: Int, ready: Bool) {
        if !ready { failedPage = page }
        guard page == waterPage else { return }
        redraw()
    }

    private func redraw() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        draw()
        CATransaction.commit()
    }

    private func draw() {
        guard let stage, !stage.fronts.isEmpty, size.width > 0, size.height > 0 else {
            layer.isHidden = true
            clock.ignore(self)
            waterPage = nil
            return
        }
        let wet = stage.fronts.contains(where: \.showsWater)
        if wet { clock.listen(self) } else { clock.ignore(self) }
        waterPage = wet ? clock.page(count: sheets.count) : nil
        let water = waterPage.flatMap(water(at:))
        var drawn = !wet || water != nil
        for bank in banks {
            bank.water.isHidden = true
            bank.actor.isHidden = true
        }
        for front in stage.fronts where drawn {
            let bank = banks[front.side.rawValue]
            if front.showsWater, let water {
                bank.layoutWater(edge: front.edge, size: size)
                bank.paint(water)
                bank.water.isHidden = false
            }
            if let actor = front.actor {
                let pose = Int((front.travel * Double(sheets.count - 1)).rounded())
                guard let image = sheets.actor(index: pose) else { drawn = false; break }
                bank.placeActor(actor, image: image, size: size)
                bank.actor.isHidden = false
            }
        }
        // 그림 한 장이라도 읽지 못하면 반쪽 바다를 남기지 않고 원래 블러만 보임. 다음 페이지나 자세에서 다시 시도함.
        layer.isHidden = !drawn
        if wet, sheets.prefetches {
            let next = clock.page(count: sheets.count, ahead: 1)
            if sheets.cachedWater(index: next) == nil { sheets.prefetchWater(index: next) { _ in } }
        }
    }

    /// 시계 페이지의 물. 아직 읽지 못했으면 읽는 동안 앞 페이지를 그대로 두고, 다 읽으면 다시 그림.
    private func water(at page: Int) -> SwimSheets.Water? {
        if let ready = sheets.cachedWater(index: page) {
            shown = (page, ready)
            return ready
        }
        guard failedPage != page else { return nil }
        if sheets.prefetches, let shown {
            sheets.prefetchWater(index: page) { [weak self] ready in self?.waterArrived(page, ready: ready) }
            return shown.water
        }
        guard let water = sheets.water(index: page) else { return nil }
        shown = (page, water)
        return water
    }
}
