// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "PrivacyAirPods",
    platforms: [.macOS(.v15)],
    products: [.executable(name: "PrivacyAirPods", targets: ["PrivacyAirPods"])],
    // 앱 내 업데이트 설치. 서명 형식과 설치 동작이 바뀔 수 있으므로 판본을 고정함.
    dependencies: [.package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.10.1")],
    targets: [
        .target(name: "PrivacyCore"),
        .target(name: "PrivacyBackdrop", publicHeadersPath: "include",
                cSettings: [.unsafeFlags(["-fobjc-arc"])],
                linkerSettings: [.linkedFramework("AppKit"), .linkedFramework("QuartzCore")]),
        .executableTarget(name: "PrivacyAirPods",
                          dependencies: ["PrivacyCore", "PrivacyBackdrop",
                                         .product(name: "Sparkle", package: "Sparkle")],
                          // 앱 번들의 Contents/Frameworks에 넣은 Sparkle.framework를 찾게 함.
                          linkerSettings: [.unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])]),
        .testTarget(name: "PrivacyCoreTests", dependencies: ["PrivacyCore"]),
        .testTarget(name: "PrivacyAppTests",
                    dependencies: ["PrivacyAirPods", .product(name: "Sparkle", package: "Sparkle")])
    ]
)
