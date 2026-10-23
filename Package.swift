// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "MacMirrorScreen",
    platforms: [.macOS(.v13)],
    targets: [
        .target(name: "MirrorCore"),
        .executableTarget(name: "MacMirrorScreen", dependencies: ["MirrorCore"]),
        .testTarget(name: "MirrorCoreTests", dependencies: ["MirrorCore"]),
    ]
)
