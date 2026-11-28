import Foundation

// MARK: - 主题领域模型（P0-01）
//
// 本文件只依赖 Foundation，不引用 SwiftUI/UIKit —— 模型层不依赖任何视图。
// Color 不可 Codable，因此所有颜色以 UInt32 hex + opacity 持久化，由引擎解析。
// 所有解码一律「逐字段 decodeIfPresent ?? 默认」，非法值 clamp、数组/字符串限长，
// 沿用 Snapshot / ReaderSnapshot 的逐字段兜底惯例：坏主题不阻断整份 catalog。

/// 可持久化双档颜色。light/dark 为 sRGB hex（0xRRGGBB），opacity 限定 0...1。
struct ThemeColor: Codable, Equatable, Hashable, Sendable {
    var light: UInt32
    var dark: UInt32
    var lightOpacity: Double
    var darkOpacity: Double

    enum CodingKeys: String, CodingKey {
        case light, dark, lightOpacity, darkOpacity
    }

    init(
        light: UInt32,
        dark: UInt32,
        lightOpacity: Double = 1,
        darkOpacity: Double = 1
    ) {
        self.light = light
        self.dark = dark
        self.lightOpacity = Self.clampOpacity(lightOpacity)
        self.darkOpacity = Self.clampOpacity(darkOpacity)
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        // 缺字段回退到中性墨色，绝不让单个坏色值把整份主题带崩。
        light = (try? c.decodeIfPresent(UInt32.self, forKey: .light)) ?? 0x111A24
        dark = (try? c.decodeIfPresent(UInt32.self, forKey: .dark)) ?? 0xF4F0E8
        lightOpacity = Self.clampOpacity(
            (try? c.decodeIfPresent(Double.self, forKey: .lightOpacity)) ?? 1
        )
        darkOpacity = Self.clampOpacity(
            (try? c.decodeIfPresent(Double.self, forKey: .darkOpacity)) ?? 1
        )
    }

    static func clampOpacity(_ v: Double) -> Double {
        (v.isFinite ? v : 1).clamped(to: 0...1)
    }
}

/// 颜色的语义来源。
/// - system：跟随 Palette.adaptive 的动态 provider，系统明暗切换不重建视图。
/// - adaptive：自定义双档，由引擎包成动态 provider（见 P0-03 / 技术评审 B1）。
/// - fixed：唯一静态色档（不随明暗变化）。
enum ColorSpec: Codable, Hashable, Sendable {
    case system
    case adaptive(light: UInt32, dark: UInt32, lightOpacity: Double, darkOpacity: Double)
    case fixed(UInt32, opacity: Double)

    /// 便捷工厂：自定义双档色默认不透明（枚举 case 本身不支持默认参数）。
    static func adaptive(light: UInt32, dark: UInt32) -> ColorSpec {
        .adaptive(light: light, dark: dark, lightOpacity: 1, darkOpacity: 1)
    }

    private enum Kind: String, Codable { case system, adaptive, fixed }
    private enum CodingKeys: String, CodingKey {
        case kind, light, dark, lightOpacity, darkOpacity, hex, opacity
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let kind = (try? c.decodeIfPresent(Kind.self, forKey: .kind)) ?? .system
        switch kind {
        case .system:
            self = .system
        case .adaptive:
            self = .adaptive(
                light: (try? c.decodeIfPresent(UInt32.self, forKey: .light)) ?? 0x111A24,
                dark: (try? c.decodeIfPresent(UInt32.self, forKey: .dark)) ?? 0xF4F0E8,
                lightOpacity: ThemeColor.clampOpacity(
                    (try? c.decodeIfPresent(Double.self, forKey: .lightOpacity)) ?? 1
                ),
                darkOpacity: ThemeColor.clampOpacity(
                    (try? c.decodeIfPresent(Double.self, forKey: .darkOpacity)) ?? 1
                )
            )
        case .fixed:
            self = .fixed(
                (try? c.decodeIfPresent(UInt32.self, forKey: .hex)) ?? 0xB6402A,
                opacity: ThemeColor.clampOpacity(
                    (try? c.decodeIfPresent(Double.self, forKey: .opacity)) ?? 1
                )
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .system:
            try c.encode(Kind.system, forKey: .kind)
        case let .adaptive(light, dark, lightOp, darkOp):
            try c.encode(Kind.adaptive, forKey: .kind)
            try c.encode(light, forKey: .light)
            try c.encode(dark, forKey: .dark)
            try c.encode(lightOp, forKey: .lightOpacity)
            try c.encode(darkOp, forKey: .darkOpacity)
        case let .fixed(hex, opacity):
            try c.encode(Kind.fixed, forKey: .kind)
            try c.encode(hex, forKey: .hex)
            try c.encode(opacity, forKey: .opacity)
        }
    }
}

/// 网格/渐变中的归一化坐标，恒在 0...1。
struct ThemePoint: Codable, Equatable, Hashable, Sendable {
    var x: Double
    var y: Double

    init(x: Double, y: Double) {
        self.x = Self.clamp(x)
        self.y = Self.clamp(y)
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        x = Self.clamp((try? c.decodeIfPresent(Double.self, forKey: .x)) ?? 0)
        y = Self.clamp((try? c.decodeIfPresent(Double.self, forKey: .y)) ?? 0)
    }

    private enum CodingKeys: String, CodingKey { case x, y }
    static func clamp(_ v: Double) -> Double { (v.isFinite ? v : 0).clamped(to: 0...1) }
}

enum ImageFillMode: String, Codable, Hashable, Sendable {
    case fill, fit, stretch
}

enum FontDesignSpec: String, Codable, Hashable, Sendable {
    case `default`, serif, rounded, monospaced
}

/// 决策②：字体来源只有系统字族与用户从文件 App 导入，没有 bundled。
enum FontFamilySpec: Codable, Hashable, Sendable {
    case system(design: FontDesignSpec)
    case imported(assetID: String, postScriptName: String)

