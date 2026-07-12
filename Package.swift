// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "mapconductor-for-mapkit",
    platforms: [
        .iOS(.v15),
    ],
    products: [
        .library(
            name: "MapConductorForMapKit",
            targets: ["MapConductorForMapKit"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/MapConductor/ios-sdk-core", from: "1.1.4"),
    ],
    targets: [
        .target(
            name: "MapConductorForMapKit",
            dependencies: [
                .product(name: "MapConductorCore", package: "ios-sdk-core"),
            ]
        ),
    ]
)
