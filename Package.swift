// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "DiskPulse",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "DiskPulse", targets: ["DiskPulse"])],
    targets: [
        .target(name: "DiskPulseCore", linkerSettings: [.linkedLibrary("sqlite3")]),
        .executableTarget(name: "DiskPulse", dependencies: ["DiskPulseCore"]),
        .testTarget(name: "DiskPulseCoreTests", dependencies: ["DiskPulseCore"])
    ]
)