    private enum Kind: String, Codable { case system, imported }
    private enum CodingKeys: String, CodingKey {
        case kind, design, assetID, postScriptName
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let kind = (try? c.decodeIfPresent(Kind.self, forKey: .kind)) ?? .system
        switch kind {
        case .system:
            self = .system(
                design: (try? c.decodeIfPresent(FontDesignSpec.self, forKey: .design)) ?? .default
            )
        case .imported:
            let id = (try? c.decodeIfPresent(String.self, forKey: .assetID))
                ?? ""
            let name = (try? c.decodeIfPresent(String.self, forKey: .postScriptName))
                ?? ""
            // assetID 非法（非 32 hex）时视为无可用导入字体，回退系统字族。
            if AssetRef.isValidAssetID(id), !name.isEmpty {
                self = .imported(
                    assetID: id,
                    postScriptName: String(name.prefix(ThemeLimits.postScriptName))
                )
            } else {
                self = .system(design: .default)
            }
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .system(design):
            try c.encode(Kind.system, forKey: .kind)
            try c.encode(design, forKey: .design)
        case let .imported(assetID, name):
            try c.encode(Kind.imported, forKey: .kind)
            try c.encode(assetID, forKey: .assetID)
            try c.encode(name, forKey: .postScriptName)
        }
    }
}

/// 界面字体排版。阅读字号/字重/行距/版心的唯一真相仍在 ReaderSettings，
/// 由 ReaderStyleResolver 合并（技术评审 C3）——这里只承载界面字体角色。
struct TypographySpec: Codable, Equatable, Hashable, Sendable {
    var uiFamily: FontFamilySpec = .system(design: .default)
    var titleFamily: FontFamilySpec = .system(design: .serif)
    var uiScale: Double = 1          // 0.8...1.3
    var tracking: Double = 0         // D20 字距 0...2pt
    var paragraphSpacing: Double = 0 // D20 段距 0...8pt

    enum CodingKeys: String, CodingKey {
        case uiFamily, titleFamily, uiScale, tracking, paragraphSpacing
    }

    init(
        uiFamily: FontFamilySpec = .system(design: .default),
        titleFamily: FontFamilySpec = .system(design: .serif),
        uiScale: Double = 1,
        tracking: Double = 0,
        paragraphSpacing: Double = 0
    ) {
        self.uiFamily = uiFamily
        self.titleFamily = titleFamily
        self.uiScale = (uiScale.isFinite ? uiScale : 1).clamped(to: 0.8...1.3)
        self.tracking = Self.clampTracking(tracking)
        self.paragraphSpacing = Self.clampParagraphSpacing(paragraphSpacing)
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        uiFamily = (try? c.decodeIfPresent(FontFamilySpec.self, forKey: .uiFamily))
            ?? .system(design: .default)
        titleFamily = (try? c.decodeIfPresent(FontFamilySpec.self, forKey: .titleFamily))
            ?? .system(design: .serif)
        uiScale = (try? c.decodeIfPresent(Double.self, forKey: .uiScale)).flatMap {
            $0.isFinite ? $0.clamped(to: 0.8...1.3) : nil
        } ?? 1
        tracking = Self.clampTracking(
            (try? c.decodeIfPresent(Double.self, forKey: .tracking)) ?? 0
        )
        paragraphSpacing = Self.clampParagraphSpacing(
            (try? c.decodeIfPresent(Double.self, forKey: .paragraphSpacing)) ?? 0
        )
    }

    static func clampTracking(_ v: Double) -> Double {
        (v.isFinite ? v : 0).clamped(to: 0...2)
    }

    static func clampParagraphSpacing(_ v: Double) -> Double {
        (v.isFinite ? v : 0).clamped(to: 0...8)
    }
}

/// 形状与交互反馈。按压动画属控件级反馈，不违反「背景无动画」红线。
struct ShapeSpec: Codable, Equatable, Hashable, Sendable {
    var cornerRadiusScale: Double = 1     // 0.6...1.6，基准 12/18/26
    var hairlineWidth: Double = 1         // 0.5...2
    var glassTintOpacity: Double = 1      // 0.2...2（乘数）
    var glassStrength: Int = 3            // 1...5 档
    var pressScale: Double = 0.94         // 0.8...1.0
    var pressOpacity: Double = 0.92       // 0...1
    var pressSpringResponse: Double = 0.28
    var pressSpringDamping: Double = 0.7

    enum CodingKeys: String, CodingKey {
        case cornerRadiusScale, hairlineWidth, glassTintOpacity, glassStrength
        case pressScale, pressOpacity, pressSpringResponse, pressSpringDamping
    }

