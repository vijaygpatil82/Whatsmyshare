// swift-tools-version:5.9
// This package exists only so the app's pure money logic (WhatsMyShare/Core)
// can be unit tested with `swift test` — on a Mac or in CI.
// To work on the app itself, open WhatsMyShare.xcodeproj.
import PackageDescription

let package = Package(
    name: "ShareCore",
    platforms: [.macOS(.v13), .iOS(.v17)],
    products: [
        .library(name: "ShareCore", targets: ["ShareCore"])
    ],
    targets: [
        .target(name: "ShareCore", path: "WhatsMyShare/Core"),
        .testTarget(name: "ShareCoreTests", dependencies: ["ShareCore"], path: "Tests/ShareCoreTests")
    ]
)
