// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "ThorRebornCore",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "ThorRebornCore", targets: ["ThorRebornCore"])
    ],
    targets: [
        .target(name: "ThorRebornCore"),
        .testTarget(name: "ThorRebornCoreTests", dependencies: ["ThorRebornCore"])
    ],
    swiftLanguageModes: [.v6]
)