    init(
        cornerRadiusScale: Double = 1,
        hairlineWidth: Double = 1,
        glassTintOpacity: Double = 1,
        glassStrength: Int = 3,
        pressScale: Double = 0.94,
        pressOpacity: Double = 0.92,
        pressSpringResponse: Double = 0.28,
        pressSpringDamping: Double = 0.7
    ) {
        self.cornerRadiusScale = Self.clamp(cornerRadiusScale, 0.6...1.6, 1)
        self.hairlineWidth = Self.clamp(hairlineWidth, 0.5...2, 1)
        self.glassTintOpacity = Self.clamp(glassTintOpacity, 0.2...2, 1)
        self.glassStrength = (1...5).contains(glassStrength) ? glassStrength : 3
        self.pressScale = Self.clamp(pressScale, 0.8...1.0, 0.94)
        self.pressOpacity = ThemeColor.clampOpacity(pressOpacity)
        self.pressSpringResponse = Self.clamp(pressSpringResponse, 0.1...1.0, 0.28)
        self.pressSpringDamping = Self.clamp(pressSpringDamping, 0.1...1.0, 0.7)
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        cornerRadiusScale = Self.clamp(
            (try? c.decodeIfPresent(Double.self, forKey: .cornerRadiusScale)) ?? 1,
            0.6...1.6, 1
        )
        hairlineWidth = Self.clamp(
            (try? c.decodeIfPresent(Double.self, forKey: .hairlineWidth)) ?? 1,
            0.5...2, 1
        )
        glassTintOpacity = Self.clamp(
            (try? c.decodeIfPresent(Double.self, forKey: .glassTintOpacity)) ?? 1,
            0.2...2, 1
        )
        glassStrength = (try? c.decodeIfPresent(Int.self, forKey: .glassStrength))
            .flatMap { (1...5).contains($0) ? $0 : nil } ?? 3
        pressScale = Self.clamp(
            (try? c.decodeIfPresent(Double.self, forKey: .pressScale)) ?? 0.94,
            0.8...1.0, 0.94
        )
        pressOpacity = ThemeColor.clampOpacity(
            (try? c.decodeIfPresent(Double.self, forKey: .pressOpacity)) ?? 0.92
        )
        pressSpringResponse = Self.clamp(
            (try? c.decodeIfPresent(Double.self, forKey: .pressSpringResponse)) ?? 0.28,
            0.1...1.0, 0.28
        )
        pressSpringDamping = Self.clamp(
            (try? c.decodeIfPresent(Double.self, forKey: .pressSpringDamping)) ?? 0.7,
            0.1...1.0, 0.7
        )
    }

    private static func clamp(_ v: Double, _ range: ClosedRange<Double>, _ fallback: Double) -> Double {
        (v.isFinite ? v : fallback).clamped(to: range)
    }
}

/// 静态光斑。全工程 ≤3 个，且没有任何时间/速度/相位字段（边界2）。
struct GlowSpec: Codable, Equatable, Hashable, Sendable {
    var enabled: Bool = true
    var color: ColorSpec = .system
    var radius: Double = 180       // 16...480
    var opacity: Double = 0.5      // 0...1
    var position: ThemePoint = ThemePoint(x: 0.5, y: 0.5)

    enum CodingKeys: String, CodingKey {
        case enabled, color, radius, opacity, position
    }

    init(
        enabled: Bool = true,
        color: ColorSpec = .system,
        radius: Double = 180,
        opacity: Double = 0.5,
        position: ThemePoint = ThemePoint(x: 0.5, y: 0.5)
    ) {
        self.enabled = enabled
        self.color = color
        self.radius = (radius.isFinite ? radius : 180).clamped(to: 16...480)
        self.opacity = ThemeColor.clampOpacity(opacity)
        self.position = position
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        enabled = (try? c.decodeIfPresent(Bool.self, forKey: .enabled)) ?? true
        color = (try? c.decodeIfPresent(ColorSpec.self, forKey: .color)) ?? .system
        radius = (try? c.decodeIfPresent(Double.self, forKey: .radius)).flatMap {
            $0.isFinite ? $0.clamped(to: 16...480) : nil
        } ?? 180
        opacity = ThemeColor.clampOpacity(
            (try? c.decodeIfPresent(Double.self, forKey: .opacity)) ?? 0.5
        )
        position = (try? c.decodeIfPresent(ThemePoint.self, forKey: .position))
            ?? ThemePoint(x: 0.5, y: 0.5)
    }
}

enum TransitionSpec: String, Codable, Hashable, Sendable {
    case lively, restrained, off
}

/// 界面背景。mesh 的 rows/cols 由 points 推导：
/// rows = points.count，cols = points.first?.count，二者都须在 3...5，
/// 且 colors.count == rows * cols、每点坐标 clamp 到 0...1，否则回退 .systemMesh。
enum BackgroundSpec: Codable, Hashable, Sendable {
    case systemMesh
    case solid(ColorSpec)
    case linear(colors: [ColorSpec], start: ThemePoint, end: ThemePoint)
    case radial(colors: [ColorSpec], center: ThemePoint, startRadius: Double, endRadius: Double)
    case mesh(points: [[Double]], colors: [ColorSpec])
    case image(asset: String, mode: ImageFillMode, overlay: ColorSpec?)

