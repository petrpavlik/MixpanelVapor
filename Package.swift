// swift-tools-version: 5.10
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "MixpanelVapor",
    platforms: [
        .macOS(.v13),
        .iOS(.v15),
        .tvOS(.v15),
        .watchOS(.v6),
    ],
    products: [
        // Products define the executables and libraries a package produces, and make them visible to other packages.
        .library(
            name: "MixpanelVapor",
            targets: ["MixpanelVapor"])
    ],
    dependencies: [
        // Dependencies declare other packages that this package depends on.
        // .package(url: /* package url */, from: "1.0.0"),
        .package(url: "https://github.com/vapor/vapor.git", from: "4.0.0"),
        .package(url: "https://github.com/malcommac/UAParserSwift.git", from: "1.2.1"),
        .package(url: "https://github.com/vadymmarkov/Fakery.git", from: "5.1.0"),
    ],
    targets: [
        // Targets are the basic building blocks of a package. A target can define a module or a test suite.
        // Targets can depend on other targets in this package, and on products in packages this package depends on.
        .target(
            name: "MixpanelVapor",
            dependencies: [.product(name: "Vapor", package: "vapor"), "UAParserSwift"],
            swiftSettings: [.enableExperimentalFeature("StrictConcurrency=complete")]),
        .testTarget(
            name: "MixpanelVaporTests",
            dependencies: [
                "MixpanelVapor",
                "Fakery",
                .product(name: "XCTVapor", package: "vapor"),
            ],
            swiftSettings: [.enableExperimentalFeature("StrictConcurrency=complete")]),
    ]
)
