// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "HeadOrbit",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "HeadOrbit", targets: ["HeadOrbit"])],
    targets: [
        .executableTarget(name: "HeadOrbit", path: "HeadOrbit", exclude: ["Info.plist", "Resources"])
    ]
)
