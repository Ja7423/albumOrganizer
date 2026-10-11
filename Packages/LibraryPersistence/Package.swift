// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "LibraryPersistence",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "LibraryPersistence", targets: ["LibraryPersistence"]),
    ],
    dependencies: [
        .package(path: "../ScreenshotKit"),
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "7.0.0"),
    ],
    targets: [
        .target(
            name: "LibraryPersistence",
            dependencies: ["ScreenshotKit", .product(name: "GRDB", package: "GRDB.swift")]
        ),
        .testTarget(name: "LibraryPersistenceTests", dependencies: ["LibraryPersistence"], resources: [.process("Fixtures")]),
    ]
)
