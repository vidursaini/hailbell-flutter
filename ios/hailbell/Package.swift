// swift-tools-version: 5.9
// The Hailbell Flutter plugin for apps that use Swift Package Manager, Flutter's default.
// Sources/hailbell/Vendor is the native Swift SDK, copied from sdk/swift by tool/sync_native.sh.
import PackageDescription

let package = Package(
    name: "hailbell",
    platforms: [
        .iOS("16.0"),
    ],
    products: [
        .library(name: "hailbell", targets: ["hailbell"]),
    ],
    dependencies: [
        .package(name: "FlutterFramework", path: "../FlutterFramework"),
    ],
    targets: [
        .target(
            name: "hailbell",
            dependencies: [
                .product(name: "FlutterFramework", package: "FlutterFramework"),
            ],
            exclude: ["Vendor/VENDORED_FROM"],
            resources: [
                .process("PrivacyInfo.xcprivacy"),
            ]
        ),
    ]
)
