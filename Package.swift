// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "LaserStudio",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "LaserStudio", targets: ["LaserStudio"])],
    targets: [
        .executableTarget(name: "LaserStudio"),
        .testTarget(name: "LaserStudioTests", dependencies: ["LaserStudio"], path: "Tests/LaserStudioTests")
    ]
)
