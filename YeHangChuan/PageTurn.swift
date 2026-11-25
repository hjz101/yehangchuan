import SwiftUI
import UIKit

/// 书页堆叠翻页。
///
/// 正文始终以整页尺寸排版，翻页时被一个从右向左展开的窗口逐帧裁切出来，
/// 因此换行位置从第一帧到最后一帧完全不变。
///
/// `matchedGeometryEffect` 用在同一条纸边上：它从书堆的右侧出发，
/// 随着翻页移动到左侧，成为新页的前缘。纸边在两个状态里尺寸一致，
/// 只发生位移，所以不会被缩放拉变形。
struct PageTurnReader: View {
    let pages: [ReaderPage]
    @Binding var index: Int
    let bookTitle: String
    let settings: ReaderSettings
    /// 沉浸模式：左右边缘出现翻页热区
    var showsTapZones: Bool = false

    let onComment: (Paragraph) -> Void
    let onExcerpt: (Paragraph) -> Void
    let onTap: () -> Void
    /// 翻到头了：参数为翻页方向
    let onEdge: (Bool) -> Void

    @Namespace private var pageNS

    private struct Turn: Equatable {
        let target: Int
        let forward: Bool
        var key: String { forward ? "edge-forward" : "edge-backward" }
    }

    @State private var turn: Turn?
    @State private var morphing = false
    @State private var progress: CGFloat = 0
    @State private var pageSize: CGSize = .zero

    private var hasNext: Bool { index < pages.count - 1 }
    private var hasPrevious: Bool { index > 0 }

    var body: some View {
        ZStack {
            if pages.indices.contains(index) {
                page(pages[index])
                    .offset(x: -progress * pageSize.width * 0.15)
                    .scaleEffect(1 - progress * 0.02)
                    .overlay {
                        Rectangle()
                            .fill(.black.opacity(progress * (settings.theme.isDark ? 0.3 : 0.13)))
                            .allowsHitTesting(false)
                    }
            }

            if let turn {
                // 纸边：从书堆右侧移动到新页左侧的共享元素
                if morphing {
                    travelingEdge(turn)
                } else {
                    placedEdge(turn.forward, turn.key)
                }

                // 新页：自带不透明纸底，固定整页排版，只按进度裁切
                ZStack {
                    pageGradient

                    page(pages[turn.target])
                        .frame(
                            width: max(pageSize.width, 1),
                            height: max(pageSize.height, 1),
                            alignment: .topLeading
                        )
                }
                .frame(width: max(pageSize.width, 1), height: max(pageSize.height, 1), alignment: .topLeading)
                .mask(alignment: turn.forward ? .trailing : .leading) {
                    Rectangle()
                        .frame(width: max(pageSize.width * progress, 1))
                }
                .allowsHitTesting(false)
            } else {
                // 两侧纸堆常驻，翻页时才有可 morph 的起点
                placedEdge(true, "edge-forward")
                placedEdge(false, "edge-backward")
            }

            if showsTapZones {
                HStack(spacing: 0) {
                    zone(.backward)
                    zone(.forward)
                }
            }
        }
        .onGeometryChange(for: CGSize.self) { $0.size } action: { newValue in
            guard newValue.width > 1, newValue.height > 1 else { return }
            pageSize = newValue
        }
        .simultaneousGesture(swipe)
        .task {
            #if DEBUG
            guard ProcessInfo.processInfo.arguments.contains("-autoTurn") else { return }
            try? await Task.sleep(for: .milliseconds(900))
            turnPage(forward: true)
            #endif
        }
    }

    // MARK: 纸张

    private func page(_ page: ReaderPage) -> some View {
        ReaderPageView(
            page: page,
            pageIndex: pages.firstIndex(where: { $0.id == page.id }) ?? index,
            total: pages.count,
            bookTitle: bookTitle,
            settings: settings,
            onComment: onComment,
            onExcerpt: onExcerpt,
            onTap: onTap
        )
    }

