import Foundation

// MARK: - 阅读样式继承/覆盖解析（P2-01）
//
// 优先级（高→低）：阅读页显式覆盖 > 阅读页选中预设 > 全局主题 > 内置默认。
// 字族独立：fontFollowGlobal 控制字族是否跟随全局；字号/字重/行距/版心
// 的唯一真相仍在 ReaderSettings（技术评审 C3），本解析器只读不写。

/// 阅读页对主题的覆盖设置（P2-02 并入 ReaderSettings）。
/// 逐字段兜底；旧 ReaderSnapshot 缺字段时 followGlobalTheme=true（行为与今天一致）。
struct ReaderThemeOverride: Codable, Equatable, Hashable, Sendable {
    var followGlobalTheme: Bool = true
    var preset: ReaderPresetID? = nil
    var customBackground: ReaderSurfaceOverride? = nil
    var fontFollowGlobal: Bool = true

    enum CodingKeys: String, CodingKey {
        case followGlobalTheme, preset, customBackground, fontFollowGlobal
    }

    init(
        followGlobalTheme: Bool = true,
        preset: ReaderPresetID? = nil,
        customBackground: ReaderSurfaceOverride? = nil,
        fontFollowGlobal: Bool = true
    ) {
        self.followGlobalTheme = followGlobalTheme
        self.preset = preset
        self.customBackground = customBackground
        self.fontFollowGlobal = fontFollowGlobal
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        followGlobalTheme = (try? c.decodeIfPresent(Bool.self, forKey: .followGlobalTheme)) ?? true
        preset = try? c.decodeIfPresent(ReaderPresetID.self, forKey: .preset)
        customBackground = try? c.decodeIfPresent(ReaderSurfaceOverride.self, forKey: .customBackground)
        fontFollowGlobal = (try? c.decodeIfPresent(Bool.self, forKey: .fontFollowGlobal)) ?? true
    }
}

/// 5 套 reader-only 预设的持久化 ID（与业务层 ReaderTheme.rawValue 对应）。
enum ReaderPresetID: String, Codable, Hashable, Sendable {
    case day, paper, eye, voyage, night
}

/// 阅读背景的自定义覆盖（reader-only，不影响界面主题）。
struct ReaderSurfaceOverride: Codable, Equatable, Hashable, Sendable {
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
        let fallback = BuiltinThemes.readerTemplate(.voyage)
        background = (try? c.decodeIfPresent(ThemeColor.self, forKey: .background)) ?? fallback.background
        backgroundDeep = (try? c.decodeIfPresent(ThemeColor.self, forKey: .backgroundDeep)) ?? fallback.backgroundDeep
        text = (try? c.decodeIfPresent(ThemeColor.self, forKey: .text)) ?? fallback.text
        secondary = (try? c.decodeIfPresent(ThemeColor.self, forKey: .secondary)) ?? fallback.secondary
        accent = (try? c.decodeIfPresent(ThemeColor.self, forKey: .accent)) ?? fallback.accent
        isDark = (try? c.decodeIfPresent(Bool.self, forKey: .isDark)) ?? fallback.isDark
    }
}

/// 解析结果：色板来自哪一层 + 字族是否跟随全局。
struct ReaderStyleResolution: Equatable {
    var surface: ReadingSurfaceSpec
    var fontFamily: FontFamilySpec
    var usedSource: Source

    enum Source: String, Hashable, Sendable {
        case custom, preset, global, builtinDefault
    }
}

enum ReaderStyleResolver {
    /// 全局主题（Theme）+ 阅读覆盖 → 最终阅读样式。
    static func resolve(global: Theme, override: ReaderThemeOverride) -> ReaderStyleResolution {
        let builtinDefault = BuiltinThemes.readerTemplate(.voyage)
        let globalSurface = global.reading

        // 色板优先级：显式自定义 > 预设 > 全局主题 > 内置默认
        var surface: ReadingSurfaceSpec
        var source: ReaderStyleResolution.Source

        if !override.followGlobalTheme, let custom = override.customBackground {
            surface = ReadingSurfaceSpec(
                background: custom.background,
                backgroundDeep: custom.backgroundDeep,
                text: custom.text,
                secondary: custom.secondary,
                accent: custom.accent,
                isDark: custom.isDark
            )
            source = .custom
        } else if !override.followGlobalTheme, let preset = override.preset,
                  let mapped = BuiltinThemes.ReaderPreset(rawValue: preset.rawValue) {
            surface = BuiltinThemes.readerTemplate(mapped)
            source = .preset
        } else {
            // 跟随全局：全局主题有 reading 就用它，否则回退内置默认。
            surface = globalSurface
            source = globalSurface == builtinDefault ? .builtinDefault : .global
        }

        // 字族独立：fontFollowGlobal=true 用全局 typography.uiFamily，否则用系统默认。
        let fontFamily: FontFamilySpec = override.fontFollowGlobal
            ? global.typography.uiFamily
            : .system(design: .default)

        return ReaderStyleResolution(surface: surface, fontFamily: fontFamily, usedSource: source)
    }

    /// 恢复跟随全局：清空所有覆盖维度。
    static func followGlobal() -> ReaderThemeOverride {
        ReaderThemeOverride()
    }
}
