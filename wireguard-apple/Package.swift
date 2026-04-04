// swift-tools-version:5.5
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription
import Foundation

let goLibDir = URL(fileURLWithPath: #file).deletingLastPathComponent()
    .appendingPathComponent("Sources/WireGuardKitGo/prebuilt").path

let package = Package(
    name: "WireGuardKit",
    platforms: [
        .macOS(.v12),
        .iOS(.v15)
    ],
    products: [
        .library(name: "WireGuardKit", targets: ["WireGuardKit"]),
        .library(name: "WireGuardKitExtensions", targets: ["WireGuardKitExtensions"])
    ],
    dependencies: [],
    targets: [
        .target(
            name: "WireGuardKit",
            dependencies: ["WireGuardKitGo", "WireGuardKitC"]
        ),
        .target(
            name: "WireGuardKitC",
            dependencies: [],
            publicHeadersPath: "."
        ),
        .target(
            name: "WireGuardKitExtensions",
            dependencies: ["WireGuardKit"],
            path: "Sources/Shared/Model",
            sources: [
                "TunnelConfiguration+WgQuickConfig.swift",
                "String+ArrayConversion.swift"
            ]
        ),
        .target(
            name: "WireGuardKitGo",
            dependencies: [],
            exclude: [
                "goruntime-boottime-over-monotonic.diff",
                "go.mod",
                "go.sum",
                "api-apple.go",
                "Makefile"
            ],
            publicHeadersPath: ".",
            linkerSettings: [
                .linkedLibrary("wg-go"),
                .unsafeFlags(["-L\(goLibDir)"])
            ]
        )
    ]
)
