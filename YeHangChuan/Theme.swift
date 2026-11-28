import SwiftUI
import UIKit

// MARK: - Color

extension UIColor {
    convenience init(hex: UInt32) {
        self.init(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }
}

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: opacity
        )
    }

    /// 跟随系统明暗自动切换的双色令牌
    static func adaptive(
        light: UInt32,
        dark: UInt32,
        lightOpacity: Double = 1,
        darkOpacity: Double = 1
    ) -> Color {
        Color(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(hex: dark).withAlphaComponent(darkOpacity)
                : UIColor(hex: light).withAlphaComponent(lightOpacity)
        })
    }
}

// MARK: - Design Tokens

/// 已弃用（P1-01）：全局主题后的内置默认常量壳。
/// 保留 enum + 静态常量形态与全部数值，作为零视觉回归基准和未迁移代码/预览的兜底。
/// 新代码一律用 `@Environment(\.theme)` 的令牌，不要再直接引用 Palette。
/// 注：这里只加文档注释、不加 @available(deprecated)，避免 481 处既有引用产生编译警告。
enum Palette {
    // 灯焰
    static let accent = Color.adaptive(light: 0xB6402A, dark: 0xFF8E63)
    static let accentSolid = Color.adaptive(light: 0xC2472B, dark: 0xF5774D)
    static let onAccent = Color.adaptive(light: 0xFFF7F2, dark: 0x2B0C04)

    // 水色
    static let jade = Color.adaptive(light: 0x1D6A66, dark: 0x7ED9C9)
    // 旧金
    static let gold = Color.adaptive(light: 0x8A6A1F, dark: 0xE9C179)
    // 船木与暮蓝，用于实验室等需要第三、第四色的入口
    static let sand = Color.adaptive(light: 0x8A5A32, dark: 0xD8A472)
    static let blue = Color.adaptive(light: 0x2F5A8A, dark: 0x86B6E6)

    // 墨色层次
    static let text = Color.adaptive(light: 0x111A24, dark: 0xF4F0E8)
    static let secondary = Color.adaptive(light: 0x5A6675, dark: 0xA7B1BE)
    static let tertiary = Color.adaptive(light: 0x87929F, dark: 0x77828F)

    static let hairline = Color.adaptive(
        light: 0x0E1720, dark: 0xFFFFFF, lightOpacity: 0.09, darkOpacity: 0.13
    )
    static let faint = Color.adaptive(
        light: 0x0E1720, dark: 0xFFFFFF, lightOpacity: 0.05, darkOpacity: 0.07
    )

    /// 玻璃上叠加的极浅底色，用于让卡片在浅色背景上仍能分层
    static let glassTint = Color.adaptive(
        light: 0xFFFFFF, dark: 0xAFD6FF, lightOpacity: 0.10, darkOpacity: 0.06
    )

    // 封面配色
    private static let covers: [(UInt32, UInt32)] = [
        (0x2B3A4C, 0x131C27),
        (0x6B4632, 0x352116),
        (0x1F5A52, 0x0E2C29),
        (0x7A382A, 0x3D180F),
        (0x3E3F5E, 0x1C1D2E),
        (0x565030, 0x2A2614)
    ]

    static func cover(_ style: Int) -> (Color, Color) {
        let pair = covers[abs(style) % covers.count]
        return (Color(hex: pair.0), Color(hex: pair.1))
    }
}

// MARK: - Ambient Backdrop

/// 夜色水面：网格渐变 + 两团柔和的光斑，为液态玻璃提供可折射的内容。
///
/// 这里刻意**不做动画**。背景是每个页面、每个弹层都会挂一层的东西
/// （全工程 30 多处），一旦它带 `repeatForever` 的漂移，应用就永远不会有
/// 静止帧：切页、弹面板、滚动都在和它抢同一帧的预算，卡顿就是这么来的。
/// 网格渐变与两团径向渐变本身就是静态的，去掉动画后外观几乎无差别，
/// 但整机功耗与切换手感完全是两回事。
struct AppBackdrop: View {
    /// P1-01：背景读主题令牌。默认主题下与旧实现（夜色水面 3×3 网格 + 双光斑）
    /// 逐色一致；换主题时随令牌换肤。静态、无动画（边界2）。
    var body: some View {
        ThemeBackdrop()
    }
}

