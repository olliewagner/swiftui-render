// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "swiftui-render",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "swiftui-render", targets: ["SwiftUIRender"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.3.0"),
    ],
    targets: [
        .executableTarget(
            name: "SwiftUIRender",
            dependencies: [
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ],
            path: "Sources/SwiftUIRender"
        ),
        .testTarget(
            name: "SwiftUIRenderTests",
            dependencies: ["SwiftUIRender"],
            path: "Tests"
        ),
    ]
)
