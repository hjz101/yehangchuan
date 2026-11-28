import SwiftUI
import YeHangCore

// MARK: - 主题编辑器主体框架与 draft 协议（P3-03）
//
// 编辑器是双层环境：外层 chrome 用真实 theme（.themedChrome），
// 内层实时预览容器注入 draft 解析出的 tokens（技术评审 B5）。
// draft 隔离：拖动只刷预览，点「应用」才写 AppStore/ThemeStore 并 bump revision。
// 主题库 CRUD：重命名/复制/删除/设为当前；删除留 .bak + 5 秒撤销。

struct ThemeEditor: View {
    @Environment(AppStore.self) private var store
    @Environment(\.theme) private var theme
    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.colorScheme) private var colorScheme

    /// 草稿：编辑期的隔离状态，应用前不影响全局。
    @State private var draft: Theme
    /// 原始主题（用于取消/对比）。
    private let original: Theme
    let onApply: (Theme) -> Void
    /// 5 秒撤销窗口到期后真正从 catalog 移除并落盘（由 SettingsView 注入）。
    let onDeleteTheme: (Theme) -> Void

    @State private var showApplyConfirm = false
    @State private var pendingDelete: Theme?
    @State private var showRestoreToast = false
    /// 删除定时器：撤销/重复删除时取消旧任务，UUID 双重防误删。
    /// 状态机放在 YeHangCore，五个关键时序有独立单元测试覆盖。
    @State private var deleteUndo = DelayedUndoController()
    @State private var selectedGroup: EditorGroup = .colors

    enum EditorGroup: String, CaseIterable, Identifiable {
        case colors = "色彩"
        case fonts = "字体"
        case backdrop = "背景"
        case glass = "玻璃与组件"
        case reading = "阅读排版"
        case loading = "加载与状态"
        case library = "我的主题"

        var id: String { rawValue }
    }

    init(
        theme: Theme,
        onApply: @escaping (Theme) -> Void,
        onDeleteTheme: @escaping (Theme) -> Void
    ) {
        self.original = theme
        self._draft = State(initialValue: theme)
        self.onApply = onApply
        self.onDeleteTheme = onDeleteTheme
    }

    var body: some View {
        NavigationStack {
            editorLayout
            .navigationTitle("主题编辑")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("应用") { showApplyConfirm = true }
                        .disabled(draft == original)
                }
            }
            .alert("应用主题", isPresented: $showApplyConfirm) {
                Button("应用", role: .none) {
                    onApply(draft)
                    dismiss()
                }
                Button("取消", role: .cancel) {}
            } message: {
                Text("应用后全 App 立即换肤。可随时在主题库切回其他主题。")
            }
            .overlay(alignment: .bottom) {
                if showRestoreToast {
                    HStack(spacing: 12) {
                        Text("已删除主题，5 秒内可撤销")
                            .font(.caption)
                        Button("撤销") { undoDelete() }
                            .font(.caption)
                            .buttonStyle(.borderedProminent)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(.regularMaterial, in: Capsule())
                    .padding(.bottom, 16)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
        }
        // 编辑器本身在 sheet 内：外层接真实 theme + 护眼层。
        .themedChrome(store)
    }

    /// 宽屏（iPad / 横屏）沿用左右分栏；窄屏（iPhone 竖屏）改纵向布局，
    /// 分组用横向滚动条，避免 180pt 侧栏挤压编辑区与预览（截图裁切根因）。
    @ViewBuilder
    private var editorLayout: some View {
        if sizeClass == .compact {
            VStack(spacing: 0) {
                groupStrip
                editorPane
                Divider()
                previewPane
            }
        } else {
            HStack(spacing: 0) {
                groupList
                    .frame(width: 180)
                VStack(spacing: 0) {
                    editorPane
                    Divider()
                    previewPane
                }
            }
        }
    }

    private var groupList: some View {
        List(EditorGroup.allCases) { group in
            groupButton(group)
        }
        .listStyle(.sidebar)
    }

    private var groupStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(EditorGroup.allCases) { group in
                    groupButton(group)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(
                            Capsule().fill(
                                selectedGroup == group
                                    ? theme.accent.opacity(0.16)
                                    : Color.clear
                            )
                        )
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
        }
        .frame(height: 54)
    }

    private func groupButton(_ group: EditorGroup) -> some View {
        Button {
            selectedGroup = group
        } label: {
            Label(group.rawValue, systemImage: icon(for: group))
                .font(.caption)
                .foregroundStyle(selectedGroup == group ? theme.accent : theme.text)
                .lineLimit(1)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var editorPane: some View {
        switch selectedGroup {
        case .colors:
            ColorEditorView(theme: $draft)
        case .fonts:
            FontGroupView(theme: $draft)
        case .backdrop:
            BackdropEditorView(theme: $draft)
        case .glass:
            ComponentStyleView(theme: $draft)
        case .reading:
            ReaderTypographyView(theme: $draft)
        case .loading:
            LoadingEditorView(theme: $draft)
        case .library:
            ThemeLibraryView(
                draft: $draft,
                original: original,
                onPreset: { preset in
                    // onApply 已负责 catalog 更新 + selectTheme，无需再改 SettingsView 的应用回调。
                    onApply(preset)
                    dismiss()
                },
                onDelete: { scheduleDelete($0) },
                onRestore: { showRestoreToast = true }
            )
        }
    }

    /// 实时预览：注入 draft 解析出的 tokens。宽度随容器自适应（上限 390），
    /// 前景按 draft 背景亮度二选一，避免深底深色字（与阅读页 D1 修复同策略）。
    private var previewPane: some View {
        let previewTokens = ThemeEngine.resolve(theme: draft)
        let foreground = Self.previewForeground(draft.backdrop, scheme: colorScheme)
        return VStack(alignment: .leading, spacing: 8) {
            Text("实时预览").font(.caption).foregroundStyle(theme.secondary)
            ZStack {
                ThemeBackdrop()
                    .environment(\.theme, previewTokens)
                VStack(spacing: 10) {
                    HStack {
                        Image(systemName: "books.vertical.fill")
                        Text("夜航船").font(.headline)
                        Spacer()
                    }
                    RoundedRectangle(cornerRadius: 12)
                        .fill(previewTokens.accent.opacity(0.6))
                        .frame(height: 64)
                        .overlay(Text("继续阅读").foregroundStyle(foreground))
                    Spacer()
                }
                .padding(20)
                .foregroundStyle(foreground)
            }
            .frame(maxWidth: 390)
            .aspectRatio(390 / 300, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay {
                RoundedRectangle(cornerRadius: 16)
                    .stroke(foreground.opacity(0.3), lineWidth: 1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
    }

    /// 从草稿背景取代表色，用亮度对比选黑/白前景；只读配置、不改 draft。
    private static func previewForeground(
        _ backdrop: BackgroundSpec,
        scheme: ColorScheme
    ) -> Color {
        let bg: UInt32
        switch backdrop {
        case .systemMesh:
            bg = scheme == .dark ? 0x07080B : 0x1C2029
        case let .solid(spec):
            bg = specHex(spec, scheme: scheme)
        case let .linear(colors, _, _):
            bg = colors.first.map { specHex($0, scheme: scheme) } ?? 0x111111
        case let .radial(colors, _, _, _):
            bg = colors.first.map { specHex($0, scheme: scheme) } ?? 0x111111
        case let .mesh(_, colors):
            bg = colors.first.map { specHex($0, scheme: scheme) } ?? 0x111111
        case let .image(_, _, overlay):
            bg = overlay.map { specHex($0, scheme: scheme) } ?? 0x111111
        }
        return Color(hex: ThemeEngine.suggestedTextColor(background: bg))
    }

    private static func specHex(_ spec: ColorSpec, scheme: ColorScheme) -> UInt32 {
        switch spec {
        case .system:
            return scheme == .dark ? 0xF4F0E8 : 0x111A24
        case let .adaptive(light, dark, _, _):
            return scheme == .dark ? dark : light
        case let .fixed(hex, _):
            return hex
        }
    }

    /// 删除进入 5 秒待确认期：先只记 pendingDelete，到期才真正移除。
    private func scheduleDelete(_ theme: Theme) {
        guard !theme.builtin else { return }
        pendingDelete = theme
        showRestoreToast = true
        deleteUndo.schedule {
            guard let target = pendingDelete, target.id == theme.id else { return }
            onDeleteTheme(target)
            pendingDelete = nil
            showRestoreToast = false
        }
    }

    /// 撤销：取消定时、清掉待删目标；状态机会换 token，旧任务醒来也被挡住。
    private func undoDelete() {
        deleteUndo.cancel()
        pendingDelete = nil
        showRestoreToast = false
    }

    private func icon(for group: EditorGroup) -> String {
        switch group {
        case .colors: return "paintpalette"
        case .fonts: return "textformat"
        case .backdrop: return "square.grid.3x3"
        case .glass: return "rectangle.on.rectangle"
        case .reading: return "book.open"
        case .loading: return "hourglass"
        case .library: return "square.stack"
        }
    }
}

// MARK: - draft 绑定协议（P3-04/05/06 子视图共享）

/// 所有编辑子视图通过它读改 draft，统一走 ThemeEngine 解析预览，不各自造轮子。
struct ThemeDraft {
    var theme: Theme
    var resolved: ThemeTokens { ThemeEngine.resolve(theme: theme) }
}
