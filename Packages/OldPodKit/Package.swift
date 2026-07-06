// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "OldPodKit",
    platforms: [
        .iOS("26.0"),
        .macOS("26.0"),
    ],
    products: [
        .library(
            name: "OldPodKit",
            targets: [
                "Domain", "LibraryStore", "MetadataImport", "CloudFiles",
                "PlaybackEngine", "NowPlaying", "DesignSystem", "AppFeatures",
            ]
        ),
    ],
    targets: [
        .target(name: "Domain"),
        .target(name: "LibraryStore", dependencies: ["Domain", "MetadataImport", "CloudFiles"]),
        .target(name: "MetadataImport", dependencies: ["Domain"]),
        .target(name: "CloudFiles"),
        .target(name: "PlaybackEngine", dependencies: ["Domain", "CloudFiles"]),
        .target(name: "NowPlaying", dependencies: ["PlaybackEngine", "MetadataImport"]),
        .target(name: "DesignSystem"),
        .target(
            name: "AppFeatures",
            dependencies: [
                "Domain", "LibraryStore", "MetadataImport", "CloudFiles",
                "PlaybackEngine", "NowPlaying", "DesignSystem",
            ]
        ),
        .testTarget(
            name: "OldPodKitTests",
            dependencies: [
                "Domain", "LibraryStore", "MetadataImport", "CloudFiles",
                "PlaybackEngine", "NowPlaying", "DesignSystem", "AppFeatures",
            ]
        ),
    ]
)
