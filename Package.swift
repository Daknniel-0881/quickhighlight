// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "CursorMagnifier",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "CursorMagnifier",
            path: "Sources/CursorMagnifier"
        )
    ]
)
