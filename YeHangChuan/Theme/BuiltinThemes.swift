import Foundation

// MARK: - 六套内置主题预设（P0-02）
//
// 「夜航·原型」的色值逐项抄自 Theme.swift 的 Palette（零视觉回归基准）。
// 其余五套按方案 §5.7 的气质给出，均为浅/深双档；builtin=true，
// customized=false，由 ThemeStore 按 builtinRevision 刷新（未被用户改过时覆盖）。

enum BuiltinThemes {
    /// 夜航·原型 ID：Snapshot 缺失/主题损坏时的最终回退目标。
    static let defaultID = "builtin.yehang.original"
    static let builtinRevision = 1

    static let all: [Theme] = [
        yehangOriginal,
        lampOldScroll,
        celadonNightRain,
        frostHorn,
        inkSeaGoldHook,
        bambooEyeCare
    ]

    static func theme(withID id: String) -> Theme? {
        all.first { $0.id == id }
    }

    /// 判断一个 ID 是否是内置主题（一期同步回退时用）。
    static func isBuiltin(_ id: String) -> Bool {
        all.contains { $0.id == id }
    }

    // MARK: 夜航·原型（默认）

    private static let yehangOriginal = Theme(
        id: defaultID,
        name: "夜航·原型",
        builtin: true,
        builtinRevision: builtinRevision,
        colors: ColorRoles(),  // 默认即 Palette 逐色
        backdrop: .systemMesh,
        glows: [
            GlowSpec(
                enabled: true,
                color: .adaptive(light: 0xFF8E63, dark: 0xFF8E63, lightOpacity: 0.28, darkOpacity: 0.30),
                radius: 220,
                opacity: 0.5,
                position: ThemePoint(x: 0.24, y: 0.22)
            ),
            GlowSpec(
                enabled: true,
                color: .adaptive(light: 0x7ED9C9, dark: 0x7ED9C9, lightOpacity: 0.20, darkOpacity: 0.24),
                radius: 260,
                opacity: 0.5,
                position: ThemePoint(x: 0.78, y: 0.82)
            )
        ],
        reading: readerTemplate(.voyage),
        typography: TypographySpec(
            uiFamily: .system(design: .default),
            titleFamily: .system(design: .serif),
            uiScale: 1
        ),
        loading: LoadingStyleSpec(style: .spinner, tint: .system),
        shape: ShapeSpec()
    )

    // MARK: 灯下旧卷（暖纸夜读）

    private static let lampOldScroll = Theme(
        id: "builtin.lamp.oldscroll",
        name: "灯下旧卷",
        builtin: true,
        builtinRevision: builtinRevision,
        colors: ColorRoles(
            accent: ThemeColor(light: 0x9C4A22, dark: 0xD98B5C),
            accentSolid: ThemeColor(light: 0xA85429, dark: 0xE09A6C),
            jade: ThemeColor(light: 0x5C6E4A, dark: 0xA9BE8C),
            gold: ThemeColor(light: 0x967024, dark: 0xE5BE70),
            text: ThemeColor(light: 0x2E2418, dark: 0xF2E8D5),
            secondary: ThemeColor(light: 0x6B5B45, dark: 0xBCA98F),
            tertiary: ThemeColor(light: 0x8C7B63, dark: 0x8D8676),
            glassTint: ThemeColor(light: 0xFFF6E4, dark: 0x6B5535, lightOpacity: 0.16, darkOpacity: 0.10)
        ),
        backdrop: .solid(.adaptive(light: 0xF5EEE0, dark: 0x181410, lightOpacity: 1, darkOpacity: 1)),
        glows: [
            GlowSpec(
                color: .fixed(0xE8B97A, opacity: 0.22), radius: 240, opacity: 0.45,
                position: ThemePoint(x: 0.2, y: 0.18)
            )
        ],
        reading: readerTemplate(.paper),
        typography: TypographySpec(
            uiFamily: .system(design: .serif),
            titleFamily: .system(design: .serif),
            uiScale: 1,
            paragraphSpacing: 0.85
        ),
        loading: LoadingStyleSpec(style: .brandMark, tint: .system),
        shape: ShapeSpec(cornerRadiusScale: 1.05)
    )

    // MARK: 青瓷夜雨（冷青雅致）

