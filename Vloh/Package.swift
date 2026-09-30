// swift-tools-version: 6.0
import PackageDescription
let package = Package(name: "VlohCore", platforms: [.macOS(.v14), .iOS(.v18)], products: [.library(name: "VlohCore", targets: ["VlohCore"])], targets: [
    .target(name: "VlohCore", path: "Vloh/Core"),
    .testTarget(name: "VlohCoreTests", dependencies: ["VlohCore"], path: "VlohTests")
], swiftLanguageModes: [.v6])
