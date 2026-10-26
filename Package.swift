// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SnapMark",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "SnapMark", targets: ["SnapMark"])],
    targets: [.executableTarget(name: "SnapMark")]
)