    private static let celadonNightRain = Theme(
        id: "builtin.celadon.rain",
        name: "青瓷夜雨",
        builtin: true,
        builtinRevision: builtinRevision,
        colors: ColorRoles(
            accent: ThemeColor(light: 0x1F6F6B, dark: 0x7FD7C9),
            accentSolid: ThemeColor(light: 0x247B76, dark: 0x8FE0D2),
            onAccent: ThemeColor(light: 0xF2FBF8, dark: 0x08201C),
            jade: ThemeColor(light: 0x155C58, dark: 0x6CC5B5),
            gold: ThemeColor(light: 0x7A7638, dark: 0xD6D08C),
            blue: ThemeColor(light: 0x2E5F74, dark: 0x8FC6DA),
            text: ThemeColor(light: 0x122320, dark: 0xE6F4EF),
            secondary: ThemeColor(light: 0x4E6B65, dark: 0xA6C3BB),
            tertiary: ThemeColor(light: 0x78918A, dark: 0x7E958D),
            glassTint: ThemeColor(light: 0xE8FFFA, dark: 0x8FD8CC, lightOpacity: 0.12, darkOpacity: 0.08)
        ),
        backdrop: .mesh(
            points: [[0, 0, 0], [0.5, 0.5, 0.5], [1, 1, 1]],
            colors: Array(repeating: .adaptive(light: 0x1D3B3A, dark: 0x0E2724), count: 9)
        ),
        glows: [
            GlowSpec(color: .fixed(0x9EE6D8, opacity: 0.24), radius: 200, opacity: 0.5,
                     position: ThemePoint(x: 0.7, y: 0.3))
        ],
        reading: readerTemplate(.eye),
        typography: TypographySpec(
            uiFamily: .system(design: .rounded),
            titleFamily: .system(design: .serif),
            uiScale: 1.02
        ),
        loading: LoadingStyleSpec(style: .spinner, tint: .system),
        shape: ShapeSpec(glassStrength: 4)
    )

    // MARK: 霜天晓角（高对比浅色 / 无障碍预设）

    private static let frostHorn = Theme(
        id: "builtin.frost.horn",
        name: "霜天晓角",
        builtin: true,
        builtinRevision: builtinRevision,
        colors: ColorRoles(
            accent: ThemeColor(light: 0x8E2C18, dark: 0xFF916E),  // 加深至 4.5:1
            accentSolid: ThemeColor(light: 0x962F19, dark: 0xF5835E),
            onAccent: ThemeColor(light: 0xFFFFFF, dark: 0x1A0602),
            jade: ThemeColor(light: 0x145A56, dark: 0x86DACC),
            gold: ThemeColor(light: 0x6E5410, dark: 0xF0C878),
            text: ThemeColor(light: 0x0A1018, dark: 0xFFFFFF),
            secondary: ThemeColor(light: 0x37424F, dark: 0xC8D2DD),
            tertiary: ThemeColor(light: 0x556070, dark: 0x9AA6B3),
            hairline: ThemeColor(light: 0x0A1018, dark: 0xFFFFFF, lightOpacity: 0.18, darkOpacity: 0.22),
            glassTint: ThemeColor(light: 0xFFFFFF, dark: 0x33506B, lightOpacity: 0.22, darkOpacity: 0.12)
        ),
        backdrop: .solid(.adaptive(light: 0xFAFBFD, dark: 0x0A0E14)),
        glows: [],  // 纯色背景、无光斑
        reading: readerTemplate(.day),
        typography: TypographySpec(
            uiFamily: .system(design: .default),
            titleFamily: .system(design: .default),
            uiScale: 1.05
        ),
        loading: LoadingStyleSpec(style: .spinner, tint: .system),
        shape: ShapeSpec(hairlineWidth: 1.4, glassStrength: 5)
    )

    // MARK: 墨海金钩（深墨鎏金）

    private static let inkSeaGoldHook = Theme(
        id: "builtin.inksea.goldhook",
        name: "墨海金钩",
        builtin: true,
        builtinRevision: builtinRevision,
        colors: ColorRoles(
            accent: ThemeColor(light: 0xA8791F, dark: 0xE9BE68),
            accentSolid: ThemeColor(light: 0xB28325, dark: 0xF0C877),
            onAccent: ThemeColor(light: 0x1A1408, dark: 0x1A1206),
            jade: ThemeColor(light: 0x2E5C54, dark: 0x79B5A6),
            gold: ThemeColor(light: 0x98731E, dark: 0xF2CC7A),
            blue: ThemeColor(light: 0x334A6A, dark: 0x8FB0D6),
            text: ThemeColor(light: 0x14161C, dark: 0xEFE6D2),
            secondary: ThemeColor(light: 0x4D4F5C, dark: 0xB3A98F),
            tertiary: ThemeColor(light: 0x73757F, dark: 0x8C8572),
            glassTint: ThemeColor(light: 0xFFF4D8, dark: 0x8A6E2A, lightOpacity: 0.12, darkOpacity: 0.10)
        ),
        backdrop: .linear(
            colors: [
                .adaptive(light: 0x1C2029, dark: 0x07080B),
                .adaptive(light: 0x2A2620, dark: 0x14100A)
            ],
            start: ThemePoint(x: 0, y: 0),
            end: ThemePoint(x: 1, y: 1)
        ),
        glows: [
            GlowSpec(color: .fixed(0xE9BE68, opacity: 0.26), radius: 200, opacity: 0.5,
                     position: ThemePoint(x: 0.75, y: 0.25))
        ],
        reading: readerTemplate(.night),
        typography: TypographySpec(
            uiFamily: .system(design: .serif),
            titleFamily: .system(design: .serif),
            uiScale: 1.06
        ),
        loading: LoadingStyleSpec(style: .brandMark, tint: .system),
        shape: ShapeSpec(cornerRadiusScale: 0.95)
    )

