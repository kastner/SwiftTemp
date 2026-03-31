// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "SwiftTemp",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "SwiftTemp",
            path: "SwiftTemp"
        ),
    ]
)
