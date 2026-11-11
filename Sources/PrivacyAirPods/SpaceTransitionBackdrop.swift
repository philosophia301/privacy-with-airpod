import AppKit
import PrivacyBackdrop

/// 본체와 Lab의 동일한 색조 없는 backdrop 필터를 사용함.
@MainActor
final class SpaceTransitionBackdrop: NSView {
    private let backdrop: CALayer
    private var lastMask: Data
    private var lastSettings: RenderSettings
    private(set) var maskImage: CGImage
    private(set) var submissionCount = 0
    private(set) var emergencyCovered = false

    init(frame: CGRect, settings: RenderSettings) throws {
        let data = try Self.maskData(settings)
        let image = try Self.image(data)
        var failure: NSError?
        guard let surface = PBBackdrop(true, settings.radius, image, &failure) else {
            throw failure ?? OutputError.unavailable
        }
        backdrop = surface
        lastMask = data; maskImage = image; lastSettings = settings
        super.init(frame: frame)
        wantsLayer = true
        surface.frame = bounds
        layer?.addSublayer(surface)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func update(_ settings: RenderSettings) throws {
        guard !emergencyCovered, settings != lastSettings else { return }
        let data = try Self.maskData(settings)
        if data == lastMask, settings.radius == lastSettings.radius {
            lastSettings = settings
            return
        }
        let image = data == lastMask ? maskImage : try Self.image(data)
        var failure: NSError?
        guard PBUpdateMask(backdrop, image, settings.radius, &failure) else {
            throw failure ?? OutputError.unavailable
        }
        lastMask = data; maskImage = image; lastSettings = settings
        submissionCount += 1
    }

    /// 화면 처리 실패에만 기존 비상 가림 정책을 적용함. 입력 탈착은 이 경로를 사용하지 않음.
    func coverForOutputFailure() {
        emergencyCovered = true
        CATransaction.begin(); CATransaction.setDisableActions(true)
        backdrop.filters = nil
        backdrop.removeFromSuperlayer()
        layer?.backgroundColor = NSColor.black.cgColor
        CATransaction.commit()
    }

    private static func maskData(_ settings: RenderSettings) throws -> Data {
        guard settings.radius.isFinite, settings.radius >= 0 else { throw OutputError.invalidSettings }
        var bytes = [UInt8](repeating: 255, count: 256 * 4)
        for x in 0..<256 {
            let strength = settings.strength(at: Double(x) / 255)
            guard strength.isFinite, (0...1).contains(strength) else { throw OutputError.invalidSettings }
            bytes[x * 4 + 3] = UInt8((strength * 255).rounded())
        }
        return Data(bytes)
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