/// 全局暖色滤光与亮度层。只做视觉压低，不拦截触摸。
struct EyeCareLayer: View {
    let settings: EyeCareSettings

    var body: some View {
        if settings.enabled {
            ZStack {
                Color(hex: 0xFF9E4A)
                    .opacity(settings.warmth * 0.3)
                Color.black
                    .opacity(settings.dim * 1.5)
            }
            .ignoresSafeArea()
            .allowsHitTesting(false)
        }
    }
}

extension View {
    /// 给一个页面叠上护眼层。
    ///
    /// sheet / fullScreenCover 都是独立的展示宿主，根视图上挂的护眼层
    /// 盖不住它们；明暗偏好也不能只靠根部 `.preferredColorScheme` 传下去，
    /// 所以每个弹层都要自己接这份外观。
    func eyeCareFilter(_ settings: EyeCareSettings) -> some View {
        overlay { EyeCareLayer(settings: settings) }
    }

    /// 弹层的统一外观：跟随 App 的明暗偏好，并叠上护眼层。
    func appChrome(_ store: AppStore) -> some View {
        preferredColorScheme(store.appearance.colorScheme)
            .eyeCareFilter(store.eyeCare)
    }
}

// MARK: - Glass

extension View {
    /// 液态玻璃表面
    func glassSurface(
        cornerRadius: CGFloat = 26,
        tint: Color? = nil,
        interactive: Bool = false
    ) -> some View {
        modifier(GlassSurfaceModifier(cornerRadius: cornerRadius, tint: tint, interactive: interactive))
    }

    /// 圆形玻璃按钮底座
    func glassCircle(diameter: CGFloat, tint: Color? = nil) -> some View {
        frame(width: diameter, height: diameter)
            .glassEffect(Glass.regular.tint(tint), in: Circle())
    }

    /// 用于提示条、状态胶囊
    func glassCapsule(tint: Color? = nil, interactive: Bool = false) -> some View {
        glassEffect(
            Glass.regular.tint(tint).interactive(interactive),
            in: Capsule(style: .continuous)
        )
    }
}

/// 液态玻璃 + 极细高光描边，让卡片在浅色背景上也能勾出层次
private struct GlassSurfaceModifier: ViewModifier {
    let cornerRadius: CGFloat
    let tint: Color?
    let interactive: Bool

    @Environment(\.colorScheme) private var scheme
    @Environment(\.theme) private var theme

    func body(content: Content) -> some View {
        // P1-02：圆角/描边读 ShapeSpec。默认 scale=1、hairline=1，观感零变化。
        let radius = cornerRadius * CGFloat(theme.shape.cornerRadiusScale)
        let hairline = 0.7 * CGFloat(theme.shape.hairlineWidth)
        // tint 为 nil 时保持系统默认玻璃（零回归）；显式传入的色由调用点在 P1-03 迁移。
        content
            .glassEffect(
                Glass.regular.tint(tint).interactive(interactive),
                in: RoundedRectangle(cornerRadius: radius, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [
                                .white.opacity(scheme == .dark ? 0.20 : 0.75),
                                .white.opacity(scheme == .dark ? 0.02 : 0.18)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: hairline
                    )
                    .allowsHitTesting(false)
            }
    }
}

// MARK: - Components

struct GlassIconButton: View {
    let symbol: String
    var diameter: CGFloat = 44
    var tint: Color?
    var foreground: Color? = nil   // 默认跟随主题 text
    let action: () -> Void

    @Environment(\.theme) private var theme

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .themeFont(.appBody, size: diameter * 0.36, weight: .semibold)
                .foregroundStyle(foreground ?? theme.text)
                .glassCircle(diameter: diameter, tint: tint)
                .contentShape(Circle())
        }
        .buttonStyle(PressableStyle())
        .accessibilityLabel(symbol)
    }
}

/// 轻微按下缩放，替代默认高亮。
/// P1-03（D37）：按压参数读 ShapeSpec，默认 scale 0.94 / opacity 0.92 / spring 0.28·0.7
/// 与旧值一致（零回归）；scale 是控件级反馈，不违反背景无动画红线。
/// 注意：scaleEffect 不改变 hitTest 热区，44pt 触控核验看 frame（P4-04）。
struct PressableStyle: ButtonStyle {
    @Environment(\.theme) private var theme

