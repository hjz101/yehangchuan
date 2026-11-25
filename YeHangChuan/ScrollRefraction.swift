import SwiftUI

// MARK: - 滚动动力学

/// 滚动瞬间的动力学快照：位移、速度、可视区尺寸。
/// 玻璃表面与折射层都从这里取「世界正在移动」的信号。
struct ScrollPulse: Equatable {
    /// 内容层相对视口顶部的滚动位移
    var offset: CGFloat = 0
    /// 每次几何变化的位移增量（pt/帧），用来近似滚动速度
    var velocity: CGFloat = 0
    /// 可视区尺寸
    var viewport: CGSize = .zero

    static let zero = ScrollPulse()

    /// 调试用：固定一段「正在快速滚动」的状态，方便截图检查折射层
    static var initial: ScrollPulse {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-showRefraction") {
            return ScrollPulse(
                offset: 160,
                velocity: 22,
                viewport: CGSize(width: 390, height: 844)
            )
        }
        #endif
        return .zero
    }

    var isMoving: Bool { abs(velocity) > 0.6 }

    /// 0…1 的归一化强度
    var intensity: CGFloat {
        min(1, abs(velocity) / 26)
    }

    /// 折射位移强度（pt）：只有几磅的位移，够看出水波但不影响阅读
    var refractionStrength: CGFloat {
        2 + intensity * 5
    }
}

private struct ScrollPulseKey: EnvironmentKey {
    static let defaultValue = ScrollPulse()
}

extension EnvironmentValues {
    var scrollPulse: ScrollPulse {
        get { self[ScrollPulseKey.self] }
        set { self[ScrollPulseKey.self] = newValue }
    }
}

// MARK: - 采集

private struct ScrollPulseTracker: ViewModifier {
    @Binding var pulse: ScrollPulse

    @State private var lastOffset: CGFloat?
    @State private var decay: Task<Void, Never>?

    private struct Metrics: Equatable {
        var offset: CGFloat
        var viewport: CGSize
    }

    func body(content: Content) -> some View {
        content
            .onScrollGeometryChange(for: Metrics.self) { geometry in
                Metrics(offset: geometry.contentOffset.y, viewport: geometry.containerSize)
            } action: { _, new in
                let previous = lastOffset ?? new.offset
                let delta = new.offset - previous
                lastOffset = new.offset

                // 静止时不刷新，避免每帧重绘
                guard abs(delta) > 0.25 || pulse.viewport != new.viewport else { return }
                push(offset: new.offset, delta: delta, viewport: new.viewport)
            }
            .onDisappear { decay?.cancel() }
    }

    private func push(offset: CGFloat, delta: CGFloat, viewport: CGSize) {
        #if DEBUG
        // 截图验收时冻结演示状态，避免几何回调把它清成静止
        if ProcessInfo.processInfo.arguments.contains("-showRefraction") { return }
        #endif

        pulse = ScrollPulse(offset: offset, velocity: delta, viewport: viewport)

        decay?.cancel()
        decay = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(90))
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.55)) {
                pulse.velocity = 0
            }
        }
    }
}

// MARK: - 折射

private struct RefractionModifier: ViewModifier {
    let pulse: ScrollPulse

    func body(content: Content) -> some View {
        let height = max(pulse.viewport.height, 1)
        let strength = pulse.refractionStrength

        content.distortionEffect(
            ShaderLibrary.glassRefraction(
                .float(pulse.offset),
                .float(height),
                .float(strength)
            ),
            maxSampleOffset: CGSize(width: 9, height: 2),
            isEnabled: pulse.intensity > 0.02
        )
    }
}

// MARK: - 玻璃高光扫描

/// 贴在玻璃表面上的一层高光：滚动越快越亮，并沿着位移方向扫过表面。
struct GlassSheen: View {
    var cornerRadius: CGFloat = 26

    @Environment(\.scrollPulse) private var pulse
    @Environment(\.colorScheme) private var scheme

    private var intensity: CGFloat {
        min(1, abs(pulse.velocity) / 18) * (scheme == .dark ? 0.5 : 0.62)
    }

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let height = geo.size.height
            let travel = (pulse.offset / 320).truncatingRemainder(dividingBy: 1)
            let x = -width * 0.75 + width * 2.1 * travel

            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0),
                    .init(color: .white.opacity(0.55), location: 0.46),
                    .init(color: .white.opacity(0.16), location: 0.6),
                    .init(color: .clear, location: 1)
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
            .frame(width: width * 0.62, height: height * 1.9)
            .rotationEffect(.degrees(-13))
            .offset(x: x, y: -height * 0.45)
            .blur(radius: 9)
            .opacity(intensity)
        }
        .mask(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(.white)
        )
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

// MARK: - 修饰器入口

extension View {
    /// 采集滚动几何，写入 `pulse`
    func trackScrollPulse(_ pulse: Binding<ScrollPulse>) -> some View {
        modifier(ScrollPulseTracker(pulse: pulse))
    }

    /// 内容在玻璃上下边缘的折射扰动
    func refraction(_ pulse: ScrollPulse) -> some View {
        modifier(RefractionModifier(pulse: pulse))
    }

    /// 玻璃表面随滚动移动的高光层
    func glassSheen(cornerRadius: CGFloat = 26) -> some View {
        overlay {
            GlassSheen(cornerRadius: cornerRadius)
        }
    }
}
