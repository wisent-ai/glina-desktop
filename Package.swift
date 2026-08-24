// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "GlinaDesktop",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "GlinaDesktop", targets: ["GlinaDesktop"])],
    dependencies: [
        .package(url: "https://github.com/wisent-ai/wisent-components.git", revision: "63aab577abc78c4d1993a711236479dbc2c2571a"),
        .package(url: "https://github.com/wisent-ai/wisent-desktop-update.git", exact: "0.1.0"),
        .package(url: "https://github.com/wisent-ai/wisent-errors.git", revision: "b01a0c99766b5c6378ecdbf3921108420ba058f1"),
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
