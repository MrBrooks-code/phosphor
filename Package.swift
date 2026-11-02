// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Phosphor", platforms: [.macOS("14.2")],
    products: [.executable(name: "Phosphor", targets: ["PhosphorApp"])],
    targets: [
        .target(name: "AudioIngress", publicHeadersPath: "include", linkerSettings: [.linkedFramework("CoreAudio")]),
        .target(name: "PhosphorCore", dependencies: ["AudioIngress"], linkerSettings: [.linkedFramework("Accelerate")]),
        .target(name: "PhosphorCapture", dependencies: ["PhosphorCore", "AudioIngress"], swiftSettings: [.swiftLanguageMode(.v5)]),
        .executableTarget(name: "PhosphorApp", dependencies: ["PhosphorCore", "PhosphorCapture"], resources: [.copy("Resources/Scenes.metal")], swiftSettings: [.swiftLanguageMode(.v5)]),
        .executableTarget(name: "CaptureChecks", dependencies: ["PhosphorCapture"], path: "Tests/CaptureChecks", swiftSettings: [.swiftLanguageMode(.v5)]),
        .executableTarget(name: "CoreChecks", dependencies: ["PhosphorCore", "AudioIngress"], path: "Tests/PhosphorCoreTests")
    ]
)
