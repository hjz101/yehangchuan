import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

// 本地私有扩展：与 Theme.swift 的 Palette 辅助保持同值，避免引擎依赖视图层文件。
#if canImport(UIKit)
private extension UIColor {
    convenience init(themeHex hex: UInt32) {
        self.init(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }
}
#endif

private extension Color {
    init(themeHex hex: UInt32, opacity: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: opacity
        )
    }
}

// MARK: - 主题引擎与解析（P0-03）
//
// 配置 + ColorScheme → ThemeTokens。技术评审 B1 的落点：
// ColorSpec.adaptive / .system 全部包成 UIColor 动态 provider（trait-responsive），
// 系统明暗切换零重建、不 bump revision；revision 只表示「主题配置真的变了」，
// 保证 P2-03 的「纯换色 rebuild=0」。

/// 解析后的网格背景：点/色数组一次性算好，30+ 处 ThemeBackdrop 共享同一份缓存（P1-00 落地）。
struct ResolvedBackground: Equatable {
    enum Style: Equatable {
        case systemMesh
        case solid(Color)
        case linear(colors: [Color], start: CGPoint, end: CGPoint)
        case radial(colors: [Color], center: CGPoint, startRadius: CGFloat, endRadius: CGFloat)
        case mesh(points: [[Double]], colors: [Color], rows: Int, cols: Int)
        case image(assetID: String, mode: ImageFillMode, overlay: Color?)
    }

    var style: Style
    var glows: [ResolvedGlow]

    struct ResolvedGlow: Equatable {
        var color: Color
        var radius: CGFloat
        var opacity: Double
        var position: CGPoint
    }
}

/// 解析后的阅读样式（供 P2-03 消费）。
struct ResolvedReaderStyle: Equatable {
    var background: Color
    var backgroundDeep: Color
    var text: Color
    var secondary: Color
    var accent: Color
    var isDark: Bool
}

/// 字体语义角色（P1-04 迁移用；本任务只定义解析，不改业务视图）。
enum FontRole: Hashable, Sendable {
    case appTitle, appBody, appCaption, readerBody
}

/// 字体解析器：界面字体跟随主题，阅读正文由 P2-03 单独处理。
struct FontRoleResolver: Equatable {
    var uiFamily: FontFamilySpec
    var titleFamily: FontFamilySpec
    var uiScale: Double

    func font(for role: FontRole, size: CGFloat, weight: Font.Weight = .regular) -> Font {
        let family: FontFamilySpec
        switch role {
        case .appTitle: family = titleFamily
        case .appBody, .appCaption, .readerBody: family = uiFamily
        }
        let scaled = size * CGFloat(uiScale)
        switch family {
        case let .system(design):
            return Font.system(size: scaled, weight: weight, design: Self.design(design))
        case let .imported(_, postScriptName):
            // 注册失败时 Font.custom 会回退系统字体，不会空白（P2-04 保证注册链）。
            return Font.custom(postScriptName, size: scaled).weight(weight)
        }
    }

    private static func design(_ spec: FontDesignSpec) -> Font.Design {
        switch spec {
        case .default: return .default
        case .serif: return .serif
        case .rounded: return .rounded
        case .monospaced: return .monospaced
        }
    }
}

/// 解析后的令牌。Equatable 只比 revision（Color/Font 不可深比较）。
struct ThemeTokens: Equatable {
    var revision: Int
    var accent: Color
    var accentSolid: Color
    var onAccent: Color
    var jade: Color
    var gold: Color
    var sand: Color
    var blue: Color
    var text: Color
    var secondary: Color
    var tertiary: Color
    var hairline: Color
    var faint: Color
    var glassTint: Color
    var covers: [Color]
    /// 封面渐变的深档（与 covers 一一对应），对齐旧 Palette.cover(_:) 的双 hex。
    var coversDeep: [Color]
    var dataLevels: [Color]
    var background: ResolvedBackground
    var reader: ResolvedReaderStyle
    var uiFont: FontRoleResolver
    var shape: ShapeSpec
    var loadingStyle: LoadingStyle
    var loadingTint: Color
    var transition: TransitionSpec
    /// Warnings 不参与 Equatable（只比 revision）。
    var contrastWarnings: [String] = []

    static func == (lhs: ThemeTokens, rhs: ThemeTokens) -> Bool {
        lhs.revision == rhs.revision
    }
}

