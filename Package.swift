// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "JasoGuard",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "JasoGuard", targets: ["JasoGuard"])
    ],
    targets: [
        .executableTarget(
            name: "JasoGuard",
            linkerSettings: [.linkedFramework("CoreServices"), .linkedFramework("AppKit")]
        )
    ]
)
