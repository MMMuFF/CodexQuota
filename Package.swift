// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "CodexQuota",
    platforms: [
        .macOS(.v13),
    ],
    products: [
        .library(name: "CodexQuotaCore", targets: ["CodexQuotaCore"]),
        .executable(name: "CodexQuota", targets: ["CodexQuotaApp"]),
    ],
    targets: [
        .target(
            name: "CodexQuotaCore",
            path: "Sources/CodexQuotaCore"
        ),
        .executableTarget(
            name: "CodexQuotaApp",
            dependencies: ["CodexQuotaCore"],
            path: "Sources/CodexQuotaApp"
        ),
    ]
)
