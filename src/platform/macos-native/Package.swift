// swift-tools-version: 6.0

import Foundation
import PackageDescription

let packageDirectory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
let repositoryRoot = packageDirectory
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()

let coreBuildDirectoryName = ProcessInfo.processInfo.environment["MGBA_CORE_BUILD_DIR"]
    ?? "build-native-core"
let coreBuildDirectory = repositoryRoot.appendingPathComponent(coreBuildDirectoryName)

let package = Package(
    name: "mGBANative",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "mGBA", targets: ["mGBAApp"]),
    ],
    targets: [
        .target(
            name: "MGBABridge",
            path: "Sources/MGBABridge",
            publicHeadersPath: "include",
            cSettings: [
                .define("ENABLE_VFS"),
                .define("ENABLE_DIRECTORIES"),
                .unsafeFlags([
                    "-I\(repositoryRoot.path)/include",
                    "-I\(coreBuildDirectory.path)/include",
                ]),
            ]
        ),
        .executableTarget(
            name: "mGBAApp",
            dependencies: ["MGBABridge"],
            path: "Sources/mGBAApp",
            resources: [
                .process("Resources"),
            ],
            linkerSettings: [
                .unsafeFlags(["-L\(coreBuildDirectory.path)"]),
                .linkedLibrary("mgba"),
                .linkedLibrary("z"),
                .linkedFramework("AppKit"),
                .linkedFramework("AVFAudio"),
                .linkedFramework("Foundation"),
                .linkedFramework("GameController"),
                .linkedFramework("Metal"),
                .linkedFramework("MetalKit"),
                .linkedFramework("QuartzCore"),
            ]
        ),
        .testTarget(
            name: "MGBABridgeTests",
            dependencies: ["MGBABridge"],
            path: "Tests/MGBABridgeTests",
            linkerSettings: [
                .unsafeFlags(["-L\(coreBuildDirectory.path)"]),
                .linkedLibrary("mgba"),
                .linkedLibrary("z"),
                .linkedFramework("Foundation"),
            ]
        ),
    ],
    swiftLanguageModes: [.v5]
)
