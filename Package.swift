// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "PlankaBar",
    platforms: [
        .macOS(.v13)
    ],
    targets: [
        .executableTarget(
            name: "PlankaBar",
            path: "Sources/PlankaBar"
        )
    ]
)
