// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "RefChecker",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "RefChecker", targets: ["RefChecker"])
    ],
    targets: [
        // Platform-independent logic: parsing, metadata lookup, comparison, HTML report.
        .target(name: "RefCheckerCore"),
        // SwiftUI macOS app.
        .executableTarget(name: "RefChecker", dependencies: ["RefCheckerCore"]),
        .testTarget(name: "RefCheckerCoreTests", dependencies: ["RefCheckerCore"])
    ]
)
