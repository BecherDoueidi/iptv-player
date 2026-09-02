// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "IPTVCore",
    platforms: [
        .iOS(.v17)
    ],
    products: [
        .library(name: "IPTVCore", targets: ["IPTVCore"])
    ],
    targets: [
        .target(name: "IPTVCore"),
        .testTarget(name: "IPTVCoreTests", dependencies: ["IPTVCore"])
    ]
)
