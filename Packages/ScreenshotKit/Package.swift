// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ScreenshotKit",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "ScreenshotKit", targets: ["ScreenshotKit"])
    ],
    targets: [
        .target(name: "ScreenshotKit"),
        .testTarget(name: "ScreenshotKitTests", dependencies: ["ScreenshotKit"])
    ]
)
