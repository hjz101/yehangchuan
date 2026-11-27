// swift-tools-version: 6.0
import PackageDescription

// LegadoCore —— Legado（开源阅读）3.0 书源规则的 Swift 实现。
//
// 来源：https://github.com/Aminark/legado-ios（GPL-3.0），
// 本仓库整体同为 GPL-3.0，符合其许可要求；原版权归 Aminark 及其贡献者。
// 详见仓库根目录 THIRD_PARTY_NOTICES.md 与 LICENSES/。
//
// 这里只保留 LegadoCore 这一个 target：上游的 LegadoAppModels 与 App 层
// 界面不需要，且它们会拖入 SwiftUI 依赖。
let package = Package(
    name: "LegadoCore",
    platforms: [
        .iOS(.v15),
        .macOS(.v13)
    ],
    products: [
        .library(name: "LegadoCore", targets: ["LegadoCore"])
    ],
    dependencies: [
        .package(url: "https://github.com/scinfu/SwiftSoup.git", exact: "2.13.5"),
        .package(url: "https://github.com/tid-kijyun/Kanna.git", exact: "6.1.0"),
        .package(url: "https://github.com/weichsel/ZIPFoundation.git", exact: "0.9.20")
    ],
    targets: [
        .target(
            name: "LegadoCore",
            dependencies: [
                .product(name: "SwiftSoup", package: "SwiftSoup"),
                .product(name: "Kanna", package: "Kanna"),
                .product(name: "ZIPFoundation", package: "ZIPFoundation")
            ],
            linkerSettings: [
                .linkedFramework("JavaScriptCore"),
                .linkedFramework("CryptoKit"),
                .linkedLibrary("sqlite3")
            ]
        ),
        .testTarget(
            name: "LegadoCoreTests",
            dependencies: [
                "LegadoCore",
                .product(name: "ZIPFoundation", package: "ZIPFoundation")
            ]
        )
    ]
)