    /// 纸边抵达新页的另一侧，成为翻页的前缘；尾段淡出，交还给书堆
    private func travelingEdge(_ turn: Turn) -> some View {
        paperEdge(turn.forward)
            .matchedGeometryEffect(id: turn.key, in: pageNS, isSource: false)
            .frame(
                maxWidth: .infinity,
                maxHeight: .infinity,
                alignment: turn.forward ? .leading : .trailing
            )
            .opacity(1 - Double(progress * progress * 0.85))
    }

    /// 把纸边放到屏幕一侧；形变只挂在纸边本身，外层对齐容器不参与。
    private func placedEdge(_ forward: Bool, _ key: String) -> some View {
        paperEdge(forward)
            .matchedGeometryEffect(id: key, in: pageNS, isSource: true)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: forward ? .trailing : .leading)
    }

    /// 书堆里露出来的那一小条纸边
    private func paperEdge(_ forward: Bool) -> some View {
        ZStack(alignment: forward ? .trailing : .leading) {
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(pageGradient)
                .frame(width: 6)
                .overlay {
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .strokeBorder(.white.opacity(0.24), lineWidth: 0.6)
                }

            HStack(spacing: 1.8) {
                ForEach(0..<2, id: \.self) { _ in
                    Rectangle()
                        .fill(pageGradient)
                        .frame(width: 2)
                }
            }
            .padding(forward ? .trailing : .leading, 7)
        }
        .frame(width: 14, height: max(pageSize.height * 0.94, 1))
        .opacity(denote(forward) ? 1 : 0)
        .allowsHitTesting(false)
    }

    private func denote(_ forward: Bool) -> Bool {
        forward ? hasNext : hasPrevious
    }

    private var pageGradient: LinearGradient {
        LinearGradient(
            colors: [settings.theme.background, settings.theme.backgroundDeep],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    // MARK: 交互

    private enum Zone { case backward, forward }

    private func zone(_ zone: Zone) -> some View {
        Color.clear
            .contentShape(Rectangle())
            .onTapGesture {
                switch zone {
                case .backward: turnPage(forward: false)
                case .forward: turnPage(forward: true)
                }
            }
    }

    private var swipe: some Gesture {
        DragGesture(minimumDistance: 22)
            .onEnded { value in
                let dx = value.translation.width
                guard abs(dx) > abs(value.translation.height) * 1.3 else { return }
                if dx < -48 {
                    turnPage(forward: true)
                } else if dx > 48 {
                    turnPage(forward: false)
                }
            }
    }

    // MARK: 翻页时序

    /// 调试用慢放：`-slowTurn` 把整个翻页拉长 5 倍，便于逐帧检查
    private var slowFactor: Double {
        #if DEBUG
        ProcessInfo.processInfo.arguments.contains("-slowTurn") ? 5 : 1
        #else
        1
        #endif
    }

    /// 纸张形变与正文裁切必须同曲线，否则中途会错位
    private var turnSpring: Animation {
        .spring(response: 0.54 * slowFactor, dampingFraction: 0.86)
    }

    private func turnPage(forward: Bool) {
        guard turn == nil else { return }

        let target = index + (forward ? 1 : -1)
        guard pages.indices.contains(target) else {
            onEdge(forward)
            return
        }

        UIImpactFeedbackGenerator(style: .soft).impactOccurred()

        var instant = Transaction()
        instant.disablesAnimations = true
        withTransaction(instant) {
            progress = 0
            turn = Turn(target: target, forward: forward)
        }

        withAnimation(turnSpring) {
            progress = 1
        }

        // 下一帧再切入目标页，确保纸边已完成一次布局，morph 才有起点
        Task { @MainActor in
            await Task.yield()

            withAnimation(turnSpring) {
                morphing = true
            }

            try? await Task.sleep(for: .milliseconds(Int(520 * slowFactor)))

            var settle = Transaction()
            settle.disablesAnimations = true
            withTransaction(settle) {
                index = target
                turn = nil
                morphing = false
                progress = 0
            }
        }
    }
}