enum ThemeEngine {
    /// 解析配置。scheme 参数保留给「需要立即取具体色」的场景（截图/对比度校验），
    /// 但常规 Color 全部走动态 provider，故同一 revision 在明暗切换时不重建。
    static func resolve(theme: Theme, scheme: ColorScheme = .light) -> ThemeTokens {
        let c = theme.colors
        let tokens = ThemeTokens(
            revision: revision(of: theme),
            accent: color(c.accent, scheme: scheme),
            accentSolid: color(c.accentSolid, scheme: scheme),
            onAccent: color(c.onAccent, scheme: scheme),
            jade: color(c.jade, scheme: scheme),
            gold: color(c.gold, scheme: scheme),
            sand: color(c.sand, scheme: scheme),
            blue: color(c.blue, scheme: scheme),
            text: color(c.text, scheme: scheme),
            secondary: color(c.secondary, scheme: scheme),
            tertiary: color(c.tertiary, scheme: scheme),
            hairline: color(c.hairline, scheme: scheme),
            faint: color(c.faint, scheme: scheme),
            glassTint: color(c.glassTint, scheme: scheme),
            covers: c.covers.map { color(ThemeColor(light: $0.light, dark: $0.light), scheme: scheme) },
            coversDeep: c.covers.map { color(ThemeColor(light: $0.dark, dark: $0.dark), scheme: scheme) },
            dataLevels: c.dataLevels.map { color($0, scheme: scheme) },
            background: resolveBackground(theme.backdrop, glows: theme.glows, scheme: scheme),
            reader: resolveReader(theme.reading, scheme: scheme),
            uiFont: FontRoleResolver(
                uiFamily: theme.typography.uiFamily,
                titleFamily: theme.typography.titleFamily,
                uiScale: theme.typography.uiScale
            ),
            shape: theme.shape,
            loadingStyle: theme.loading.style,
            loadingTint: color(theme.loading.tint, scheme: scheme),
            transition: theme.loading.transition
        )
        var result = tokens
        result.contrastWarnings = contrastWarnings(for: result)
        return result
    }

    // MARK: 颜色解析

    /// 关键：adaptive 与 system 都包成 UIColor 动态 provider——
    /// 系统明暗切换由 trait 驱动，token 内 Color 自身响应，不重建视图（B1）。
    static func color(_ spec: ColorSpec, scheme: ColorScheme = .light) -> Color {
        switch spec {
        case .system:
            #if canImport(UIKit)
            // .system 语义：跟随 Palette 的默认动态行为，这里用中性墨色 provider。
            // 具体业务色由 Palette 兼容壳提供（P1-01），令牌层只保留可覆盖的动态色。
            return Color(uiColor: UIColor { (traits: UITraitCollection) -> UIColor in
                traits.userInterfaceStyle == .dark
                    ? UIColor(themeHex: 0xF4F0E8)
                    : UIColor(themeHex: 0x111A24)
            })
            #else
            return scheme == .dark
                ? Color(themeHex: 0xF4F0E8) : Color(themeHex: 0x111A24)
            #endif
        case let .adaptive(light, dark, lightOpacity, darkOpacity):
            #if canImport(UIKit)
            return Color(uiColor: UIColor { (traits: UITraitCollection) -> UIColor in
                traits.userInterfaceStyle == .dark
                    ? UIColor(themeHex: dark).withAlphaComponent(darkOpacity)
                    : UIColor(themeHex: light).withAlphaComponent(lightOpacity)
            })
            #else
            return scheme == .dark
                ? Color(themeHex: dark, opacity: darkOpacity)
                : Color(themeHex: light, opacity: lightOpacity)
            #endif
        case let .fixed(hex, opacity):
            return Color(themeHex: hex, opacity: opacity)
        }
    }

    static func color(_ tc: ThemeColor, scheme: ColorScheme) -> Color {
        #if canImport(UIKit)
        let light = UIColor(themeHex: tc.light).withAlphaComponent(tc.lightOpacity)
        let dark = UIColor(themeHex: tc.dark).withAlphaComponent(tc.darkOpacity)
        return Color(uiColor: UIColor { (traits: UITraitCollection) -> UIColor in
            traits.userInterfaceStyle == .dark ? dark : light
        })
        #else
        return scheme == .dark
            ? Color(themeHex: tc.dark, opacity: tc.darkOpacity)
            : Color(themeHex: tc.light, opacity: tc.lightOpacity)
        #endif
    }

    // MARK: 背景解析

