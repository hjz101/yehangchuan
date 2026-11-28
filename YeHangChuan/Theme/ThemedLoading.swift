import SwiftUI

// MARK: - 主题化加载态（P4-01）
//
// 统一 App 内所有加载指示（12 处 ProgressView 替换点在 P4-02）。
// 四种样式：spinner / brandMark / artwork / skeleton。
// 动画元素仅限小尺寸控件，不在背景层做无限循环（边界2）；
// 尊重 Reduce Motion（降级为静态），首启动画仅一次（P4-03）。

struct ThemedLoadingView: View {
    var style: LoadingStyle = .spinner
    var tint: Color = .accentColor
    var title: String?
    var reduceMotion: Bool = false

    var body: some View {
        VStack(spacing: 14) {
            indicator
            if let title {
                Text(title)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var indicator: some View {
        switch style {
        case .spinner:
            if reduceMotion {
                Image(systemName: "ellipsis")
                    .font(.title2)
                    .foregroundStyle(tint)
            } else {
                ProgressView()
                    .tint(tint)
                    .controlSize(.large)
            }
        case .brandMark:
            // 品牌标记灯焰：小尺寸旋转，Reduce Motion 下静态。
            Image(systemName: "flame.fill")
                .font(.title)
                .foregroundStyle(tint)
                .rotationEffect(reduceMotion ? .degrees(0) : .degrees(360))
                .animation(
                    reduceMotion ? nil : .linear(duration: 0.6),
                    value: reduceMotion
                )
        case .artwork:
            // 图片加载态：静态占位骨架（P3-01 资产接入前的轻量表现）。
            RoundedRectangle(cornerRadius: 12)
                .fill(tint.opacity(0.15))
                .frame(width: 120, height: 120)
                .overlay {
                    Image(systemName: "book.closed")
                        .font(.title)
                        .foregroundStyle(tint)
                }
        case .skeleton:
            VStack(spacing: 8) {
                ForEach(0..<3, id: \.self) { _ in
                    RoundedRectangle(cornerRadius: 6)
                        .fill(tint.opacity(0.12))
                        .frame(width: 220, height: 14)
                }
            }
        }
    }
}

/// 加载态 modifier：读主题令牌渲染，isLoading=false 时不占空间。
struct ThemedLoadingModifier: ViewModifier {
    let isLoading: Bool
    let label: String?

    @Environment(\.theme) private var theme
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion

    func body(content: Content) -> some View {
        ZStack {
            content
            if isLoading {
                ThemedLoadingView(
                    style: theme.loadingStyle,
                    tint: theme.loadingTint,
                    title: label,
                    reduceMotion: systemReduceMotion || !theme.transition.isAnimated
                )
                .background(theme.background.style.isSolid ? theme.loadingTint.opacity(0.05) : .clear)
                .transition(.opacity)
            }
        }
    }
}

private extension TransitionSpec {
    /// 灵动档允许小控件动画；克制/关闭一律静态。
    var isAnimated: Bool { self == .lively }
}

private extension ResolvedBackground.Style {
    var isSolid: Bool {
        if case .solid = self { return true }
        return false
    }
}

// MARK: - 内联小转圈主题化（P4-02）
//
// 12 处业务加载点多为局部小 ProgressView，直接换成全屏 ThemedLoadingView
// 会铺满父视图破坏布局。这里提供 tint 读主题的内联版本，保证换肤一致且零布局回归。

extension View {
    func themedProgress() -> some View {
        modifier(ThemedProgressModifier())
    }
}

private struct ThemedProgressModifier: ViewModifier {
    @Environment(\.theme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content.tint(theme.loadingTint)
    }
}
