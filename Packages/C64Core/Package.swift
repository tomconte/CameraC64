// swift-tools-version: 6.0
import PackageDescription

// The platform-independent core: palettes, graphics modes, converter, renderer
// and C64 file formats. No UIKit, SwiftUI or Metal here, so it also builds and
// tests on Linux. Its platform floor is lower than the app's on purpose.
let package = Package(
    name: "C64Core",
    platforms: [.iOS(.v18), .macOS(.v15)],
    products: [
        .library(name: "C64Core", targets: ["C64Core"])
    ],
    targets: [
        .target(name: "C64Core"),
        .testTarget(name: "C64CoreTests", dependencies: ["C64Core"]),
    ]
)
