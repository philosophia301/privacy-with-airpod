import Foundation
import Testing
import Sparkle
@testable import PrivacyAirPods

/// 실제 Sparkle이 appcast를 읽고 critical 여부를 판정해 설정 화면 차단 상태까지 오는 흐름.
/// 대역은 배포 서버(127.0.0.1의 appcast)와 업데이트 창(응답만 하는 user driver)뿐임.
@MainActor
struct RequiredUpdateFlowTests {
    /// 설치된 앱이 빌드 3(0.1.2)일 때의 appcast별 결과.
    enum Feed: CaseIterable, CustomTestStringConvertible {
        case criticalForInstalledBuild, criticalOnlyForOlderBuilds, alreadyLatest, unreachable

        var testDescription: String { "\(self)" }

        /// nil이면 서버를 띄우지 않아 연결이 거부되는 경우가 됨.
        var newest: (build: Int, version: String, requiredBelow: Int?)? {
            switch self {
            case .criticalForInstalledBuild: (4, "0.1.3", 4)
            case .criticalOnlyForOlderBuilds: (4, "0.1.3", 3)
            case .alreadyLatest: (3, "0.1.2", nil)
            case .unreachable: nil
            }
        }

        var expectedRequiredVersion: String? { self == .criticalForInstalledBuild ? "0.1.3" : nil }
        /// 판정이 실제로 appcast를 읽고 나온 것인지 구분함.
        var expectedOffer: String? { newest.flatMap { $0.build > 3 ? $0.version : nil } }
    }

    @Test(arguments: Feed.allCases)
    func installedAppBlocksSettingsOnlyWhenAppcastRequiresItsBuild(feed: Feed) async throws {
        let fixture = try await UpdateFixture(installedBuild: 3, installedVersion: "0.1.2", newest: feed.newest)
        defer { fixture.remove() }
        let driver = AnsweringUserDriver()
        let updater = SparkleUpdater(hostBundle: fixture.bundle, userDriver: driver)

        try await waitUntil { !updater.updater.sessionInProgress }

        #expect(updater.state.requiredVersion == feed.expectedRequiredVersion)
        #expect(driver.offeredVersion == feed.expectedOffer)
    }

    @Test func updateButtonOpensSparkleCheckForTheSameUpdater() async throws {
        let fixture = try await UpdateFixture(installedBuild: 3, installedVersion: "0.1.2", newest: (4, "0.1.3", 4))
        defer { fixture.remove() }
        let driver = AnsweringUserDriver()
        let updater = SparkleUpdater(hostBundle: fixture.bundle, userDriver: driver)
        try await waitUntil { !updater.updater.sessionInProgress }
        #expect(driver.userInitiatedChecks == 0)

        updater.state.checkForUpdates()

        try await waitUntil { !updater.updater.sessionInProgress }
        #expect(driver.userInitiatedChecks == 1)
        #expect(updater.state.requiredVersion == "0.1.3")
    }

    private func waitUntil(_ done: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(10)
        // 확인 세션은 시작 직후 다음 run loop에서 열리므로 한 번은 양보함.
        try await Task.sleep(for: .milliseconds(50))
        while !done() {
            try #require(Date() < deadline, "Sparkle 업데이트 확인이 10초 안에 끝나지 않음")
            try await Task.sleep(for: .milliseconds(20))
        }
    }
}

/// 설치된 앱 번들을 임시 폴더에, 배포 appcast를 로컬 서버에 둠. Sparkle이 남긴 사용자 기본값도 지움.
private struct UpdateFixture {
    static let bundleID = "io.enjoy301.PrivacyAirPods.update-tests"
    let root: URL
    let bundle: Bundle
    let server: LocalFeedServer?