    // MARK: 竹影护眼（低蓝光）

    private static let bambooEyeCare = Theme(
        id: "builtin.bamboo.eyecare",
        name: "竹影护眼",
        builtin: true,
        builtinRevision: builtinRevision,
        colors: ColorRoles(
            accent: ThemeColor(light: 0x3E6B45, dark: 0x91C99A),
            accentSolid: ThemeColor(light: 0x46764D, dark: 0x9FD2A8),
            onAccent: ThemeColor(light: 0xF4FAF2, dark: 0x0E1E10),
            jade: ThemeColor(light: 0x2E6047, dark: 0x82C1A0),
            gold: ThemeColor(light: 0x6E7538, dark: 0xC9D08A),
            blue: ThemeColor(light: 0x3C6070, dark: 0x91B9C6),
            text: ThemeColor(light: 0x18241A, dark: 0xE8F2E6),
            secondary: ThemeColor(light: 0x4C5F4E, dark: 0xAFC4AD),
            tertiary: ThemeColor(light: 0x758574, dark: 0x8C9F8A),
            glassTint: ThemeColor(light: 0xEFF8EC, dark: 0x8FB294, lightOpacity: 0.14, darkOpacity: 0.10)
        ),
        backdrop: .linear(
            colors: [
                .adaptive(light: 0xEAF2E7, dark: 0x111C13),
                .adaptive(light: 0xDFEBDC, dark: 0x0A140D)
            ],
            start: ThemePoint(x: 0, y: 0),
            end: ThemePoint(x: 0.6, y: 1)
        ),
        glows: [
            GlowSpec(color: .fixed(0x9BCF9E, opacity: 0.20), radius: 220, opacity: 0.4,
                     position: ThemePoint(x: 0.3, y: 0.75))
        ],
        reading: readerTemplate(.eye),
        typography: TypographySpec(
            uiFamily: .system(design: .default),
            titleFamily: .system(design: .rounded),
            uiScale: 1
        ),
        loading: LoadingStyleSpec(style: .spinner, tint: .system),
        shape: ShapeSpec()
    )

    // MARK: 5 套 ReaderTheme → reader-only 模板

    /// 与业务层 ReaderTheme 的 rawValue 对应（day/paper/eye/voyage/night）。
    enum ReaderPreset: String {
        case day, paper, eye, voyage, night
    }

    static func readerTemplate(_ preset: ReaderPreset) -> ReadingSurfaceSpec {
        switch preset {
        case .day:
            return ReadingSurfaceSpec(
                background: ThemeColor(light: 0xFAF7F1, dark: 0xFAF7F1),
                backgroundDeep: ThemeColor(light: 0xEFE9DD, dark: 0xEFE9DD),
                text: ThemeColor(light: 0x1E1B16, dark: 0x1E1B16),
                secondary: ThemeColor(light: 0x877B69, dark: 0x877B69),
                accent: ThemeColor(light: 0xB6402A, dark: 0xB6402A),
                isDark: false
            )
        case .paper:
            return ReadingSurfaceSpec(
                background: ThemeColor(light: 0xF0E4CB, dark: 0xF0E4CB),
                backgroundDeep: ThemeColor(light: 0xE2D1B0, dark: 0xE2D1B0),
                text: ThemeColor(light: 0x3A2D1D, dark: 0x3A2D1D),
                secondary: ThemeColor(light: 0x8C7656, dark: 0x8C7656),
                accent: ThemeColor(light: 0x96502C, dark: 0x96502C),
                isDark: false
            )
        case .eye:
            return ReadingSurfaceSpec(
                background: ThemeColor(light: 0xE7EFE3, dark: 0xE7EFE3),
                backgroundDeep: ThemeColor(light: 0xD3E1CE, dark: 0xD3E1CE),
                text: ThemeColor(light: 0x263829, dark: 0x263829),
                secondary: ThemeColor(light: 0x667865, dark: 0x667865),
                accent: ThemeColor(light: 0x4F7A55, dark: 0x4F7A55),
                isDark: false
            )
        case .voyage:
            return ReadingSurfaceSpec(
                background: ThemeColor(light: 0x0D1B2A, dark: 0x0D1B2A),
                backgroundDeep: ThemeColor(light: 0x081119, dark: 0x081119),
                text: ThemeColor(light: 0xD9E2EC, dark: 0xD9E2EC),
                secondary: ThemeColor(light: 0x6E869D, dark: 0x6E869D),
                accent: ThemeColor(light: 0xE8A76A, dark: 0xE8A76A),
                isDark: true
            )
        case .night:
            return ReadingSurfaceSpec(
                background: ThemeColor(light: 0x101013, dark: 0x101013),
                backgroundDeep: ThemeColor(light: 0x08080A, dark: 0x08080A),
                text: ThemeColor(light: 0xC9C4BA, dark: 0xC9C4BA),
                secondary: ThemeColor(light: 0x7A766D, dark: 0x7A766D),
                accent: ThemeColor(light: 0xB49C7E, dark: 0xB49C7E),
                isDark: true
            )
        }
    }
}
