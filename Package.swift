// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "WorkoutTimer",
    defaultLocalization: "ja",
    platforms: [
        .iOS(.v17),
        .watchOS(.v10)
    ],
    products: [
        .library(
            name: "WorkoutTimerCore",
            targets: ["WorkoutTimerCore"]),
    ],
    dependencies: [],
    targets: [
        .target(
            name: "WorkoutTimerCore",
            dependencies: [],
            path: "Shared/Sources",
            resources: [
                .process("Resources")
            ]
        ),
        .testTarget(
            name: "WorkoutTimerCoreTests",
            dependencies: ["WorkoutTimerCore"],
            path: "Shared/Tests"
        ),
    ]
)