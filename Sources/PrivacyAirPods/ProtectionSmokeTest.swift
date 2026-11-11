import AppKit

/// 배포 산출물 확인용(`--smoke-test`). 서명된 실행 파일이 비공개 화면 API로 가림 창을 열고,
/// 마스크를 갱신하고, 닫는지 확인함. AirPods 입력과 사용자 설정은 사용하지 않음.
enum ProtectionSmokeTest {
    @MainActor static func run() async -> Bool {
        guard let screen = NSScreen.screens.first else { return report("화면 없음") }
        let cover = ScreenCover()
        var failure: String?
        cover.onFailure = { failure = $0 }
        defer { cover.stop() }
        do {
            try await cover.start(settings: [screen.displayID: .covered()])
        } catch {
            return report("가림 시작 실패: \(error.localizedDescription)")
        }
        guard let panel = cover.outputWindows.first, cover.outputWindows.count == 1, panel.isVisible else {
            return report("가림 창이 표시되지 않음")
        }
        cover.update([screen.displayID: .hinge(angle: 35)])
        guard failure == nil, cover.maskUpdateCount == 1 else {
            return report("마스크 갱신 실패: \(failure ?? "제출 \(cover.maskUpdateCount)회")")
        }
        cover.stop()
        guard !panel.isVisible, cover.outputWindows.isEmpty else { return report("가림 창이 닫히지 않음") }
        print("smoke-test OK display=\(screen.displayID)")
        return true
    }

    private static func report(_ message: String) -> Bool {
        FileHandle.standardError.write(Data("smoke-test FAIL \(message)\n".utf8))
        return false
    }
}
