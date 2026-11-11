// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MiBudsMac", platforms: [.macOS(.v14)],
    products: [.executable(name: "MiBudsMac", targets: ["MiBudsMac"])],
    targets: [
        .target(name: "MiBudsCore"),
        .executableTarget(
            name: "MiBudsMac", dependencies: ["MiBudsCore"],
            resources: [.process("Resources")],
            linkerSettings: [.linkedFramework("IOBluetooth")]),
        .testTarget(name: "MiBudsCoreTests", dependencies: ["MiBudsCore"]),
    ], swiftLanguageModes: [.v5]
)
