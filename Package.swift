// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "TaskDock",
    platforms: [.macOS(.v15)],
    targets: [
        .executableTarget(name: "TaskDock", path: "Sources/TaskDock"),
        .testTarget(name: "TaskDockTests", dependencies: ["TaskDock"], path: "Tests/TaskDockTests"),
    ],
    swiftLanguageModes: [.v5]
)
