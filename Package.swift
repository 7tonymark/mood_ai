// swift-tools-version:5.9
// The iOS app is built from project.yml with XcodeGen. This package exists so the
// platform-independent core (crypto, wire formats, sync) can be built and tested with
// plain `swift test`, on a Mac or on Linux (where swift-crypto stands in for CryptoKit).
import PackageDescription

let package = Package(
    name: "ProximityCore",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "ProximityCore", targets: ["ProximityCore"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-crypto.git", "3.0.0"..<"4.0.0"),
    ],
    targets: [
        .target(
            name: "ProximityCore",
            dependencies: [
                .product(name: "Crypto", package: "swift-crypto", condition: .when(platforms: [.linux])),
            ],
            path: "Proximity/Core"
        ),
        .testTarget(
            name: "ProximityCoreTests",
            dependencies: ["ProximityCore"],
            path: "ProximityTests"
        ),
    ]
)
