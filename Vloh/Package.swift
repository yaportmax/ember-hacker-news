// swift-tools-version: 6.0
import PackageDescription
let package = Package(name: "VlohCore", platforms: [.macOS(.v15), .iOS(.v18)], products: [.library(name: "VlohCore", targets: ["VlohCore"])], targets: [
    .target(name: "VlohCore", path: "Vloh", exclude: ["App", "Views", "State", "Resources", "Services/CloudService.swift"], sources: ["Core", "Services/MediaService.swift"]),
    .testTarget(name: "VlohCoreTests", dependencies: ["VlohCore"], path: "VlohTests")
], swiftLanguageModes: [.v6])