    private enum Kind: String, Codable {
        case systemMesh, solid, linear, radial, mesh, image
    }
    private enum CodingKeys: String, CodingKey {
        case kind, color, colors, start, end, center
        case startRadius, endRadius, points, asset, mode, overlay
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let kind = (try? c.decodeIfPresent(Kind.self, forKey: .kind)) ?? .systemMesh
        switch kind {
        case .systemMesh:
            self = .systemMesh
        case .solid:
            self = .solid(
                (try? c.decodeIfPresent(ColorSpec.self, forKey: .color)) ?? .system
            )
        case .linear:
            let colors = Self.decodeColors(
                (try? c.decodeIfPresent([ColorSpec].self, forKey: .colors))
            )
            self = .linear(
                colors: colors,
                start: (try? c.decodeIfPresent(ThemePoint.self, forKey: .start))
                    ?? ThemePoint(x: 0, y: 0),
                end: (try? c.decodeIfPresent(ThemePoint.self, forKey: .end))
                    ?? ThemePoint(x: 1, y: 1)
            )
        case .radial:
            let colors = Self.decodeColors(
                (try? c.decodeIfPresent([ColorSpec].self, forKey: .colors))
            )
            let sr = (try? c.decodeIfPresent(Double.self, forKey: .startRadius)) ?? 0
            let er = (try? c.decodeIfPresent(Double.self, forKey: .endRadius)) ?? 200
            self = .radial(
                colors: colors,
                center: (try? c.decodeIfPresent(ThemePoint.self, forKey: .center))
                    ?? ThemePoint(x: 0.5, y: 0.5),
                startRadius: sr.isFinite ? sr.clamped(to: 0...1000) : 0,
                endRadius: er.isFinite ? er.clamped(to: 1...4000) : 200
            )
        case .mesh:
            guard let points = try? c.decodeIfPresent([[Double]].self, forKey: .points),
                  let rawColors = try? c.decodeIfPresent([ColorSpec].self, forKey: .colors),
                  Self.validMesh(points: points, colors: rawColors) else {
                self = .systemMesh
                return
            }
            let normPoints = points.map { row in
                row.map { ThemePoint.clamp($0) }
            }
            self = .mesh(points: normPoints, colors: rawColors)
        case .image:
            let rawAsset = (try? c.decodeIfPresent(String.self, forKey: .asset)) ?? ""
            // 只接受 assetID 形式，拒绝路径与 URL 前缀。
            if AssetRef.isValidAssetID(rawAsset) {
                self = .image(
                    asset: rawAsset,
                    mode: (try? c.decodeIfPresent(ImageFillMode.self, forKey: .mode)) ?? .fill,
                    overlay: try? c.decodeIfPresent(ColorSpec.self, forKey: .overlay)
                )
            } else {
                self = .systemMesh
            }
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .systemMesh:
            try c.encode(Kind.systemMesh, forKey: .kind)
        case let .solid(color):
            try c.encode(Kind.solid, forKey: .kind)
            try c.encode(color, forKey: .color)
        case let .linear(colors, start, end):
            try c.encode(Kind.linear, forKey: .kind)
            try c.encode(colors, forKey: .colors)
            try c.encode(start, forKey: .start)
            try c.encode(end, forKey: .end)
        case let .radial(colors, center, sr, er):
            try c.encode(Kind.radial, forKey: .kind)
            try c.encode(colors, forKey: .colors)
            try c.encode(center, forKey: .center)
            try c.encode(sr, forKey: .startRadius)
            try c.encode(er, forKey: .endRadius)
        case let .mesh(points, colors):
            try c.encode(Kind.mesh, forKey: .kind)
            try c.encode(points, forKey: .points)
            try c.encode(colors, forKey: .colors)
        case let .image(asset, mode, overlay):
            try c.encode(Kind.image, forKey: .kind)
            try c.encode(asset, forKey: .asset)
            try c.encode(mode, forKey: .mode)
            try c.encode(overlay, forKey: .overlay)
        }
    }

    private static func decodeColors(_ raw: [ColorSpec]?) -> [ColorSpec] {
        guard let raw else { return [.system, .system] }
        let capped = Array(raw.prefix(ThemeLimits.gradientColors))
        return capped.count >= 2 ? capped : [.system, .system]
    }

    static func validMesh(points: [[Double]], colors: [ColorSpec]) -> Bool {
        let rows = points.count
        guard (3...5).contains(rows), let cols = points.first?.count,
              (3...5).contains(cols), points.allSatisfy({ $0.count == cols }),
              colors.count == rows * cols else { return false }
        return true
    }
}

enum LoadingStyle: String, Codable, Hashable, Sendable {
    case spinner, brandMark, artwork, skeleton
}

struct LoadingStyleSpec: Codable, Equatable, Hashable, Sendable {
    var style: LoadingStyle = .spinner
    var tint: ColorSpec = .system
    var background: BackgroundSpec? = nil   // nil = 跟随界面背景
    var title: String? = nil
    var artworkAsset: String? = nil
    var respectReduceMotion: Bool = true
    var firstLaunchAnimation: Bool = false
    var transition: TransitionSpec = .restrained

    enum CodingKeys: String, CodingKey {
        case style, tint, background, title, artworkAsset
        case respectReduceMotion, firstLaunchAnimation, transition
    }

    init(
        style: LoadingStyle = .spinner,
        tint: ColorSpec = .system,
        background: BackgroundSpec? = nil,
        title: String? = nil,
        artworkAsset: String? = nil,
        respectReduceMotion: Bool = true,
        firstLaunchAnimation: Bool = false,
        transition: TransitionSpec = .restrained
    ) {
        self.style = style
        self.tint = tint
        self.background = background
        self.title = title.map { String($0.prefix(ThemeLimits.title)) }
        self.artworkAsset = artworkAsset.flatMap { AssetRef.isValidAssetID($0) ? $0 : nil }
        self.respectReduceMotion = respectReduceMotion
        self.firstLaunchAnimation = firstLaunchAnimation
        self.transition = transition
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        style = (try? c.decodeIfPresent(LoadingStyle.self, forKey: .style)) ?? .spinner
        tint = (try? c.decodeIfPresent(ColorSpec.self, forKey: .tint)) ?? .system
        background = try? c.decodeIfPresent(BackgroundSpec.self, forKey: .background)
        title = (try? c.decodeIfPresent(String.self, forKey: .title)).flatMap {
            String($0.prefix(ThemeLimits.title))
        }
        artworkAsset = (try? c.decodeIfPresent(String.self, forKey: .artworkAsset))
            .flatMap { AssetRef.isValidAssetID($0) ? $0 : nil }
        respectReduceMotion = (try? c.decodeIfPresent(Bool.self, forKey: .respectReduceMotion)) ?? true
        firstLaunchAnimation = (try? c.decodeIfPresent(Bool.self, forKey: .firstLaunchAnimation)) ?? false
        transition = (try? c.decodeIfPresent(TransitionSpec.self, forKey: .transition)) ?? .restrained
    }
}

/// 阅读背景（reader-only 模板，5 套 ReaderTheme 映射来）。
struct ReadingSurfaceSpec: Codable, Equatable, Hashable, Sendable {
    var background: ThemeColor
    var backgroundDeep: ThemeColor
    var text: ThemeColor
    var secondary: ThemeColor
    var accent: ThemeColor
    var isDark: Bool

    enum CodingKeys: String, CodingKey {
        case background, backgroundDeep, text, secondary, accent, isDark
    }

