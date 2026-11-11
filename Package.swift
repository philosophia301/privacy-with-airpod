// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "PrivacyAirPods",
    platforms: [.macOS(.v15)],
    products: [.executable(name: "PrivacyAirPods", targets: ["PrivacyAirPods"])],
    targets: [
        .target(name: "PrivacyCore"),
        .target(name: "PrivacyBackdrop", publicHeadersPath: "include",
                cSettings: [.unsafeFlags(["-fobjc-arc"])],
                linkerSettings: [.linkedFramework("AppKit"), .linkedFramework("QuartzCore")]),
        .executableTarget(name: "PrivacyAirPods", dependencies: ["PrivacyCore", "PrivacyBackdrop"]),
        .testTarget(name: "PrivacyCoreTests", dependencies: ["PrivacyCore"]),
        .testTarget(name: "PrivacyAppTests", dependencies: ["PrivacyAirPods"])
    ]
)
