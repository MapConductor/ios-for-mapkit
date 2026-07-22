// swift-tools-version: 5.9
import Foundation
import PackageDescription

let frameworkLibraryType: Product.Library.LibraryType? =
    ProcessInfo.processInfo.environment["MAPCONDUCTOR_BUILD_XCFRAMEWORK"] == "1" ? .dynamic : nil
let usingLocalCore = FileManager.default.fileExists(atPath: "../ios-sdk-core/Package.swift")
let coreDependency: Package.Dependency = usingLocalCore
    ? .package(path: "../ios-sdk-core")
    : .package(url: "https://github.com/MapConductor/ios-sdk-core", from: "1.1.4")

let package = Package(
    name: "mapconductor-for-mapkit",
    platforms: [
        // See ios-sdk-core/Package.swift's comment: "15.0" must not be used here.
        .iOS("15.1"),
    ],
    products: [
        .library(
            name: "MapConductorForMapKit",
            type: frameworkLibraryType,
            targets: ["MapConductorForMapKit"]
        ),
    ],
    dependencies: [
        coreDependency,
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
