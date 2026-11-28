import SwiftUI

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

    /// 草稿：编辑期的隔离状态，应用前不影响全局。
    @State private var draft: Theme
    /// 原始主题（用于取消/对比）。
    private let original: Theme
    let onApply: (Theme) -> Void

    @State private var showApplyConfirm = false
    @State private var pendingDelete: Theme?
    @State private var showRestoreToast = false
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

    init(theme: Theme, onApply: @escaping (Theme) -> Void) {
        self.original = theme
        self._draft = State(initialValue: theme)
        self.onApply = onApply
    }

    var body: some View {
        NavigationStack {
            HStack(spacing: 0) {
                // 左侧分组导航
                List(EditorGroup.allCases) { group in
                    Button {
                        selectedGroup = group
                    } label: {
                        Label(group.rawValue, systemImage: icon(for: group))
                            .foregroundStyle(selectedGroup == group ? theme.accent : theme.text)
                    }
                    .buttonStyle(.plain)
                }
                .listStyle(.sidebar)
                .frame(width: 180)

                // 右侧：编辑区 + 实时预览
                VStack(spacing: 0) {
                    editorPane
                    Divider()
                    previewPane
                }
            }
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
                    Text("已删除主题，5 秒内可撤销")
                        .font(.caption)
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
                onDelete: { pendingDelete = $0 },
                onRestore: { showRestoreToast = true }
            )
        }
    }

    /// 实时预览：注入 draft 解析出的 tokens（390×844 预览几何）。
    private var previewPane: some View {
        // 预览内容统一用 draft 解析的令牌（背景+前景都跟随草稿）。
        let previewTokens = ThemeEngine.resolve(theme: draft)
        return VStack(alignment: .leading, spacing: 8) {
            Text("实时预览").font(.caption).foregroundStyle(previewTokens.secondary)
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
                        .overlay(Text("继续阅读").foregroundStyle(previewTokens.onAccent))
                    Spacer()
                }
                .padding(20)
                .foregroundStyle(previewTokens.text)
            }
            .frame(width: 390, height: 300)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay {
                RoundedRectangle(cornerRadius: 16)
                    .stroke(previewTokens.hairline, lineWidth: 1)
            }
        }
        .padding(16)
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
