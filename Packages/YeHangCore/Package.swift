// swift-tools-version: 6.0
import PackageDescription

// YeHangCore —— 夜航船自己的阅读内核。
//
// 只依赖 Foundation + CoreText：CoreText 在 macOS 与 iOS 上是同一套实现，
// 所以排版逻辑可以在 Mac 上用 `swift test` 秒级验证，不必开模拟器。
// 这里不放任何 UIKit / SwiftUI 类型，界面层通过 UIViewRepresentable 接入。
let package = Package(
    name: "YeHangCore",
    platforms: [
        .iOS(.v15),
        .macOS(.v13)
    ],
    products: [
        .library(name: "YeHangCore", targets: ["YeHangCore"])
    ],
    targets: [
        .target(name: "YeHangCore"),
        .testTarget(name: "YeHangCoreTests", dependencies: ["YeHangCore"])
    ]
)
