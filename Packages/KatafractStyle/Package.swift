// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "KatafractStyle",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
    ],
    products: [
        .library(name: "KatafractStyle", targets: ["KatafractStyle"]),
    ],
    targets: [
        .target(
            name: "KatafractStyle",
            path: "Sources/KatafractStyle"
        ),
    ]
)
