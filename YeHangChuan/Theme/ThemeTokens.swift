import SwiftUI

// MARK: - 环境注入与字体语义适配骨架（P0-04）
//
// 根部注入 @Environment(\.theme)，弹层必须各自接 .themedChrome(store)
// （sheet/fullScreenCover 是独立宿主，根视图环境盖不住）。
// 本任务先定义 themedLoading / themeFont 接口骨架，实现体在 P4-01 / P1-04 落地。

private struct ThemeEnvironmentKey: EnvironmentKey {
    static let defaultValue: ThemeTokens = ThemeEngine.resolve(
        theme: BuiltinThemes.theme(withID: BuiltinThemes.defaultID) ?? Theme(name: "默认")
    )
}

extension EnvironmentValues {
    var theme: ThemeTokens {
        get { self[ThemeEnvironmentKey.self] }
        set { self[ThemeEnvironmentKey.self] = newValue }
    }
}

extension View {
    /// 弹层的统一外观（appChrome 的主题版）：主题环境 + 明暗偏好 + 护眼层。
    /// 签名对齐现有 .appChrome(store)（Theme.swift:217 定义）。
    ///
    /// theme 令牌优先取显式传入（新增的编辑器 draft 预览用），否则从环境继承
    /// 根部已注入的 tokens——这样弹层无需重复解析主题，也不依赖 store 暴露主题本体。
    func themedChrome(
        _ store: AppStore,
        tokens: ThemeTokens? = nil,
        fallbackTheme: Theme? = nil
    ) -> some View {
        // sheet/fullScreenCover 是独立宿主，环境不会从根部继承，必须由这里显式注入。
        // 兜底顺序：显式 tokens > 指定主题 > 当前激活主题 > 内置默认。
        // 关键：必须用当前激活主题，否则切到自定义主题后所有弹层退回默认色（换肤不一致）。
        let active = ThemeStore.shared.activeTheme
        let resolved = tokens
            ?? (fallbackTheme.map { ThemeEngine.resolve(theme: $0) })
            ?? ThemeEngine.resolve(theme: active)
        return self
            .environment(\.theme, resolved)
            .preferredColorScheme(store.appearance.colorScheme)
            .eyeCareFilter(store.eyeCare)
    }

    /// 主题化加载态（P4-01）：读 theme.loadingStyle/tint，尊重 Reduce Motion。
    func themedLoading(isLoading: Bool, label: String? = nil) -> some View {
        modifier(ThemedLoadingModifier(isLoading: isLoading, label: label))
    }

    /// 语义字体（P1-04）：从主题 uiFont 解析器取字体。
    /// 默认主题 TypographySpec(system.default/serif, uiScale=1) 产生与
    /// `.system(size:weight:)` 完全一致的字体，观感零回归；换主题时随 uiFamily 变化。
    func themeFont(_ role: FontRole, size: CGFloat, weight: Font.Weight = .regular) -> some View {
        modifier(ThemeFontModifier(role: role, size: size, weight: weight))
    }
}

/// ViewModifier 能读 @Environment，把主题字体套到内容上。
private struct ThemeFontModifier: ViewModifier {
    let role: FontRole
    let size: CGFloat
    let weight: Font.Weight

    @Environment(\.theme) private var theme

    func body(content: Content) -> some View {
        content.font(theme.uiFont.font(for: role, size: size, weight: weight))
    }
}
