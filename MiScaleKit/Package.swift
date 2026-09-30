// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "MiScaleKit",
    platforms: [.watchOS(.v10), .iOS(.v17), .macOS(.v13)],
    products: [
        .library(name: "MiScaleKit", targets: ["MiScaleKit"]),
    ],
    targets: [
        .target(name: "MiScaleKit"),
        .testTarget(name: "MiScaleKitTests", dependencies: ["MiScaleKit"]),
    ]
)
