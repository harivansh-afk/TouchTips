// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "TouchTipsCore",
    platforms: [.iOS(.v26), .macOS(.v15)],
    products: [
        .library(name: "TouchTipsCore", targets: ["TouchTipsCore"]),
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "7.9.0"),
    ],
    targets: [
        .target(
            name: "TouchTipsCore",
            dependencies: [.product(name: "GRDB", package: "GRDB.swift")]
        ),
        .testTarget(
            name: "TouchTipsCoreTests",
            dependencies: ["TouchTipsCore"]
        ),
    ]
)