    init(
        background: ThemeColor,
        backgroundDeep: ThemeColor,
        text: ThemeColor,
        secondary: ThemeColor,
        accent: ThemeColor,
        isDark: Bool
    ) {
        self.background = background
        self.backgroundDeep = backgroundDeep
        self.text = text
        self.secondary = secondary
        self.accent = accent
        self.isDark = isDark
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        background = (try? c.decodeIfPresent(ThemeColor.self, forKey: .background))
            ?? ThemeColor(light: 0xFAF7F1, dark: 0x0D1B2A)
        backgroundDeep = (try? c.decodeIfPresent(ThemeColor.self, forKey: .backgroundDeep))
            ?? ThemeColor(light: 0xEFE9DD, dark: 0x081119)
        text = (try? c.decodeIfPresent(ThemeColor.self, forKey: .text))
            ?? ThemeColor(light: 0x1E1B16, dark: 0xD9E2EC)
        secondary = (try? c.decodeIfPresent(ThemeColor.self, forKey: .secondary))
            ?? ThemeColor(light: 0x877B69, dark: 0x6E869D)
        accent = (try? c.decodeIfPresent(ThemeColor.self, forKey: .accent))
            ?? ThemeColor(light: 0xB6402A, dark: 0xE8A76A)
        isDark = (try? c.decodeIfPresent(Bool.self, forKey: .isDark)) ?? false
    }
}

/// 与 Palette 一一对应的 13 个角色 + covers[6] + 数据分级色。
struct ColorRoles: Codable, Equatable, Hashable, Sendable {
    var accent: ThemeColor
    var accentSolid: ThemeColor
    var onAccent: ThemeColor
    var jade: ThemeColor
    var gold: ThemeColor
    var sand: ThemeColor
    var blue: ThemeColor
    var text: ThemeColor
    var secondary: ThemeColor
    var tertiary: ThemeColor
    var hairline: ThemeColor
    var faint: ThemeColor
    var glassTint: ThemeColor
    var covers: [ThemeColor]
    var dataLevels: [ThemeColor]

    enum CodingKeys: String, CodingKey {
        case accent, accentSolid, onAccent, jade, gold, sand, blue
        case text, secondary, tertiary, hairline, faint, glassTint
        case covers, dataLevels
    }

    /// 成员初始化器：缺省即「夜航·原型」的 Palette 色值，供内置主题与兜底复用。
    init(
        accent: ThemeColor = ThemeColor(light: 0xB6402A, dark: 0xFF8E63),
        accentSolid: ThemeColor = ThemeColor(light: 0xC2472B, dark: 0xF5774D),
        onAccent: ThemeColor = ThemeColor(light: 0xFFF7F2, dark: 0x2B0C04),
        jade: ThemeColor = ThemeColor(light: 0x1D6A66, dark: 0x7ED9C9),
        gold: ThemeColor = ThemeColor(light: 0x8A6A1F, dark: 0xE9C179),
        sand: ThemeColor = ThemeColor(light: 0x8A5A32, dark: 0xD8A472),
        blue: ThemeColor = ThemeColor(light: 0x2F5A8A, dark: 0x86B6E6),
        text: ThemeColor = ThemeColor(light: 0x111A24, dark: 0xF4F0E8),
        secondary: ThemeColor = ThemeColor(light: 0x5A6675, dark: 0xA7B1BE),
        tertiary: ThemeColor = ThemeColor(light: 0x87929F, dark: 0x77828F),
        hairline: ThemeColor = ThemeColor(
            light: 0x0E1720, dark: 0xFFFFFF, lightOpacity: 0.09, darkOpacity: 0.13
        ),
        faint: ThemeColor = ThemeColor(
            light: 0x0E1720, dark: 0xFFFFFF, lightOpacity: 0.05, darkOpacity: 0.07
        ),
        glassTint: ThemeColor = ThemeColor(
            light: 0xFFFFFF, dark: 0xAFD6FF, lightOpacity: 0.10, darkOpacity: 0.06
        ),
        covers: [ThemeColor]? = nil,
        dataLevels: [ThemeColor]? = nil
    ) {
        self.accent = accent
        self.accentSolid = accentSolid
        self.onAccent = onAccent
        self.jade = jade
        self.gold = gold
        self.sand = sand
        self.blue = blue
        self.text = text
        self.secondary = secondary
        self.tertiary = tertiary
        self.hairline = hairline
        self.faint = faint
        self.glassTint = glassTint
        self.covers = covers ?? ColorRoles.defaultCovers
        self.dataLevels = dataLevels ?? ColorRoles.defaultDataLevels
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func color(_ key: CodingKeys, _ fallback: ThemeColor) -> ThemeColor {
            (try? c.decodeIfPresent(ThemeColor.self, forKey: key)) ?? fallback
        }
        accent = color(.accent, ThemeColor(light: 0xB6402A, dark: 0xFF8E63))
        accentSolid = color(.accentSolid, ThemeColor(light: 0xC2472B, dark: 0xF5774D))
        onAccent = color(.onAccent, ThemeColor(light: 0xFFF7F2, dark: 0x2B0C04))
        jade = color(.jade, ThemeColor(light: 0x1D6A66, dark: 0x7ED9C9))
        gold = color(.gold, ThemeColor(light: 0x8A6A1F, dark: 0xE9C179))
        sand = color(.sand, ThemeColor(light: 0x8A5A32, dark: 0xD8A472))
        blue = color(.blue, ThemeColor(light: 0x2F5A8A, dark: 0x86B6E6))
        text = color(.text, ThemeColor(light: 0x111A24, dark: 0xF4F0E8))
        secondary = color(.secondary, ThemeColor(light: 0x5A6675, dark: 0xA7B1BE))
        tertiary = color(.tertiary, ThemeColor(light: 0x87929F, dark: 0x77828F))
        hairline = color(
            .hairline,
            ThemeColor(light: 0x0E1720, dark: 0xFFFFFF, lightOpacity: 0.09, darkOpacity: 0.13)
        )
        faint = color(
            .faint,
            ThemeColor(light: 0x0E1720, dark: 0xFFFFFF, lightOpacity: 0.05, darkOpacity: 0.07)
        )
        glassTint = color(
            .glassTint,
            ThemeColor(light: 0xFFFFFF, dark: 0xAFD6FF, lightOpacity: 0.10, darkOpacity: 0.06)
        )
        let rawCovers = (try? c.decodeIfPresent([ThemeColor].self, forKey: .covers)) ?? []
        covers = rawCovers.count == ThemeLimits.covers ? rawCovers : ColorRoles.defaultCovers
        let rawLevels = (try? c.decodeIfPresent([ThemeColor].self, forKey: .dataLevels)) ?? []
        dataLevels = (ThemeLimits.dataLevelMin...ThemeLimits.dataLevelMax).contains(rawLevels.count)
            ? rawLevels : ColorRoles.defaultDataLevels
    }

