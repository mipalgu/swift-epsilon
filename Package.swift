// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "swift-epsilon",
    platforms: [
        .macOS(.v15),
        .iOS(.v18),
    ],
    products: [
        .library(
            name: "EOL",
            targets: ["EOL"]
        ),
        .library(
            name: "EVL",
            targets: ["EVL"]
        ),
        .library(
            name: "ETL",
            targets: ["ETL"]
        ),
        .library(
            name: "EGL",
            targets: ["EGL"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/mipalgu/swift-ecore", exact: "0.8.0"),
    ],
    targets: [
        .target(
            name: "EOL",
            dependencies: [
                .product(name: "ECore", package: "swift-ecore"),
                .product(name: "EMFBase", package: "swift-ecore"),
            ],
            swiftSettings: [
                .enableUpcomingFeature("StrictConcurrency")
            ]
        ),
        .target(
            name: "EVL",
            dependencies: [
                "EOL",
                .product(name: "ECore", package: "swift-ecore"),
            ],
            swiftSettings: [
                .enableUpcomingFeature("StrictConcurrency")
            ]
        ),
        .target(
            name: "ETL",
            dependencies: [
                "EOL",
                .product(name: "ECore", package: "swift-ecore"),
            ],
            swiftSettings: [
                .enableUpcomingFeature("StrictConcurrency")
            ]
        ),
        .target(
            name: "EGL",
            dependencies: [
                "EOL",
                .product(name: "ECore", package: "swift-ecore"),
            ],
            swiftSettings: [
                .enableUpcomingFeature("StrictConcurrency")
            ]
        ),
        .target(
            name: "EpsilonTestSupport",
            dependencies: [
                "EOL",
                .product(name: "ECore", package: "swift-ecore"),
            ],
            path: "Tests/EpsilonTestSupport",
            resources: [
                .copy("Resources")
            ],
            swiftSettings: [
                .enableUpcomingFeature("StrictConcurrency")
            ]
        ),
        .testTarget(
            name: "EOLTests",
            dependencies: [
                "EpsilonTestSupport",
                "EOL",
                .product(name: "ECore", package: "swift-ecore"),
            ],
            swiftSettings: [
                .enableUpcomingFeature("StrictConcurrency")
            ]
        ),
        .testTarget(
            name: "EVLTests",
            dependencies: [
                "EpsilonTestSupport",
                "EVL",
                "EOL",
                .product(name: "ECore", package: "swift-ecore"),
            ],
            swiftSettings: [
                .enableUpcomingFeature("StrictConcurrency")
            ]
        ),
        .testTarget(
            name: "ETLTests",
            dependencies: [
                "EpsilonTestSupport",
                "ETL",
                "EOL",
                .product(name: "ECore", package: "swift-ecore"),
            ],
            swiftSettings: [
                .enableUpcomingFeature("StrictConcurrency")
            ]
        ),
        .testTarget(
            name: "EGLTests",
            dependencies: [
                "EpsilonTestSupport",
                "EGL",
                "EOL",
                .product(name: "ECore", package: "swift-ecore"),
            ],
            swiftSettings: [
                .enableUpcomingFeature("StrictConcurrency")
            ]
        ),
        .testTarget(
            name: "EpsilonReferenceTests",
            dependencies: [
                "EOL",
                "EVL",
                "ETL",
                "EGL",
            ],
            swiftSettings: [
                .enableUpcomingFeature("StrictConcurrency")
            ]
        ),
    ]
)
