// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "EmberCore",
    platforms: [.macOS(.v14), .iOS(.v17)],
    products: [.library(name: "EmberCore", targets: ["EmberCore"])],
    targets: [
        .target(name: "EmberCore", path: "Ember", exclude: ["App", "Views", "Resources"], sources: ["Core", "State"]),
        .testTarget(name: "EmberCoreTests", dependencies: ["EmberCore"], path: "EmberTests")
    ],
    swiftLanguageModes: [.v6]
)
