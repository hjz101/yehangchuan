import SwiftUI

// MARK: - 网格解析缓存渲染器（P1-00 性能前置）
//
// 全工程 30+ 处挂载背景。旧 AppBackdrop 在 body 里现算网格点/色数组，
// 每次切页/弹层/滚动都重建。这里改为：从 @Environment(\.theme).background
// 读一次性算好的 ResolvedBackground（ThemeEngine 解析时生成），body 只做渲染，
// 不重建数据、不加任何动画（禁 repeatForever，边界2）。

struct ThemeBackdrop: View {
    @Environment(\.theme) private var theme

    var body: some View {
        Color.clear
            .overlay {
                ZStack {
                    meshLayer
                    glowLayer
                }
            }
            .clipped()
            .allowsHitTesting(false)
            .ignoresSafeArea()
    }

    /// 纯静态网格：数据来自缓存，body 内不做任何数组变换。
    @ViewBuilder
    private var meshLayer: some View {
        switch theme.background.style {
        case .systemMesh:
            // 内置夜色水面：保留现有 3×3 静态网格（零视觉回归基准）。
            SystemMeshBackdrop()
        case let .solid(color):
            color.ignoresSafeArea()
        case let .linear(colors, start, end):
            LinearGradient(
                colors: colors,
                startPoint: start,
                endPoint: end
            )
            .ignoresSafeArea()
        case let .radial(colors, center, startRadius, endRadius):
            RadialGradient(
                colors: colors,
                center: center,
                startRadius: startRadius,
                endRadius: endRadius
            )
            .ignoresSafeArea()
        case let .mesh(points, colors, rows, cols):
            // 数据已由引擎算好并 clamp 为 [[Double]]，body 内零变换直接渲染。
            MeshGradient(width: rows, height: cols, points: points, colors: colors)
                .ignoresSafeArea()
        case let .image(assetID, mode, overlay):
            ThemeBackgroundImage(assetID: assetID, mode: mode, overlay: overlay)
        }
    }

    /// 光斑 ≤3、静态，颜色取缓存里的解析结果。
    private var glowLayer: some View {
        ZStack {
            ForEach(Array(theme.background.glows.enumerated()), id: \.offset) { _, glow in
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [glow.color.opacity(glow.opacity), .clear],
                            center: .center,
                            startRadius: 0,
                            endRadius: glow.radius
                        )
                    )
                    .frame(width: glow.radius * 2.3, height: glow.radius * 2.3)
                    .blur(radius: glow.radius * 0.12)
                    .offset(
                        x: (glow.position.x - 0.5) * 400,
                        y: (glow.position.y - 0.5) * 700
                    )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }
}

/// 内置夜色水面：从 Theme.swift 的 AppBackdrop 抄录的静态 3×3 网格 + 双光斑。
/// 独立成视图，确保默认主题下外观零变化（G0/G1 零回归基准）。
private struct SystemMeshBackdrop: View {
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        ZStack {
            mesh
            glows
        }
    }

    private var mesh: some View {
        Group {
            if scheme == .dark {
                MeshGradient(
                    width: 3, height: 3,
                    points: Self.points,
                    colors: [
                        Color(hex: 0x05080E), Color(hex: 0x081019), Color(hex: 0x0C1622),
                        Color(hex: 0x0A121C), Color(hex: 0x13202D), Color(hex: 0x1A232D),
                        Color(hex: 0x0E161E), Color(hex: 0x191D24), Color(hex: 0x2A1E15)
                    ]
                )
            } else {
                MeshGradient(
                    width: 3, height: 3,
                    points: Self.points,
                    colors: [
                        Color(hex: 0xF7F9FD), Color(hex: 0xEFF3FA), Color(hex: 0xE6EDF7),
                        Color(hex: 0xF3F6FB), Color(hex: 0xE9F0F8), Color(hex: 0xDEE7F2),
                        Color(hex: 0xEDF0F5), Color(hex: 0xE5EBF3), Color(hex: 0xF3E7DA)
                    ]
                )
            }
        }
    }

    private static let points: [[Double]] = [
        [0, 0], [0.5, 0], [1, 0],
        [0, 0.52], [0.52, 0.46], [1, 0.55],
        [0, 1], [0.48, 1], [1, 1]
    ]

    private var glows: some View {
        let isDark = scheme == .dark
        return ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [Palette.accentSolid.opacity(isDark ? 0.34 : 0.20), .clear],
                        center: .center, startRadius: 0, endRadius: 200
                    )
                )
                .frame(width: 460, height: 460)
                .blur(radius: 24)
                .offset(x: -70, y: 350)

            Circle()
                .fill(
                    RadialGradient(
                        colors: [Color(hex: 0x3F8FA8).opacity(isDark ? 0.30 : 0.16), .clear],
                        center: .center, startRadius: 0, endRadius: 190
                    )
                )
                .frame(width: 420, height: 420)
                .blur(radius: 28)
                .offset(x: 110, y: -320)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }
}

/// 图片背景占位：P3-01 资产 Store 落地后接入降采样缓存。
/// 本阶段只画纯色占位，避免首帧解码大图。
private struct ThemeBackgroundImage: View {
    let assetID: String
    let mode: ImageFillMode
    let overlay: Color?

    var body: some View {
        ZStack {
            Color.gray.opacity(0.15)
            if let overlay { overlay.ignoresSafeArea() }
        }
        .ignoresSafeArea()
    }
}