    static let defaultCovers: [ThemeColor] = [
        ThemeColor(light: 0x2B3A4C, dark: 0x131C27),
        ThemeColor(light: 0x6B4632, dark: 0x352116),
        ThemeColor(light: 0x1F5A52, dark: 0x0E2C29),
        ThemeColor(light: 0x7A382A, dark: 0x3D180F),
        ThemeColor(light: 0x3E3F5E, dark: 0x1C1D2E),
        ThemeColor(light: 0x565030, dark: 0x2A2614)
    ]

    static let defaultDataLevels: [ThemeColor] = [
        ThemeColor(light: 0xC8D4DE, dark: 0x2A3642),
        ThemeColor(light: 0x8FB6A8, dark: 0x3E6B5E),
        ThemeColor(light: 0xD8A472, dark: 0x8A5A32),
        ThemeColor(light: 0xB6402A, dark: 0xFF8E63)
    ]
}

/// 一套主题。id 稳定、不随改名变化；base 指向继承的内置主题。
struct Theme: Codable, Identifiable, Equatable, Sendable {
    var id: String
    var name: String
    var base: String?
    var builtin: Bool
    var customized: Bool
    var builtinRevision: Int
    var updatedAt: Date
    var colors: ColorRoles
    var backdrop: BackgroundSpec
    var glows: [GlowSpec]
    var reading: ReadingSurfaceSpec
    var typography: TypographySpec
    var loading: LoadingStyleSpec
    var shape: ShapeSpec

    enum CodingKeys: String, CodingKey {
        case id, name, base, builtin, customized, builtinRevision, updatedAt
        case colors, backdrop, glows, reading, typography, loading, shape
    }

    init(
        id: String = UUID().uuidString,
        name: String,
        base: String? = nil,
        builtin: Bool = false,
        customized: Bool = false,
        builtinRevision: Int = 1,
        updatedAt: Date = Date(),
        colors: ColorRoles = ColorRoles(),
        backdrop: BackgroundSpec = .systemMesh,
        glows: [GlowSpec] = [],
        reading: ReadingSurfaceSpec? = nil,
        typography: TypographySpec = TypographySpec(),
        loading: LoadingStyleSpec = LoadingStyleSpec(),
        shape: ShapeSpec = ShapeSpec()
    ) {
        self.id = id
        self.name = String(name.prefix(ThemeLimits.name))
        self.base = base
        self.builtin = builtin
        self.customized = customized
        self.builtinRevision = builtinRevision
        self.updatedAt = updatedAt
        self.colors = colors
        self.backdrop = backdrop
        self.glows = Array(glows.prefix(ThemeLimits.glows))
        self.reading = reading ?? Theme.defaultReadingSurface
        self.typography = typography
        self.loading = loading
        self.shape = shape
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decodeIfPresent(String.self, forKey: .id)).flatMap {
            $0.isEmpty ? nil : String($0.prefix(ThemeLimits.assetID))
        } ?? UUID().uuidString
        name = (try? c.decodeIfPresent(String.self, forKey: .name)).flatMap {
            $0.isEmpty ? nil : String($0.prefix(ThemeLimits.name))
        } ?? "自定义主题"
        base = (try? c.decodeIfPresent(String.self, forKey: .base)).flatMap {
            String($0.prefix(ThemeLimits.assetID))
        }
        builtin = (try? c.decodeIfPresent(Bool.self, forKey: .builtin)) ?? false
        customized = (try? c.decodeIfPresent(Bool.self, forKey: .customized)) ?? false
        builtinRevision = (try? c.decodeIfPresent(Int.self, forKey: .builtinRevision))
            .flatMap { $0 >= 0 ? $0 : nil } ?? 1
        updatedAt = (try? c.decodeIfPresent(Date.self, forKey: .updatedAt)) ?? Date()
        colors = (try? c.decodeIfPresent(ColorRoles.self, forKey: .colors)) ?? ColorRoles()
        backdrop = (try? c.decodeIfPresent(BackgroundSpec.self, forKey: .backdrop)) ?? .systemMesh
        let rawGlows = (try? c.decodeIfPresent([GlowSpec].self, forKey: .glows)) ?? []
        glows = Array(rawGlows.prefix(ThemeLimits.glows))
        reading = (try? c.decodeIfPresent(ReadingSurfaceSpec.self, forKey: .reading))
            ?? Self.defaultReadingSurface
        typography = (try? c.decodeIfPresent(TypographySpec.self, forKey: .typography))
            ?? TypographySpec()
        loading = (try? c.decodeIfPresent(LoadingStyleSpec.self, forKey: .loading))
            ?? LoadingStyleSpec()
        shape = (try? c.decodeIfPresent(ShapeSpec.self, forKey: .shape)) ?? ShapeSpec()
    }

