// swift-tools-version: 5.9
// Flutter plugin Swift Package for SwiftPM hosts (Flutter 3.24+).
// The LinkSense iOS SDK is vendored into this target (Sources/linksense/
// LinkSenseCore/, synced by ios/sync-ios-sdk.sh) and compiles into the same
// module; see that script for why it is not a package dependency.
import PackageDescription

let package = Package(
    name: "linksense",
    platforms: [.iOS(.v16)],
    products: [
        .library(name: "linksense", targets: ["linksense"]),
    ],
    dependencies: [
        .package(name: "FlutterFramework", path: "../FlutterFramework"),
    ],
    targets: [
        .target(
            name: "linksense",
            dependencies: [
                .product(name: "FlutterFramework", package: "FlutterFramework"),
            ],
            exclude: ["LinkSenseCore/VERSION"],
            resources: [.process("Resources")]
        ),
    ]
)
