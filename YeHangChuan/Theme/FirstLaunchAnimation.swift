import SwiftUI

// MARK: - 首次进入动画（P4-03）
//
// 受限：仅首次启动显示一次（AppStorage 标记）、0.7s、可点击跳过、
// Reduce Motion 下静止、用主题令牌绘制。绝不改 Info.plist 的 UILaunchScreen，
// 不做成每启动都放的伪启动页（边界1）。

struct FirstLaunchAnimation: View {
    @AppStorage("theme.firstLaunchShown") private var shown = false
    @Environment(\.theme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var animate = false

    var body: some View {
        ZStack {
            if !shown {
                theme.background.style == .systemMesh ? AnyView(ThemeBackdrop()) : AnyView(theme.background.solidColor)
                VStack(spacing: 16) {
                    Image(systemName: "sailboat.fill")
                        .font(.system(size: 56))
                        .foregroundStyle(theme.accent)
                        .scaleEffect(animate || reduceMotion ? 1 : 0.7)
                        .opacity(animate || reduceMotion ? 1 : 0)
                    Text("夜航船")
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(theme.text)
                        .opacity(animate || reduceMotion ? 1 : 0)
                }
                .onAppear {
                    if reduceMotion {
                        finish()
                    } else {
                        withAnimation(.easeOut(duration: 0.45)) { animate = true }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) { finish() }
                    }
                }
                .onTapGesture { finish() }  // 可跳过
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(!shown)
    }

    private func finish() {
        withAnimation(.easeOut(duration: 0.2)) { shown = true }
    }
}

private extension ResolvedBackground.Style {
    /// 非 systemMesh 背景的纯色占位（首启动画只显示一次，不做完整渲染）。
    var solidColor: Color {
        if case let .solid(color) = self { return color }
        return Color.black.opacity(0.9)
    }
}

