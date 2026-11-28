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
        let resolved = tokens
            ?? (fallbackTheme.map { ThemeEngine.resolve(theme: $0) })
            ?? ThemeEngine.resolve(
                theme: BuiltinThemes.theme(withID: BuiltinThemes.defaultID)
                    ?? Theme(name: "默认")
            )
        return self
            .environment(\.theme, resolved)
            .preferredColorScheme(store.appearance.colorScheme)
            .eyeCareFilter(store.eyeCare)
    }

    /// 主题化加载态接口骨架（P4-01 实现具体渲染）。
    func themedLoading(isLoading: Bool, label: String? = nil) -> some View {
        // P4-01 落地：读 theme.loadingStyle/tint/background/title。
        self
    }

    /// 语义字体接口骨架（P1-04 实现批量迁移）。
    func themeFont(_ role: FontRole, size: CGFloat, weight: Font.Weight = .regular) -> some View {
        // P1-04 落地：从 @Environment(\.theme).uiFont 取字体。
        self.font(.system(size: size, weight: weight))
    }
}
