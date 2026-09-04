// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "IPTVCore",
    platforms: [
        .iOS(.v17),
        // `swift test` runs on the CI runner's host macOS, and SwiftData (used by
        // Persistence/ProviderAccount) needs a declared macOS minimum to compile there.
        .macOS(.v14)
    ],
    products: [
        .library(name: "IPTVCore", targets: ["IPTVCore"])
    ],
    targets: [
        .target(name: "IPTVCore"),
        .testTarget(name: "IPTVCoreTests", dependencies: ["IPTVCore"])
    ]
)
