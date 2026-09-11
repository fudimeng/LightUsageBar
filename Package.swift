// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "LightUsageBar",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "LightUsageBar", targets: ["LightUsageBar"])],
    targets: [.executableTarget(name: "LightUsageBar")]
)