    static let defaultReadingSurface = ReadingSurfaceSpec(
        background: ThemeColor(light: 0xFAF7F1, dark: 0x0D1B2A),
        backgroundDeep: ThemeColor(light: 0xEFE9DD, dark: 0x081119),
        text: ThemeColor(light: 0x1E1B16, dark: 0xD9E2EC),
        secondary: ThemeColor(light: 0x877B69, dark: 0x6E869D),
        accent: ThemeColor(light: 0xB6402A, dark: 0xE8A76A),
        isDark: false
    )

}

/// 资产引用。引用一律只存 assetID，绝不存绝对路径/URL。
struct AssetRef: Codable, Equatable, Hashable, Sendable {
    enum AssetKind: String, Codable, Hashable, Sendable { case image, font }

    var id: String
    var kind: AssetKind
    var ext: String
    var byteCount: Int
    var pixelWidth: Int?
    var pixelHeight: Int?

    static let allowedExtensions: Set<String> = ["png", "jpg", "jpeg", "heic", "webp", "ttf", "otf"]

    init(
        id: String,
        kind: AssetKind,
        ext: String,
        byteCount: Int,
        pixelWidth: Int? = nil,
        pixelHeight: Int? = nil
    ) {
        self.id = Self.isValidAssetID(id) ? id : ""
        self.kind = kind
        let lower = ext.lowercased()
        self.ext = Self.allowedExtensions.contains(lower) ? lower : ""
        self.byteCount = max(0, byteCount)
        self.pixelWidth = pixelWidth.flatMap { $0 > 0 ? $0 : nil }
        self.pixelHeight = pixelHeight.flatMap { $0 > 0 ? $0 : nil }
    }

    /// assetID 必须是 32 位小写 hex。这是路径穿越的硬防线（安全评审 G3）。
    static func isValidAssetID(_ id: String) -> Bool {
        id.count == 32 && id.unicodeScalars.allSatisfy { c in
            (c.value >= 48 && c.value <= 57) || (c.value >= 97 && c.value <= 102)
        }
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let rawID = (try? c.decodeIfPresent(String.self, forKey: .id)) ?? ""
        id = Self.isValidAssetID(rawID) ? rawID : ""
        kind = (try? c.decodeIfPresent(AssetKind.self, forKey: .kind)) ?? .image
        let rawExt = (try? c.decodeIfPresent(String.self, forKey: .ext)) ?? ""
        ext = Self.allowedExtensions.contains(rawExt.lowercased()) ? rawExt.lowercased() : ""
        byteCount = (try? c.decodeIfPresent(Int.self, forKey: .byteCount))
            .flatMap { $0 >= 0 ? $0 : nil } ?? 0
        pixelWidth = (try? c.decodeIfPresent(Int.self, forKey: .pixelWidth)).flatMap { $0 > 0 ? $0 : nil }
        pixelHeight = (try? c.decodeIfPresent(Int.self, forKey: .pixelHeight)).flatMap { $0 > 0 ? $0 : nil }
    }

    private enum CodingKeys: String, CodingKey {
        case id, kind, ext, byteCount, pixelWidth, pixelHeight
    }
}

/// Snapshot 里唯一的主题桥接字段（P0-06）。主题本体不并入 Snapshot。
struct ThemeSelection: Codable, Equatable, Hashable, Sendable {
    var activeThemeID: String
    var catalogSchemaVersion: Int

    enum CodingKeys: String, CodingKey { case activeThemeID, catalogSchemaVersion }

    init(activeThemeID: String, catalogSchemaVersion: Int = ThemeCatalog.currentSchemaVersion) {
        self.activeThemeID = activeThemeID
        self.catalogSchemaVersion = catalogSchemaVersion
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        activeThemeID = (try? c.decodeIfPresent(String.self, forKey: .activeThemeID))
            .flatMap { $0.isEmpty ? nil : $0 } ?? ""
        catalogSchemaVersion = (try? c.decodeIfPresent(Int.self, forKey: .catalogSchemaVersion))
            .flatMap { $0 >= 0 ? $0 : nil } ?? ThemeCatalog.currentSchemaVersion
    }
}

/// 容错解码包装器：坏主题项解成 nil 而不是让整个数组抛错。
private struct FailableTheme: Decodable {
    let value: Theme?
    init(from decoder: Decoder) throws {
        value = try? Theme(from: decoder)
    }
}

/// 主题目录索引。schemaVersion 串行升级；未来版本只读不写盘。
struct ThemeCatalog: Codable, Sendable {
    static let currentSchemaVersion = 1

    var schemaVersion: Int
    var activeThemeID: String
    var themes: [Theme]
    var assets: [AssetRef]
    var skippedThemes: [String]?
    /// 孤儿清理的持久化 pending-delete 队列（技术/运维评审 G4）：assetID + 标记时间。
    var pendingDelete: [PendingDelete]

    struct PendingDelete: Codable, Equatable, Sendable {
        var assetID: String
        var ext: String = "png"           // 记录扩展名，避免 jpg/heic/otf 等孤儿永久泄漏
        var markedAt: Date