    static func resolveBackground(
        _ spec: BackgroundSpec,
        glows: [GlowSpec],
        scheme: ColorScheme
    ) -> ResolvedBackground {
        let style: ResolvedBackground.Style
        switch spec {
        case .systemMesh:
            style = .systemMesh
        case let .solid(c):
            style = .solid(color(c, scheme: scheme))
        case let .linear(colors, start, end):
            style = .linear(
                colors: colors.map { color($0, scheme: scheme) },
                start: CGPoint(x: start.x, y: start.y),
                end: CGPoint(x: end.x, y: end.y)
            )
        case let .radial(colors, center, sr, er):
            style = .radial(
                colors: colors.map { color($0, scheme: scheme) },
                center: CGPoint(x: center.x, y: center.y),
                startRadius: CGFloat(sr),
                endRadius: CGFloat(er)
            )
        case let .mesh(points, colors):
            let rows = points.count
            let cols = points.first?.count ?? 0
            // points 已由模型层 clamp 到 0...1 且点数校验通过，直接缓存，
            // 渲染器 body 内不做任何数组变换（P1-00 性能红线）。
            style = .mesh(
                points: points,
                colors: colors.map { color($0, scheme: scheme) },
                rows: rows,
                cols: cols
            )
        case let .image(assetID, mode, overlay):
            style = .image(
                assetID: assetID,
                mode: mode,
                overlay: overlay.map { color($0, scheme: scheme) }
            )
        }

        let resolvedGlows = glows.filter(\.enabled).prefix(ThemeLimits.glows).map { g in
            ResolvedBackground.ResolvedGlow(
                color: color(g.color, scheme: scheme),
                radius: CGFloat(g.radius),
                opacity: g.opacity,
                position: CGPoint(x: g.position.x, y: g.position.y)
            )
        }
        return ResolvedBackground(style: style, glows: Array(resolvedGlows))
    }

    static func resolveReader(_ spec: ReadingSurfaceSpec, scheme: ColorScheme) -> ResolvedReaderStyle {
        ResolvedReaderStyle(
            background: color(spec.background, scheme: scheme),
            backgroundDeep: color(spec.backgroundDeep, scheme: scheme),
            text: color(spec.text, scheme: scheme),
            secondary: color(spec.secondary, scheme: scheme),
            accent: color(spec.accent, scheme: scheme),
            isDark: spec.isDark
        )
    }

    // MARK: Revision

    /// 只由配置决定，不含 scheme——明暗切换不 bump（B1）。
    /// 用稳定字符串散列，避免 Color/Font 深比较。
    static func revision(of theme: Theme) -> Int {
        var hasher = Hasher()
        hasher.combine(theme.id)
        hasher.combine(theme.name)
        hasher.combine(theme.builtinRevision)
        hasher.combine(theme.customized)
        hasher.combine(theme.colors)
        hasher.combine(theme.backdrop)
        hasher.combine(theme.glows)
        hasher.combine(theme.reading)
        hasher.combine(theme.typography)
        hasher.combine(theme.loading)
        hasher.combine(theme.shape)
        return hasher.finalize()
    }

    // MARK: 对比度校验（WCAG 相对亮度线性化，只输出警告不强制拒绝）

    struct ContrastResult {
        var ratio: Double
        var passesBody: Bool   // ≥4.5
        var passesLarge: Bool  // ≥3.0
    }

    /// 输入为 sRGB hex（0xRRGGBB），返回 WCAG 2.1 对比度。
    static func contrastRatio(foreground: UInt32, background: UInt32) -> Double {
        let f = relativeLuminance(foreground)
        let b = relativeLuminance(background)
        let lighter = max(f, b)
        let darker = min(f, b)
        return (lighter + 0.05) / (darker + 0.05)
    }

    static func contrast(_ foreground: UInt32, _ background: UInt32) -> ContrastResult {
        let ratio = contrastRatio(foreground: foreground, background: background)
        return ContrastResult(
            ratio: ratio,
            passesBody: ratio >= 4.5,
            passesLarge: ratio >= 3.0
        )
    }

    /// sRGB 逐通道线性化（非简单灰度均值）。
    static func relativeLuminance(_ hex: UInt32) -> Double {
        func channel(_ v: Double) -> Double {
            v <= 0.03928 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4)
        }
        let r = channel(Double((hex >> 16) & 0xFF) / 255)
        let g = channel(Double((hex >> 8) & 0xFF) / 255)
        let b = channel(Double(hex & 0xFF) / 255)
        return 0.2126 * r + 0.7152 * g + 0.0722 * b
    }

    /// 只输出警告列表，不拒绝配置（与 P3-04「一键修正」配合）。
    /// tokens 侧不留存配置 hex，真实校验由编辑器/门禁调用 `warnings(pairs:)`，
    /// 传入主题配置里的具体色对（含护眼叠加后的最坏值）。
    static func contrastWarnings(for tokens: ThemeTokens) -> [String] {
        // 令牌层不持有 hex；保留接口供 P3-04 注入成对校验结果。
        []
    }

    /// 对一组「前景/背景 hex + 最小倍率」产出警告，供编辑器与 G4 无障碍核验复用。
    static func warnings(pairs: [(name: String, fg: UInt32, bg: UInt32, min: Double)]) -> [String] {
        pairs.compactMap { pair in
            contrastRatio(foreground: pair.fg, background: pair.bg) < pair.min
                ? "\(pair.name) 对比度不足（要求 \(pair.min):1）"
                : nil
        }
    }
}
