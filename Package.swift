// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "GlinaDesktop",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "GlinaDesktop", targets: ["GlinaDesktop"])],
    dependencies: [
        .package(url: "https://github.com/wisent-ai/wisent-components.git", exact: "0.8.1"),
        .package(url: "https://github.com/wisent-ai/wisent-desktop-update.git", exact: "0.2.0"),
        .package(url: "https://github.com/wisent-ai/wisent-errors.git", exact: "1.0.0"),
    ],
    targets: [
        .executableTarget(
            name: "GlinaDesktop",
            dependencies: [
                .product(name: "WisentDesignSystem", package: "wisent-components"),
                .product(name: "WisentDesktopUpdate", package: "wisent-desktop-update"),
                .product(name: "WisentErrors", package: "wisent-errors"),
            ],
            path: "Sources/GlinaDesktop"
        ),
    ]
)
