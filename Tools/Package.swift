// swift-tools-version: 6.0
import PackageDescription

// Developer tools on top of C64Core: the c64conv command-line tool, and the
// tests that compare the renderer with the VICE emulator. Like C64Core, they
// build and run on Linux and macOS, and have no other dependencies.
let package = Package(
    name: "Tools",
    platforms: [.macOS(.v15)],
    products: [
        .executable(name: "c64conv", targets: ["c64conv"])
    ],
    dependencies: [
        .package(path: "../Packages/C64Core")
    ],
    targets: [
        .target(name: "C64Tools", dependencies: ["C64Core"]),
        .executableTarget(name: "c64conv", dependencies: ["C64Tools", "C64Core"]),
        .testTarget(name: "C64ToolsTests", dependencies: ["C64Tools", "C64Core"]),
    ]
)
