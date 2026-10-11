// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ScreenshotKit",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "ScreenshotKit", targets: ["ScreenshotKit"]),
        .library(name: "ScreenshotKitLLM", targets: ["ScreenshotKitLLM"]),
        .executable(name: "classification-eval", targets: ["ClassificationEval"]),
    ],
    targets: [
        .target(name: "ScreenshotKit"),
        // Apple Intelligence layer: FoundationModels needs iOS 26 / macOS 26, so it stays out of ScreenshotKit.
        .target(name: "ScreenshotKitLLM", dependencies: ["ScreenshotKit"]),
        // Measures both layers on a labeled set; see doc/classification.md §7.1.
        .executableTarget(name: "ClassificationEval", dependencies: ["ScreenshotKit", "ScreenshotKitLLM"]),
        .testTarget(name: "ScreenshotKitTests", dependencies: ["ScreenshotKit"], resources: [.process("Fixtures")]),
    ]
)
