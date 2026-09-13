// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "PoiseKit",
    platforms: [.iOS(.v18), .macOS(.v15)],
    products: [
        .library(name: "PoiseKit", targets: ["PoiseKit"]),
    ],
    targets: [
        .target(name: "PoiseKit"),
        .testTarget(name: "PoiseKitTests", dependencies: ["PoiseKit"]),
    ],
    swiftLanguageModes: [.v6]
)
