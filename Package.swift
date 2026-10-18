// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "DropMe",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "DropMe", path: "Sources/DropMe")
    ]
)
