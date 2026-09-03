// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "TouchedTipsCore",
    platforms: [.iOS(.v26), .macOS(.v15)],
    products: [
        .library(name: "TouchedTipsCore", targets: ["TouchedTipsCore"]),
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "7.9.0"),
    ],
    targets: [
        .target(
            name: "TouchedTipsCore",
            dependencies: [.product(name: "GRDB", package: "GRDB.swift")]
        ),
        .testTarget(
            name: "TouchedTipsCoreTests",
            dependencies: ["TouchedTipsCore"]
        ),
    ]
)