        enum CodingKeys: String, CodingKey { case assetID, ext, markedAt }
        init(assetID: String, ext: String = "png", markedAt: Date = Date()) {
            self.assetID = assetID; self.ext = ext; self.markedAt = markedAt
        }
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            assetID = (try? c.decodeIfPresent(String.self, forKey: .assetID)) ?? ""
            ext = (try? c.decodeIfPresent(String.self, forKey: .ext))
                .flatMap { AssetRef.allowedExtensions.contains($0.lowercased()) ? $0 : nil } ?? "png"
            markedAt = (try? c.decodeIfPresent(Date.self, forKey: .markedAt)) ?? Date()
        }
    }

    enum CodingKeys: String, CodingKey {
        case schemaVersion, activeThemeID, themes, assets, skippedThemes, pendingDelete
    }

    init(
        schemaVersion: Int = currentSchemaVersion,
        activeThemeID: String,
        themes: [Theme] = [],
        assets: [AssetRef] = [],
        skippedThemes: [String]? = nil,
        pendingDelete: [PendingDelete] = []
    ) {
        self.schemaVersion = schemaVersion
        self.activeThemeID = activeThemeID
        self.themes = themes
        self.assets = assets
        self.skippedThemes = skippedThemes
        self.pendingDelete = pendingDelete
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = (try? c.decodeIfPresent(Int.self, forKey: .schemaVersion))
            .flatMap { $0 >= 0 ? $0 : nil } ?? 0
        activeThemeID = (try? c.decodeIfPresent(String.self, forKey: .activeThemeID)) ?? ""
        // 逐个主题解码：单个坏项（非对象/类型错乱）只跳过并记录，不阻断整份 catalog。
        // [Theme] 整体解码会在任一元素坏掉时整数组抛错；FailableTheme 的 try? 解包
        // 让坏元素变成 nil 并被 compactMap 丢弃（unkeyedContainer 失败不前进，不能用循环 try?）。
        let wrapped = (try? c.decodeIfPresent([FailableTheme].self, forKey: .themes)) ?? []
        let decodedThemes = wrapped.compactMap(\.value).prefix(ThemeLimits.themes)
        let localSkipped = wrapped.enumerated().filter { $0.element.value == nil }
            .map { "(invalid theme at index \($0.offset))" }
        themes = Array(decodedThemes)
        let rawAssets = (try? c.decodeIfPresent([AssetRef].self, forKey: .assets)) ?? []
        assets = Array(rawAssets.prefix(ThemeLimits.assets))
        var storedSkipped = (try? c.decodeIfPresent([String].self, forKey: .skippedThemes)) ?? []
        storedSkipped.append(contentsOf: localSkipped)
        skippedThemes = Array(storedSkipped.prefix(ThemeLimits.skippedThemes))
        let rawPending = (try? c.decodeIfPresent([PendingDelete].self, forKey: .pendingDelete)) ?? []
        pendingDelete = Array(rawPending.prefix(ThemeLimits.assets))
    }

    /// 版本升级链占位。当前只有 v1，保留串行迁移入口（数据库评审 C5）。
    static func migrate(_ catalog: ThemeCatalog, from oldVersion: Int) -> ThemeCatalog {
        var result = catalog
        var v = oldVersion
        while v < currentSchemaVersion {
            // 未来版本在此按 v 逐级迁移：v = 2 时处理 1→2 ...
            v += 1
        }
        result.schemaVersion = currentSchemaVersion
        return result
    }
}

/// .yhthm 包清单（决策④）。checksums 保留完整 256bit（安全评审 G3）。
struct ThemePackageManifest: Codable, Sendable {
    var format: String = "yhthm"
    var schemaVersion: Int = ThemeCatalog.currentSchemaVersion
    var themeID: String
    var name: String
    var checksums: [String: String]   // 相对路径 → sha256 完整 64 hex
    var createdAt: Date
    var appVersion: String
    /// 合规 C-4：主题包为纯数据，不含可执行脚本（声明字段，无行为）。
    var containsExecutableCode: Bool = false

    enum CodingKeys: String, CodingKey {
        case format, schemaVersion, themeID, name, checksums
        case createdAt, appVersion, containsExecutableCode
    }

    init(
        format: String = "yhthm",
        schemaVersion: Int = ThemeCatalog.currentSchemaVersion,
        themeID: String,
        name: String,
        checksums: [String: String],
        createdAt: Date = Date(),
        appVersion: String,
        containsExecutableCode: Bool = false
    ) {
        self.format = format
        self.schemaVersion = schemaVersion
        self.themeID = themeID
        self.name = String(name.prefix(ThemeLimits.name))
        self.checksums = checksums
        self.createdAt = createdAt
        self.appVersion = appVersion
        self.containsExecutableCode = containsExecutableCode
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        format = (try? c.decodeIfPresent(String.self, forKey: .format)) ?? "yhthm"
        schemaVersion = (try? c.decodeIfPresent(Int.self, forKey: .schemaVersion)) ?? 1
        themeID = (try? c.decodeIfPresent(String.self, forKey: .themeID)) ?? ""
        name = (try? c.decodeIfPresent(String.self, forKey: .name)).flatMap {
            String($0.prefix(ThemeLimits.name))
        } ?? "导入主题"
        let raw = (try? c.decodeIfPresent([String: String].self, forKey: .checksums)) ?? [:]
        var clean: [String: String] = [:]
        for (key, value) in raw.prefix(ThemeLimits.assets) {
            // 路径非法的 key 直接拒绝；checksum 值即使格式非法也保留，
            // 让 ThemePackage.import 的逐资产校验抛 checksumMismatch，
            // 避免「静默过滤成空校验集 → 资产绕过 SHA256」的安全漏洞（Phase5 缺陷2）。
            guard !key.contains(".."), !key.hasPrefix("/") else { continue }
            clean[key] = value
        }
        checksums = clean
        createdAt = (try? c.decodeIfPresent(Date.self, forKey: .createdAt)) ?? Date()
        appVersion = (try? c.decodeIfPresent(String.self, forKey: .appVersion)) ?? ""
        containsExecutableCode = (try? c.decodeIfPresent(Bool.self, forKey: .containsExecutableCode)) ?? false
    }
}

/// 全局字符串/数组限长表（数据库评审 C4）。
enum ThemeLimits {
    static let name = 64
    static let title = 120
    static let postScriptName = 128
    static let assetID = 32
    static let covers = 6
    static let dataLevelMin = 4
    static let dataLevelMax = 6
    static let glows = 3
    static let gradientColors = 8
    static let themes = 64
    static let assets = 512
    static let skippedThemes = 256
}

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        if self < range.lowerBound { return range.lowerBound }
        if self > range.upperBound { return range.upperBound }
        return self
    }
}
