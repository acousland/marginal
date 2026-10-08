// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "Marginal",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "Marginal", targets: ["Marginal"])],
    dependencies: [.package(url: "https://github.com/swiftlang/swift-markdown.git", exact: "0.7.3")],
    targets: [
        .target(name: "MarginalCore", dependencies: [.product(name: "Markdown", package: "swift-markdown")]),
        .target(name: "MarginalApp", dependencies: ["MarginalCore"]),
        .executableTarget(name: "Marginal", dependencies: ["MarginalApp"]),
        .testTarget(name: "MarginalCoreTests", dependencies: ["MarginalCore"]),
        .testTarget(name: "MarginalAppTests", dependencies: ["MarginalApp"]),
        .testTarget(name: "MarginalUpdateTests", dependencies: ["MarginalApp"])
    ]
)
