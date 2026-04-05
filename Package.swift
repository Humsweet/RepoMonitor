// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "RepoMonitor",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "RepoMonitor",
            path: "RepoMonitor"
        )
    ]
)
