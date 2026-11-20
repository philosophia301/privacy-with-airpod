import AppKit
import PrivacyBackdrop

/// 본체와 Lab의 동일한 색조 없는 backdrop 필터를 사용함.
@MainActor
final class SpaceTransitionBackdrop: NSView {
    private let backdrop: CALayer
    private let swim: SwimOverlay?
    private var lastMask: Data
    private var lastSettings: RenderSettings
    private(set) var maskImage: CGImage
    private(set) var submissionCount = 0
    private(set) var emergencyCovered = false
    var showsSwim: Bool {
        guard let layer = swim?.layer else { return false }
        return layer.superlayer != nil && !layer.isHidden && layer.opacity > 0
    }

    init(frame: CGRect, settings: RenderSettings, swimSheets: SwimSheets? = .bundled,
         swimClock: SwimWaterClock = .shared) throws {
        guard let data = settings.maskRGBA() else { throw OutputError.invalidSettings }
        let image = try Self.image(data)
        var failure: NSError?
        guard let surface = PBBackdrop(true, settings.radius, image, &failure) else {
            throw failure ?? OutputError.unavailable
        }
        backdrop = surface
        swim = SwimOverlay(sheets: swimSheets, clock: swimClock)
        lastMask = data; maskImage = image; lastSettings = settings
        super.init(frame: frame)
        wantsLayer = true
        surface.frame = bounds
        layer?.addSublayer(surface)
        if let swim {
            layer?.addSublayer(swim.layer)
            swim.update(settings: settings, size: bounds.size)
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func layout() {
        super.layout()
        guard !emergencyCovered else { return }
        backdrop.frame = bounds
        swim?.update(settings: lastSettings, size: bounds.size)
    }

    func update(_ settings: RenderSettings) throws {
        guard !emergencyCovered, settings != lastSettings else { return }
        guard let data = settings.maskRGBA() else { throw OutputError.invalidSettings }
        if data != lastMask || settings.radius != lastSettings.radius {
            let image = data == lastMask ? maskImage : try Self.image(data)
            var failure: NSError?
            guard PBUpdateMask(backdrop, image, settings.radius, &failure) else {
                throw failure ?? OutputError.unavailable
            }
            lastMask = data
            maskImage = image
            submissionCount += 1
        }
        lastSettings = settings
        swim?.update(settings: settings, size: bounds.size)
    }

    /// 화면 처리 실패에만 기존 비상 가림 정책을 적용함. 입력 탈착은 이 경로를 사용하지 않음.
    func coverForOutputFailure() {
        emergencyCovered = true
        CATransaction.begin(); CATransaction.setDisableActions(true)
        backdrop.filters = nil
        backdrop.removeFromSuperlayer()
        swim?.suspend()
        swim?.layer.removeFromSuperlayer()
        layer?.backgroundColor = NSColor.black.cgColor
        CATransaction.commit()
    }

    private static func image(_ data: Data) throws -> CGImage {
        guard let provider = CGDataProvider(data: data as CFData),
              let image = CGImage(width: 256, height: 1, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: 1024,
                  space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue),
                  provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent) else {
            throw OutputError.unavailable
        }
        return image
    }

    enum OutputError: LocalizedError {
        case invalidSettings, unavailable
        var errorDescription: String? {
            switch self {
            case .invalidSettings: "유효하지 않은 블러 설정입니다."
            case .unavailable: "화면 블러를 준비할 수 없습니다."
            }
        }
    }
}
