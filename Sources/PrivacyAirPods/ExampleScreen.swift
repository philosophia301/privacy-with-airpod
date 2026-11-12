import AppKit
import CoreImage

/// 설정 미리보기에만 쓰는 앱 자체 예제 화면. 실제 화면 내용은 사용하지 않음.
enum ExampleScreen {
    @MainActor static func make() -> CIImage {
        let size = NSSize(width: 800, height: 420)
        let image = NSImage(size: size)
        image.lockFocus()
        NSColor(calibratedRed: 0.09, green: 0.12, blue: 0.18, alpha: 1).setFill()
        NSBezierPath(rect: NSRect(origin: .zero, size: size)).fill()
        let heading: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 26, weight: .semibold), .foregroundColor: NSColor.white]
        ("PRIVACY / 미리보기" as NSString).draw(at: NSPoint(x: 28, y: 360), withAttributes: heading)
        for column in 0..<3 {
            let x = CGFloat(28 + column * 254)
            NSColor(calibratedWhite: 0.20 + CGFloat(column) * 0.04, alpha: 1).setFill()
            NSBezierPath(roundedRect: NSRect(x: x, y: 45, width: 235, height: 285), xRadius: 16, yRadius: 16).fill()
            let titles = ["오늘 할 일", "프로젝트 메모", "주간 일정"]
            (titles[column] as NSString).draw(at: NSPoint(x: x + 18, y: 285), withAttributes: [.font: NSFont.systemFont(ofSize: 20, weight: .medium), .foregroundColor: NSColor.white])
            for row in 0..<6 {
                ("\(row + 1). 예제 내용 확인하기" as NSString).draw(at: NSPoint(x: x + 18, y: CGFloat(246 - row * 32)), withAttributes: [.font: NSFont.systemFont(ofSize: 15), .foregroundColor: NSColor(calibratedWhite: 0.9, alpha: 1)])
            }
        }
        image.unlockFocus()
        var rect = NSRect(origin: .zero, size: size)
        return CIImage(cgImage: image.cgImage(forProposedRect: &rect, context: nil, hints: nil)!)
    }
}