    func makeBody(configuration: Configuration) -> some View {
        let shape = theme.shape
        return configuration.label
            .scaleEffect(configuration.isPressed ? shape.pressScale : 1)
            .opacity(configuration.isPressed ? shape.pressOpacity : 1)
            .animation(
                reduceMotion ? nil : .spring(
                    response: shape.pressSpringResponse,
                    dampingFraction: shape.pressSpringDamping
                ),
                value: configuration.isPressed
            )
    }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
}

struct SectionHeading: View {
    let text: String
    var trailing: String?

    @Environment(\.theme) private var theme

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(text)
                .themeFont(.appBody, size: 12, weight: .semibold))
                .tracking(1.6)
                .foregroundStyle(theme.secondary)

            Spacer(minLength: 8)

            if let trailing {
                Text(trailing)
                    .themeFont(.appBody, size: 11, weight: .medium))
                    .foregroundStyle(theme.tertiary)
            }
        }
    }
}

struct ProgressBar: View {
    let value: Double
    var tint: Color? = nil        // 默认跟随主题 accent（P1-03 默认参数陷阱）
    var track: Color? = nil       // 默认跟随主题 faint
    var height: CGFloat = 3

    @Environment(\.theme) private var theme

    var body: some View {
        let barTint = tint ?? theme.accent
        let barTrack = track ?? theme.faint
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(barTrack)
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [barTint, barTint.opacity(0.7)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: max(3, geometry.size.width * min(max(value, 0), 1)))
            }
        }
        .frame(height: height)
    }
}

/// 环形进度，用于目标与封面角标
struct RingProgress: View {
    let value: Double
    var lineWidth: CGFloat = 8
    var tint: Color? = nil        // 默认跟随主题 accent
    var track: Color? = nil       // 默认跟随主题 faint
    var label: String?
    var caption: String?

    @Environment(\.theme) private var theme

    var body: some View {
        let ringTint = tint ?? theme.accent
        let ringTrack = track ?? theme.faint
        ZStack {
            Circle().stroke(ringTrack, lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: min(max(value, 0), 1))
                .stroke(
                    AngularGradient(
                        colors: [ringTint.opacity(0.55), ringTint, ringTint.opacity(0.85)],
                        center: .center
                    ),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))

            VStack(spacing: 1) {
                if let label {
                    Text(label)
                        // 保留理由：环数字用圆体是品牌既有设计，不属于主题可换字族范围。
                        .font(.system(size: 17, weight: .semibold, design: .rounded))
                        .foregroundStyle(theme.text)
                }
                if let caption {
                    Text(caption)
                        .themeFont(.appBody, size: 9, weight: .medium))
                        .foregroundStyle(theme.tertiary)
                }
            }
        }
    }
}

/// 封面
struct BookCover: View {
    let book: Book
    var cornerRadius: CGFloat = 12
    /// 大尺寸展示（继续阅读卡、详情页、播放页）时使用更大的书名比例
    var prominent = false

    @Environment(\.theme) private var theme

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            // covers / coversDeep 与旧 Palette.cover(_:) 的 (light, dark) 双 hex 逐色一致（零回归）。
            let idx = abs(book.coverStyle) % theme.covers.count
            let colors: (Color, Color) = (theme.covers[idx], theme.coversDeep[idx])
            let titleSize = prominent
                ? min(26, max(8, width * 0.155))
                : min(14, max(7, width * 0.105))
            let authorSize = prominent
                ? min(13, max(6, width * 0.082))
                : min(9, max(5, width * 0.072))

