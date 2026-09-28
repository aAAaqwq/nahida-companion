// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "NahidaCompanion",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "NahidaCompanion", targets: ["NahidaCompanion"])],
    targets: [.executableTarget(name: "NahidaCompanion")]
)
