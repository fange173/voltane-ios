// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "VoltaneKit",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [.library(name: "VoltaneKit", targets: ["VoltaneKit"])],
    targets: [
        .target(name: "VoltaneKit"),
        .testTarget(
            name: "VoltaneKitTests",
            dependencies: ["VoltaneKit"],
            resources: [.copy("Fixtures"), .copy("Golden")]
        ),
    ]
)
