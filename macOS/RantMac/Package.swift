// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "RantMac",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "Rant", targets: ["RantMac"])],
    targets: [
        .executableTarget(
            name: "RantMac",
            path: "Sources/RantMac"
        )
    ]
)
