// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "PrismModules",
    defaultLocalization: "en",
    platforms: [
        .iOS(.v26),
    ],
    products: [
        .library(name: "VaultManager", targets: ["VaultManager"]),
        .library(name: "AdBlockEngine", targets: ["AdBlockEngine"]),
        .library(name: "ParallelDownloader", targets: ["ParallelDownloader"]),
        .library(name: "PrismPlayer", targets: ["PrismPlayer"]),
        .library(name: "MediaInterceptor", targets: ["MediaInterceptor"]),
        .library(name: "BrowserCore", targets: ["BrowserCore"]),
    ],
    dependencies: [
        .package(path: "../../Vendor/SwiftyDownloadManager/Packages/SDMCore"),
        .package(url: "https://github.com/kingslay/FFmpegKit.git", exact: "9.0.2"),
        .package(url: "https://github.com/weichsel/ZIPFoundation.git", exact: "0.9.21"),
    ],
    targets: [
        .target(
            name: "VaultManager",
            dependencies: [
                .product(name: "ZIPFoundation", package: "ZIPFoundation"),
            ],
            linkerSettings: [
                .linkedFramework("LocalAuthentication"),
                .linkedFramework("AVFoundation"),
                .linkedFramework("MediaPlayer"),
                .linkedFramework("Security"),
            ]
        ),
        .target(
            name: "AdBlockEngine",
            dependencies: [],
            linkerSettings: [
                .linkedFramework("WebKit"),
            ]
        ),
        .target(
            name: "ParallelDownloader",
            dependencies: [
                "VaultManager",
                .product(name: "SDMCore", package: "SDMCore"),
                .product(name: "FFmpegKit", package: "FFmpegKit"),
                .product(name: "Libavformat", package: "FFmpegKit"),
                .product(name: "Libavcodec", package: "FFmpegKit"),
                .product(name: "Libavutil", package: "FFmpegKit"),
            ],
            linkerSettings: [
                .linkedFramework("VideoToolbox"),
                .linkedFramework("AudioToolbox"),
                .linkedFramework("CoreMedia"),
                .linkedLibrary("z"),
                .linkedLibrary("bz2"),
                .linkedLibrary("iconv"),
            ]
        ),
        .target(
            name: "PrismPlayer",
            dependencies: [
                "VaultManager",
                "ParallelDownloader",
                .product(name: "FFmpegKit", package: "FFmpegKit"),
                .product(name: "libmpv", package: "FFmpegKit"),
            ],
            linkerSettings: [
                .linkedFramework("AVFoundation"),
                .linkedFramework("AVKit"),
                .linkedFramework("VideoToolbox"),
                .linkedFramework("AudioToolbox"),
                .linkedFramework("CoreMedia"),
                .linkedFramework("MediaPlayer"),
                .linkedFramework("Metal"),
                .linkedFramework("QuartzCore"),
            ]
        ),
        .target(
            name: "MediaInterceptor",
            dependencies: [
                "ParallelDownloader",
                "PrismPlayer",
            ],
            resources: [
                .process("Resources"),
            ],
            linkerSettings: [
                .linkedFramework("WebKit"),
            ]
        ),
        .target(
            name: "BrowserCore",
            dependencies: [
                "VaultManager",
                "AdBlockEngine",
                "ParallelDownloader",
                "PrismPlayer",
                "MediaInterceptor",
            ],
            resources: [
                .process("Resources"),
            ],
            linkerSettings: [
                .linkedFramework("WebKit"),
                .linkedFramework("VisionKit"),
                .linkedFramework("AVFoundation"),
            ]
        ),
        .testTarget(
            name: "PrismModulesTests",
            dependencies: [
                "VaultManager",
                "AdBlockEngine",
                "ParallelDownloader",
                "PrismPlayer",
                "MediaInterceptor",
                "BrowserCore",
            ]
        ),
    ],
    swiftLanguageModes: [.v6]
)
