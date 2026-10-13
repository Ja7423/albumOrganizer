// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ScreenshotKit",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "ScreenshotKit", targets: ["ScreenshotKit"]),
        .library(name: "ScreenshotKitLLM", targets: ["ScreenshotKitLLM"]),
        .library(name: "ScreenshotKitML", targets: ["ScreenshotKitML"]),
        .executable(name: "classification-eval", targets: ["ClassificationEval"]),
    ],
    targets: [
        .target(name: "ScreenshotKit", resources: [.process("Resources")]),
        // Apple Intelligence layer: FoundationModels needs iOS 26 / macOS 26, so it stays out of ScreenshotKit.
        .target(name: "ScreenshotKitLLM", dependencies: ["ScreenshotKit"]),
        // The learned layer: a text classifier trained on the device from the user's own placements (Create ML).
        .target(name: "ScreenshotKitML", dependencies: ["ScreenshotKit"]),
        // Measures the layers on a labeled set; see doc/classification.md §7.1.
        .executableTarget(name: "ClassificationEval", dependencies: ["ScreenshotKit", "ScreenshotKitLLM", "ScreenshotKitML"]),
        .testTarget(name: "ScreenshotKitTests", dependencies: ["ScreenshotKit"], resources: [.process("Fixtures")]),
        .testTarget(name: "ScreenshotKitMLTests", dependencies: ["ScreenshotKit", "ScreenshotKitML"]),
    ]
)
