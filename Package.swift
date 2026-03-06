// swift-tools-version: 6.0

import PackageDescription

let whisperInstall = "vendor/whisper-install"

let package = Package(
    name: "Aavaz",
    platforms: [.macOS(.v15)],
    targets: [
        .systemLibrary(
            name: "CWhisper",
            path: "Sources/CWhisper",
            pkgConfig: nil,
            providers: []
        ),
        .executableTarget(
            name: "Aavaz",
            dependencies: ["CWhisper"],
            path: "Sources/Aavaz",
            swiftSettings: [
                .unsafeFlags(["-import-objc-header", "Sources/CWhisper/include/whisper_shim.h"]),
            ],
            linkerSettings: [
                .unsafeFlags([
                    "-L\(whisperInstall)/lib",
                ]),
                .linkedLibrary("whisper"),
                .linkedLibrary("ggml"),
                .linkedLibrary("ggml-base"),
                .linkedLibrary("ggml-cpu"),
                .linkedLibrary("ggml-metal"),
                .linkedLibrary("ggml-blas"),
                .linkedLibrary("c++"),
                .linkedFramework("Accelerate"),
                .linkedFramework("Metal"),
                .linkedFramework("Foundation"),
                .linkedFramework("MetalKit"),
            ]
        ),
        .testTarget(
            name: "AavazTests",
            dependencies: ["Aavaz"],
            path: "Tests/AavazTests"
        ),
    ]
)
