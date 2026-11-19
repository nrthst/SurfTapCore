// swift-tools-version: 6.0
import PackageDescription

let package = Package(
  name: "SurfTapCore",
  platforms: [.macOS(.v13), .iOS(.v16), .watchOS(.v9), .tvOS(.v16)],
  products: [
    .library(name: "SurfTapCore", targets: ["SurfTapCore"]),
    .library(name: "SurfTapStormglass", targets: ["SurfTapStormglass"]),
    .executable(name: "surftap-example", targets: ["SurfTapExample"]),
  ],
  targets: [
    .target(name: "SurfTapCore"),
    .target(name: "SurfTapStormglass", dependencies: ["SurfTapCore"]),
    .executableTarget(name: "SurfTapExample", dependencies: ["SurfTapCore", "SurfTapStormglass"]),
    .testTarget(name: "SurfTapCoreTests", dependencies: ["SurfTapCore"]),
    .testTarget(name: "SurfTapStormglassTests", dependencies: ["SurfTapStormglass"]),
  ]
)
