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

enum Palette {
    // 灯焰
    static let accent = Color.adaptive(light: 0xB6402A, dark: 0xFF8E63)
    static let accentSolid = Color.adaptive(light: 0xC2472B, dark: 0xF5774D)
    static let onAccent = Color.adaptive(light: 0xFFF7F2, dark: 0x2B0C04)

    // 水色
    static let jade = Color.adaptive(light: 0x1D6A66, dark: 0x7ED9C9)
    // 旧金
    static let gold = Color.adaptive(light: 0x8A6A1F, dark: 0xE9C179)

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

/// 夜色水面：网格渐变 + 缓慢漂移的光斑，为液态玻璃提供可折射的内容
struct AppBackdrop: View {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var drift = false

    var body: some View {
        // 用 Color.clear 作为尺寸基准，避免固定尺寸的光斑把父级 ZStack 撑大
        Color.clear
            .overlay {
                ZStack {
                    mesh
                    glows
                }
            }
            .clipped()
            .allowsHitTesting(false)
            .ignoresSafeArea()
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.easeInOut(duration: 18).repeatForever(autoreverses: true)) {
                    drift = true
                }
            }
    }

    private var mesh: some View {
        Group {
            if scheme == .dark {
                MeshGradient(
                    width: 3,
                    height: 3,
                    points: [
                        [0, 0], [0.5, 0], [1, 0],
                        [0, 0.52], [0.52, 0.46], [1, 0.55],
                        [0, 1], [0.48, 1], [1, 1]
                    ],
                    colors: [
                        Color(hex: 0x05080E), Color(hex: 0x081019), Color(hex: 0x0C1622),
                        Color(hex: 0x0A121C), Color(hex: 0x13202D), Color(hex: 0x1A232D),
                        Color(hex: 0x0E161E), Color(hex: 0x191D24), Color(hex: 0x2A1E15)
                    ]
                )
            } else {
                MeshGradient(
                    width: 3,
                    height: 3,
                    points: [
                        [0, 0], [0.5, 0], [1, 0],
                        [0, 0.52], [0.52, 0.46], [1, 0.55],
                        [0, 1], [0.48, 1], [1, 1]
                    ],
                    colors: [
                        Color(hex: 0xF7F9FD), Color(hex: 0xEFF3FA), Color(hex: 0xE6EDF7),
                        Color(hex: 0xF3F6FB), Color(hex: 0xE9F0F8), Color(hex: 0xDEE7F2),
                        Color(hex: 0xEDF0F5), Color(hex: 0xE5EBF3), Color(hex: 0xF3E7DA)
                    ]
                )
            }
        }
    }

    private var glows: some View {
        let isDark = scheme == .dark
        return ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [Palette.accentSolid.opacity(isDark ? 0.34 : 0.20), .clear],
                        center: .center,
                        startRadius: 0,
                        endRadius: 200
                    )
                )
                .frame(width: 460, height: 460)
                .blur(radius: 70)
                .offset(x: drift ? -120 : -70, y: drift ? 300 : 350)

            Circle()
                .fill(
                    RadialGradient(
                        colors: [Color(hex: 0x3F8FA8).opacity(isDark ? 0.30 : 0.16), .clear],
                        center: .center,
                        startRadius: 0,
                        endRadius: 190
                    )
                )
                .frame(width: 420, height: 420)
                .blur(radius: 80)
                .offset(x: drift ? 150 : 110, y: drift ? -270 : -320)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }
}

/// 全局暖色滤光与亮度层。只做视觉压低，不拦截触摸。
struct EyeCareLayer: View {
    let settings: EyeCareSettings

    var body: some View {
        if settings.enabled {
            ZStack {
                Color(hex: 0xFF9E4A)
                    .opacity(settings.warmth * 0.13)
                Color.black
                    .opacity(settings.dim)
            }
            .ignoresSafeArea()
            .allowsHitTesting(false)
        }
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

    func body(content: Content) -> some View {
        content
            .glassEffect(
                Glass.regular.tint(tint).interactive(interactive),
                in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [
                                .white.opacity(scheme == .dark ? 0.20 : 0.75),
                                .white.opacity(scheme == .dark ? 0.02 : 0.18)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 0.7
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
    var foreground: Color = Palette.text
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: diameter * 0.36, weight: .semibold))
                .foregroundStyle(foreground)
                .glassCircle(diameter: diameter, tint: tint)
                .contentShape(Circle())
        }
        .buttonStyle(PressableStyle())
        .accessibilityLabel(symbol)
    }
}

