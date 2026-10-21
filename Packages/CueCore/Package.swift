// swift-tools-version: 6.2
import PackageDescription

/// Pure-Swift logic for Cue. No UIKit, SwiftUI or AVFoundation here, so the
/// whole package builds and tests on Linux CI as well as in Xcode.
let package = Package(
    name: "CueCore",
    platforms: [.iOS(.v26), .macOS(.v15)],
    products: [
        .library(name: "CueCore", targets: ["CueCore"])
    ],
    targets: [
        .target(name: "CueCore"),
        .testTarget(name: "CueCoreTests", dependencies: ["CueCore"])
    ],
    swiftLanguageModes: [.v6]
)
