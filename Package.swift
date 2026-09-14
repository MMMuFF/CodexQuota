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
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.10.0"),
    ],
    targets: [
        .target(
            name: "CodexQuotaCore",
            path: "Sources/CodexQuotaCore"
        ),
        .executableTarget(
            name: "CodexQuotaApp",
            dependencies: ["CodexQuotaCore", .product(name: "Sparkle", package: "Sparkle")],
            path: "Sources/CodexQuotaApp",
            linkerSettings: [.unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])]
        ),
    ]
)