/// 轻微按下缩放，替代默认高亮
struct PressableStyle: ButtonStyle {
    var scale: CGFloat = 0.94

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1)
            .opacity(configuration.isPressed ? 0.92 : 1)
            .animation(.spring(response: 0.28, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

struct SectionHeading: View {
    let text: String
    var trailing: String?

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(text)
                .font(.system(size: 12, weight: .semibold))
                .tracking(1.6)
                .foregroundStyle(Palette.secondary)

            Spacer(minLength: 8)

            if let trailing {
                Text(trailing)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Palette.tertiary)
            }
        }
    }
}

struct ProgressBar: View {
    let value: Double
    var tint: Color = Palette.accent
    var track: Color = Palette.faint
    var height: CGFloat = 3

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(track)
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [tint, tint.opacity(0.7)],
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
    var tint: Color = Palette.accent
    var track: Color = Palette.faint
    var label: String?
    var caption: String?

    var body: some View {
        ZStack {
            Circle().stroke(track, lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: min(max(value, 0), 1))
                .stroke(
                    AngularGradient(
                        colors: [tint.opacity(0.55), tint, tint.opacity(0.85)],
                        center: .center
                    ),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))

            VStack(spacing: 1) {
                if let label {
                    Text(label)
                        .font(.system(size: 17, weight: .semibold, design: .rounded))
                        .foregroundStyle(Palette.text)
                }
                if let caption {
                    Text(caption)
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(Palette.tertiary)
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

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let colors = Palette.cover(book.coverStyle)
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
                        .font(.system(size: titleSize, weight: .semibold, design: .serif))
                        .foregroundStyle(.white.opacity(0.96))
                        .lineLimit(3)
                        .minimumScaleFactor(0.7)
                        .shadow(color: .black.opacity(0.3), radius: 1, y: 1)

                    Spacer(minLength: 0)

                    Rectangle()
                        .fill(.white.opacity(0.4))
                        .frame(width: max(6, width * 0.18), height: 1)

                    Text(book.author)
                        .font(.system(size: authorSize, weight: .medium))
                        .foregroundStyle(.white.opacity(0.62))
                        .lineLimit(1)
                }
                .padding(.horizontal, width * 0.13)
                .padding(.vertical, width * 0.11)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)

                if book.kind != .novel {
                    Image(systemName: book.kind.symbol)
                        .font(.system(size: max(5, width * 0.08), weight: .semibold))
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

    var body: some View {
        Text(text)
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(Palette.text)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .glassCapsule(tint: Palette.accent.opacity(0.12))
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
    var iconTint: Color = Palette.accent
    var showsChevron = true
    var isLast = false

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 13) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(iconTint)
                        .frame(width: 30, height: 30)
                        .background(iconTint.opacity(0.12), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                }

                Text(title)
                    .font(.system(size: 15))
                    .foregroundStyle(Palette.text)

                Spacer(minLength: 8)

                if let value {
                    Text(value)
                        .font(.system(size: 13))
                        .foregroundStyle(Palette.secondary)
                        .multilineTextAlignment(.trailing)
                }

                if showsChevron {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Palette.tertiary.opacity(0.5))
                }
            }
            .padding(.horizontal, 15)
            .padding(.vertical, 12)
            .contentShape(Rectangle())

            if !isLast {
                Rectangle()
                    .fill(Palette.hairline)
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
                        .font(.system(size: 13, weight: isSelected ? .semibold : .medium))
                        .foregroundStyle(isSelected ? Palette.text : Palette.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background {
                            if isSelected {
                                RoundedRectangle(cornerRadius: 11, style: .continuous)
                                    .fill(Palette.glassTint)
                                    .overlay {
                                        RoundedRectangle(cornerRadius: 11, style: .continuous)
                                            .strokeBorder(Palette.hairline, lineWidth: 0.6)
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