            ZStack(alignment: .topLeading) {
                LinearGradient(
                    colors: [colors.0, colors.1],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )

                // 水面反光
                LinearGradient(
                    colors: [.white.opacity(0.16), .clear, .white.opacity(0.04)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )

                // 书脊
                HStack(spacing: 0) {
                    Rectangle()
                        .fill(.black.opacity(0.18))
                        .frame(width: max(1, width * 0.014))
                    Rectangle()
                        .fill(.white.opacity(0.10))
                        .frame(width: max(0.5, width * 0.006))
                    Spacer(minLength: 0)
                }
                .padding(.leading, width * 0.075)

                VStack(alignment: .leading, spacing: width * 0.05) {
                    Text(book.title)
                        .themeFont(.appTitle, size: titleSize, weight: .semibold)
                        .foregroundStyle(.white.opacity(0.96))
                        .lineLimit(3)
                        .minimumScaleFactor(0.7)
                        .shadow(color: .black.opacity(0.3), radius: 1, y: 1)

                    Spacer(minLength: 0)

                    Rectangle()
                        .fill(.white.opacity(0.4))
                        .frame(width: max(6, width * 0.18), height: 1)

                    Text(book.author)
                        .themeFont(.appCaption, size: authorSize, weight: .medium)
                        .foregroundStyle(.white.opacity(0.62))
                        .lineLimit(1)
                }
                .padding(.horizontal, width * 0.13)
                .padding(.vertical, width * 0.11)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)

                if book.kind != .novel {
                    Image(systemName: book.kind.symbol)
                        .themeFont(.appCaption, size: max(5, width * 0.08), weight: .semibold)
                        .foregroundStyle(.white.opacity(0.9))
                        .padding(max(2.5, width * 0.04))
                        .background(.black.opacity(0.22), in: Circle())
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                        .padding(width * 0.075)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [.white.opacity(0.34), .white.opacity(0.05)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 0.8
                    )
            }
            .shadow(color: .black.opacity(0.28), radius: 10, y: 6)
        }
        .aspectRatio(0.71, contentMode: .fit)
    }
}

/// 玻璃提示条
struct ToastView: View {
    let text: String
    @Environment(\.theme) private var theme

    var body: some View {
        Text(text)
            .themeFont(.appBody, size: 13, weight: .medium))
            .foregroundStyle(theme.text)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .glassCapsule(tint: theme.accent.opacity(0.12))
    }
}

struct ToastModifier: ViewModifier {
    let text: String

    func body(content: Content) -> some View {
        content.overlay(alignment: .bottom) {
            if !text.isEmpty {
                ToastView(text: text)
                    .padding(.bottom, 26)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.36, dampingFraction: 0.82), value: text)
    }
}

struct SettingsRow: View {
    let title: String
    var value: String?
    var systemImage: String?
    var iconTint: Color? = nil   // 默认跟随主题 accent
    var showsChevron = true
    var isLast = false

    @Environment(\.theme) private var theme

    var body: some View {
        let rowTint = iconTint ?? theme.accent
        VStack(spacing: 0) {
            HStack(spacing: 13) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .themeFont(.appBody, size: 14, weight: .semibold))
                        .foregroundStyle(rowTint)
                        .frame(width: 30, height: 30)
                        .background(rowTint.opacity(0.12), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                }

                Text(title)
                    .themeFont(.appBody, size: 15)
                    .foregroundStyle(theme.text)

                Spacer(minLength: 8)

                if let value {
                    Text(value)
                        .themeFont(.appBody, size: 13)
                        .foregroundStyle(theme.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .multilineTextAlignment(.trailing)
                }

                if showsChevron {
                    Image(systemName: "chevron.right")
                        .themeFont(.appBody, size: 11, weight: .bold))
                        .foregroundStyle(theme.tertiary.opacity(0.5))
                }
            }
            .padding(.horizontal, 15)
            .padding(.vertical, 12)
            .contentShape(Rectangle())

            if !isLast {
                Rectangle()
                    .fill(theme.hairline)
                    .frame(height: 0.6)
                    .padding(.leading, systemImage == nil ? 15 : 58)
            }
        }
    }
}

/// 分段玻璃胶囊（自绘，避免系统分段控件在玻璃上层次混乱）
struct GlassSegmented<T: Hashable>: View {
    let items: [T]
    let title: (T) -> String
    @Binding var selection: T
    @Namespace private var namespace
    @Environment(\.theme) private var theme

    var body: some View {
        HStack(spacing: 4) {
            ForEach(items, id: \.self) { item in
                let isSelected = selection == item
                Button {
                    withAnimation(.spring(response: 0.34, dampingFraction: 0.86)) {
                        selection = item
                    }
                } label: {
                    Text(title(item))
                        .themeFont(.appBody, size: 13, weight: isSelected ? .semibold : .medium)
                        .foregroundStyle(isSelected ? theme.text : theme.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background {
                            if isSelected {
                                RoundedRectangle(cornerRadius: 11, style: .continuous)
                                    .fill(theme.glassTint)
                                    .overlay {
                                        RoundedRectangle(cornerRadius: 11, style: .continuous)
                                            .strokeBorder(theme.hairline, lineWidth: 0.6)
                                    }
                                    .matchedGeometryEffect(id: "segment", in: namespace)
                            }
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .glassSurface(cornerRadius: 15)
    }
}
