// swift-tools-version: 6.2

import PackageDescription

let jellyfinAPI: Target.Dependency = .product(name: "JellyfinAPI", package: "jellyfin-sdk-swift")

let package = Package(
    name: "SerafinKit",
    defaultLocalization: "en",
    platforms: [
        .iOS("26.1"),
        .macOS(.v26),
    ],
    products: [
        .library(name: "SerafinCore", targets: ["SerafinCore"]),
        .library(name: "SerafinPlayback", targets: ["SerafinPlayback"]),
        .library(name: "SerafinDesign", targets: ["SerafinDesign"]),
        .library(name: "SerafinFeatures", targets: ["SerafinFeatures"]),
    ],
    dependencies: [
        .package(url: "https://github.com/jellyfin/jellyfin-sdk-swift.git", exact: "3.3.0"),
        .package(url: "https://github.com/kean/Nuke.git", exact: "13.2.0"),
    ],
    targets: [
        // Networking, auth, stores, models and the image pipeline. No UI.
        .target(
            name: "SerafinCore",
            dependencies: [
                jellyfinAPI,
                .product(name: "Nuke", package: "Nuke"),
            ]
        ),
        // AVPlayer wrapper, device profile, playback negotiation, progress, Now Playing and PiP.
        .target(
            name: "SerafinPlayback",
            dependencies: ["SerafinCore"]
        ),
        // Tokens, components, mock fixtures and previews. Depends on nothing in the project.
        .target(
            name: "SerafinDesign",
            resources: [.process("Resources")]
        ),
        // Screens and screen models, one folder per feature.
        .target(
            name: "SerafinFeatures",
            dependencies: [
                "SerafinCore",
                "SerafinPlayback",
                "SerafinDesign",
                jellyfinAPI,
                .product(name: "NukeUI", package: "Nuke"),
            ],
            resources: [.process("Resources")]
        ),
        .testTarget(name: "SerafinCoreTests", dependencies: ["SerafinCore"]),
        .testTarget(name: "SerafinPlaybackTests", dependencies: ["SerafinPlayback"]),
        .testTarget(name: "SerafinDesignTests", dependencies: ["SerafinDesign"]),
    ],
    // Swift 6 language mode enforces complete strict concurrency checking.
    swiftLanguageModes: [.v6]
)
