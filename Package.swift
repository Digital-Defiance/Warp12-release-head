// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Warp12ReleaseHead",
    platforms: [.macOS(.v13)],
    dependencies: [
        .package(url: "https://github.com/migueldeicaza/SwiftTerm", from: "1.5.0"),
    ],
    targets: [
        .executableTarget(
            name: "Warp12ReleaseHead",
            dependencies: [
                .product(name: "SwiftTerm", package: "SwiftTerm"),
            ],
            path: "Sources/Warp12ReleaseHead"
        ),
    ]
)