    init(installedBuild: Int, installedVersion: String,
         newest: (build: Int, version: String, requiredBelow: Int?)?) async throws {
        UserDefaults.standard.removePersistentDomain(forName: Self.bundleID)
        root = FileManager.default.temporaryDirectory.appendingPathComponent("update-flow-\(UUID().uuidString)")
        let contents = root.appendingPathComponent("Installed.app/Contents")
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        server = try newest.map { try LocalFeedServer(body: Data(Self.appcast(newest: $0).utf8)) }
        // 서버가 없으면 닫힌 포트로 보내 오프라인과 같은 연결 실패를 만듦.
        let feed = try await server?.start() ?? URL(string: "http://127.0.0.1:9/appcast.xml")!
        let info: [String: Any] = [
            "CFBundleIdentifier": Self.bundleID,
            "CFBundleName": "Privacy AirPods",
            "CFBundleExecutable": "PrivacyAirPods",
            "CFBundlePackageType": "APPL",
            "CFBundleShortVersionString": installedVersion,
            "CFBundleVersion": String(installedBuild),
            "SUFeedURL": feed.absoluteString,
            "SUPublicEDKey": "1H9M8qzGlyp+eqmmS2hC1wvRgkSDoz4vdP4brGNcsZA=",
            // 주기 확인은 끄고 앱이 실행 때 하는 확인만 관측함.
            "SUEnableAutomaticChecks": false
        ]
        try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
            .write(to: contents.appendingPathComponent("Info.plist"))
        bundle = try #require(Bundle(url: root.appendingPathComponent("Installed.app")))
    }

    private static func appcast(newest: (build: Int, version: String, requiredBelow: Int?)) -> String {
        let critical = newest.requiredBelow.map { "<sparkle:criticalUpdate sparkle:version=\"\($0)\"/>" } ?? ""
        return """
            <?xml version="1.0" encoding="utf-8"?>
            <rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
            <channel><title>Privacy AirPods</title>
            <item><title>\(newest.version)</title>
            <sparkle:version>\(newest.build)</sparkle:version>
            <sparkle:shortVersionString>\(newest.version)</sparkle:shortVersionString>
            <sparkle:minimumSystemVersion>15.0</sparkle:minimumSystemVersion>
            \(critical)
            <enclosure url="https://example.invalid/Privacy-AirPods-\(newest.version).dmg" length="1" type="application/octet-stream" sparkle:edSignature="AA=="/>
            </item></channel></rss>
            """
    }

    func remove() {
        server?.stop()
        try? FileManager.default.removeItem(at: root)
        UserDefaults.standard.removePersistentDomain(forName: Self.bundleID)
    }
}

/// Sparkle 업데이트 창 대역. 제안된 판본을 기록하고 사용자가 닫은 것처럼 응답함.
private final class AnsweringUserDriver: NSObject, SPUUserDriver {
    nonisolated(unsafe) private(set) var offeredVersion: String?
    nonisolated(unsafe) private(set) var userInitiatedChecks = 0

    func show(_ request: SPUUpdatePermissionRequest,
              reply: @escaping (SUUpdatePermissionResponse) -> Void) {
        reply(SUUpdatePermissionResponse(automaticUpdateChecks: false, sendSystemProfile: false))
    }
    func showUserInitiatedUpdateCheck(cancellation: @escaping () -> Void) { userInitiatedChecks += 1 }
    func showUpdateFound(with appcastItem: SUAppcastItem, state: SPUUserUpdateState,
                         reply: @escaping (SPUUserUpdateChoice) -> Void) {
        offeredVersion = appcastItem.displayVersionString
        reply(.dismiss)
    }
    func showUpdateReleaseNotes(with downloadData: SPUDownloadData) {}
    func showUpdateReleaseNotesFailedToDownloadWithError(_ error: any Error) {}
    func showUpdateNotFoundWithError(_ error: any Error, acknowledgement: @escaping () -> Void) { acknowledgement() }
    func showUpdaterError(_ error: any Error, acknowledgement: @escaping () -> Void) { acknowledgement() }
    func showDownloadInitiated(cancellation: @escaping () -> Void) { cancellation() }
    func showDownloadDidReceiveExpectedContentLength(_ expectedContentLength: UInt64) {}
    func showDownloadDidReceiveData(ofLength length: UInt64) {}
    func showDownloadDidStartExtractingUpdate() {}
    func showExtractionReceivedProgress(_ progress: Double) {}
    func showReady(toInstallAndRelaunch reply: @escaping (SPUUserUpdateChoice) -> Void) { reply(.dismiss) }
    func showInstallingUpdate(withApplicationTerminated applicationTerminated: Bool,
                              retryTerminatingApplication: @escaping () -> Void) {}
    func showUpdateInstalledAndRelaunched(_ relaunched: Bool, acknowledgement: @escaping () -> Void) { acknowledgement() }
    func dismissUpdateInstallation() {}
}
