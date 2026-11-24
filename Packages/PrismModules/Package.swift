// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "PrismModules",
    defaultLocalization: "en",
    platforms: [
        .iOS(.v26),
    ],
    products: [
        .library(name: "PrismCore", targets: ["PrismCore"]),
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
        .package(url: "https://github.com/kstenerud/KSCrash.git", from: "2.6.1"),
        .package(url: "https://github.com/Catlyn-Lab/ytdlp-apple.git", from: "0.1.1"),
    ],
    targets: [
        .target(
            name: "PrismCore",
            dependencies: [
                .product(name: "Recording", package: "KSCrash"),
                .product(name: "Filters", package: "KSCrash"),
            ]
        ),
        .target(
            name: "VaultManager",
            dependencies: [
                "PrismCore",
                .product(name: "ZIPFoundation", package: "ZIPFoundation"),
            ],
            linkerSettings: [
                .linkedFramework("LocalAuthentication"),
                .linkedFramework("AVFoundation"),
                .linkedFramework("MediaPlayer"),
                .linkedFramework("Photos"),
                .linkedFramework("PhotosUI"),
                .linkedFramework("Security"),
            ]
        ),
        .target(
            name: "AdBlockEngine",
            dependencies: [
                "PrismCore",
            ],
            resources: [
                .process("Resources"),
            ],
            linkerSettings: [
                .linkedFramework("WebKit"),
            ]
        ),
        .target(
            name: "ParallelDownloader",
            dependencies: [
                "PrismCore",
                "VaultManager",
                .product(name: "SDMCore", package: "SDMCore"),
                .product(name: "YTDLP", package: "ytdlp-apple"),
                .product(name: "FFmpegKit", package: "FFmpegKit"),
                .product(name: "Libavformat", package: "FFmpegKit"),
                .product(name: "Libavcodec", package: "FFmpegKit"),
                .product(name: "Libavutil", package: "FFmpegKit"),
            ],
            linkerSettings: [
                .linkedFramework("JavaScriptCore"),
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
                "PrismCore",
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
                "PrismCore",
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
                "PrismCore",
                "VaultManager",
                "AdBlockEngine",
                "ParallelDownloader",
                "PrismPlayer",
                "MediaInterceptor",
                .product(name: "SDMCore", package: "SDMCore"),
            ],
            resources: [
                .process("Resources"),
            ],
            linkerSettings: [
                .linkedFramework("WebKit"),
                .linkedFramework("VisionKit"),
                .linkedFramework("AVFoundation"),
                .linkedFramework("PhotosUI"),
                .linkedFramework("Translation"),
            ]
        ),
        .testTarget(
            name: "PrismModulesTests",
            dependencies: [
                "PrismCore",
                "VaultManager",
                "AdBlockEngine",
                "ParallelDownloader",
                "PrismPlayer",
                "MediaInterceptor",
                "BrowserCore",
                .product(name: "SDMCore", package: "SDMCore"),
            ]
        ),
    ],
    swiftLanguageModes: [.v6]
)
