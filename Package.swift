// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "PokeNX2iOS",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "PokeNX2iOS", path: "Sources/PokeNX2iOS")
    ]
)
