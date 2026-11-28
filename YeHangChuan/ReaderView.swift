import SwiftUI
import AVFoundation
import MediaPlayer
import LegadoCore
import YeHangCore

// P4-05/D1：阅读正文前景色专用环境键。
// 阅读正文由 CoreText 绘制（NSAttributedString），拿不到 SwiftUI 的 @Environment(\.theme)，
// 深层的 ReaderPageView 通过此键拿到解析后的 effective 前景色，避免退回旧 settings.theme。
private struct ReaderTextColorKey: EnvironmentKey {
    static let defaultValue: UIColor = UIColor(hex: 0xD9E2EC)
}
private extension EnvironmentValues {
    var readerTextColor: UIColor {
        get { self[ReaderTextColorKey.self] }
        set { self[ReaderTextColorKey.self] = newValue }
    }
}

struct ReaderView: View {
    /// 门禁计数：验证「纯换色 rebuild=0、换字体族 rebuild=1」。
    static var rebuildCount = 0
    static func resetRebuildCount() { rebuildCount = 0 }

    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    /// P2-03：全局主题令牌（纯读；颜色变化不会触发 rebuild）。
    @Environment(\.theme) private var themeTokens

    let book: Book
    var initialChapterTitle: String? = nil
    /// 从大纲或书封直接进「版心微调」。工具栏是浮层，得先亮出来，
    /// 否则读者落在一个没有工具栏、却也没法拖的画面里。
    var startInFrameAdjust = false

    /// 排好版的整本书。页表来自 `ChapterPagination`（真实 CoreText 排出来），
    /// 不是按字数估算的 —— 估算的容量与实际排版永远有出入，差的那几个字就画不出来。
    @State private var pagination: PaginatedBook?
    @State private var pageIndex = 0
    /// 每发一次重排就加一。后台算完回来时若已经不是最新一次，就丢掉结果：
    /// 拖字号滑块会连发十几次，晚到的旧结果会把新排版盖回去。
    @State private var paginationGeneration = 0
    /// 长按选中的段落。CoreText 画出来的文字拿不到系统的选择菜单，
    /// 所以由命中测试找出是哪一段，再弹自己的操作条。
    @State private var selectedParagraph: Paragraph?
    @State private var showChrome = true
    @State private var showTOC = false
    @State private var showSettings = false
    @State private var showBookmarks = false
    @State private var showListen = false
    @State private var showSourceSwitch = false
    /// 版心微调：四边抓手直接拖正文的边界。
    @State private var showFrameAdjust = false
    @State private var commentParagraph: Paragraph?
    /// 点「导出正文」后生成的临时 TXT，驱动分享面板。
    @State private var exportFile: ExportedTextFile?
    @State private var flash: String?
    /// 在线书正在拉目录或正文。
    @State private var isLoadingNetwork = false
    /// 在线书加载失败的原因，显示在正文区而不是静默空白。
    @State private var networkError: String?
    @State private var viewport: CGSize = CGSize(width: 390, height: 844)
    @State private var safeAreaInsets = EdgeInsets()
    /// 滚动模式下当前可见段落的 ID，与 ScrollReaderView 的 scrollPosition 双向绑定。
    @State private var scrollParagraphID: String?
    /// 滚动模式下据此把段落位置换算成与分页模式一致的百分比。
    @State private var scrollProgress: Double = 0
    /// 上次结算阅读时长的时间点。统计页的数据来自真实停留时间，
    /// 每翻一页（含滚动模式）结算一次，离开阅读页时再结算剩余部分。
    @State private var lastReadingTick = Date()

    private var settings: ReaderSettings { store.settings }
    private var chapters: [Chapter] { store.chapters(for: book) }
    private var currentPage: ReadingPage? { pagination?.page(at: pageIndex) }
    private var pageCount: Int { pagination?.pages.count ?? 0 }

    /// 当前章节标题，分页与滚动两种模式统一口径。
    private var currentChapterTitle: String {
        if isScrollMode { return scrollAnchor.chapterTitle ?? chapters.first?.title ?? book.lastPosition }
        return currentPage?.chapterTitle ?? book.lastPosition
    }

    private var isScrollMode: Bool { settings.pageMode == .scroll }

    private var isBookmarked: Bool {
        store.isBookmarked(
            bookID: book.id,
            pageIndex: pageIndex,
            chapterTitle: currentChapterTitle,
            paragraphID: currentAnchorParagraphID
        )
    }

    /// 当前页首段 ID，作为书签与位置恢复的稳定锚点。
    private var anchorParagraphID: String? { currentPage?.firstParagraphID }

    /// 书签与听书使用的定位锚点，两种阅读模式统一口径。
    private var currentAnchorParagraphID: String? {
        isScrollMode ? scrollAnchor.paragraphID : anchorParagraphID
    }

    /// 当前锚点在所属章节内的 UTF-16 偏移，用于旧数据兼容与导出。
    private var currentAnchorOffset: Int {
        if isScrollMode {
            let anchor = scrollAnchor
            guard let title = anchor.chapterTitle,
                  let id = anchor.paragraphID,
                  let chapter = chapters.first(where: { $0.title == title }),
                  let index = chapter.paragraphs.firstIndex(where: { $0.id == id }) else { return 0 }
            return chapter.paragraphs.prefix(index).reduce(0) { $0 + $1.text.utf16.count }
        }
        // 页在章内的字符位置：排版直接算出来的，不用再逐个段落累加。
        return currentPage?.chapterRange.location ?? 0
    }

    /// 滚动模式下的定位锚点：当前可见段落所在章节与段落本身。
    private var scrollAnchor: (chapterTitle: String?, paragraphID: String?) {
        guard let id = scrollParagraphID else { return (nil, nil) }
        for chapter in chapters {
            if chapter.paragraphs.contains(where: { $0.id == id }) {
                return (chapter.title, id)
            }
        }
        return (chapters.first?.title, id)
    }

    private var progress: Double {
        if isScrollMode { return scrollProgress }
        guard let pagination else { return 0 }
        // 分母是目录章数，不是已排版的页数：在线书按章懒加载，
        // 拿页数当分母会让「读到第一章末尾」显示成已读 100%。
        return ReadingProgress.fraction(
            at: pageIndex,
            of: pagination.pages,
            chapterCount: max(chapters.count, book.chapterCount)
        )
    }

    private var chapterText: String {
        if isScrollMode {
            let title = scrollAnchor.chapterTitle ?? ""
            let paragraphs = chapters.first { $0.title == title }?.paragraphs ?? []
            return paragraphs.map(\.text).joined(separator: "\n")
        }
        let title = currentPage?.chapterTitle ?? ""
        let paragraphs = chapters.first { $0.title == title }?.paragraphs ?? []
        return paragraphs.map(\.text).joined(separator: "\n")
    }

    /// P2-03：阅读页最终样式。优先级由 ReaderStyleResolver 决定；
    /// 纯颜色变化只重算视图，不进 rebuild 的 onChange 列表（避免 CoreText 重排）。
    private var effectiveReaderStyle: ReaderStyleResolution {
        let global = ThemeStore.shared.activeTheme
        return ReaderStyleResolver.resolve(global: global, override: settings.themeOverride)
    }

    private var effectiveSurface: ReadingSurfaceSpec {
        effectiveReaderStyle.surface
    }

    private var readerScheme: ColorScheme {
        effectiveSurface.isDark ? .dark : .light
    }

    private func readerColor(_ color: ThemeColor) -> Color {
        ThemeEngine.color(color, scheme: readerScheme)
    }

    private var chromeColor: Color {
        effectiveSurface.isDark ? .white : themeTokens.text
    }

    private var usesFullscreenFrame: Bool {
        settings.sideMargin <= Double(ReaderMetrics.minSide)
            && settings.topMargin <= Double(ReaderMetrics.minTop)
            && settings.bottomMargin <= Double(ReaderMetrics.minBottom)
    }

    var body: some View {
        ZStack {
            readerBackground

            readingContent
                .ignoresSafeArea()
                // 调版心时正文还在底下，只是被遮罩盖住了。触摸照旧会落到
                // 正文层的翻页热区与长按上：点一下框外就悄悄翻了页，松手
                // 还停在旧页上，看起来像「拖完边界书跳了」。这段时间干脆
                // 不接受正文触摸，翻页和选段都等退出微调之后再说。
                .allowsHitTesting(!showFrameAdjust)

            // 顶部浮层
            VStack {
                if showChrome {
                    topBar
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
                Spacer()
            }

            // 底部浮层
            VStack {
                Spacer()
                if showChrome {
                    bottomBar
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }

            if let flash {
                Text(flash)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(readerColor(effectiveSurface.text))
                    .padding(.horizontal, 15)
                    .padding(.vertical, 9)
                    .glassCapsule(tint: effectiveSurface.isDark ? .white.opacity(0.08) : .white.opacity(0.5))
                    .transition(.scale(scale: 0.9).combined(with: .opacity))
                    // 提示条正压在屏幕正中，能点就得让路：否则它浮着的那 1.5 秒里
                    // 点中间既唤不出工具栏、也翻不了页。
                    .allowsHitTesting(false)
            }

            // 翻页热区不再是一层铺满屏幕的透明遮罩。
            //
            // 以前这里挂了两块各占半屏的 tapZone，铺满整页：中间那一下被当成
            // 翻页吞掉了，读者怎么点也唤不出工具栏；遮罩同时也截走了
            // TabView 的左滑手势。现在分区判定挪进正文自己的触摸层
            // （见 `handlePageTap`），既不挡手势，也能分清左/中/右。

            if settings.volumeKeyTurn {
                VolumeKeyReader(
                    onVolumeUp: {
                        turnPage(forward: false)
                    },
                    onVolumeDown: {
                        turnPage(forward: true)
                    }
                )
                .frame(width: 1, height: 1)
                .opacity(0.01)
                .allowsHitTesting(false)
            }

            if showFrameAdjust {
                ReaderFrameAdjustOverlay(
                    viewport: viewport,
                    theme: settings.theme,
                    initialSideMargin: settings.sideMargin,
                    initialTopMargin: settings.topMargin,
                    initialBottomMargin: settings.bottomMargin,
                    bottomSafeAreaInset: safeAreaInsets.bottom,
                    onCommit: applyFrame,
                    onDone: {
                        withAnimation(.easeInOut(duration: 0.2)) { showFrameAdjust = false }
                    }
                )
                .transition(.opacity)
                .ignoresSafeArea()
            }

            EyeCareLayer(settings: store.eyeCare)
        }
        .onGeometryChange(for: CGSize.self) { $0.size } action: { newSize in
            guard newSize.width > 1, newSize.height > 1 else { return }
            let fullSize = Self.windowBoundsSize
            let measuredSize = fullSize.width > 1 && fullSize.height > 1 ? fullSize : newSize
            guard abs(measuredSize.width - viewport.width) > 1 || abs(measuredSize.height - viewport.height) > 1 else { return }
            viewport = measuredSize
            guard pagination != nil else { return }
            rebuild(restore: false)
        }
        .environment(\.readerTextColor, UIColor(ThemeEngine.color(
            effectiveSurface.text, scheme: effectiveSurface.isDark ? .dark : .light
        )))
        .preferredColorScheme(effectiveSurface.isDark ? .dark : .light)
        .statusBarHidden(!showChrome)
        .persistentSystemOverlays(.hidden)
        .onAppear {
            safeAreaInsets = Self.windowSafeAreaInsets
            viewport = Self.windowBoundsSize
            bootstrap()
        }
        .onDisappear { flushReadingTime() }
        .onChange(of: settings.fontSize) { _, _ in rebuild(restore: false) }
        .onChange(of: settings.lineSpacing) { _, _ in rebuild(restore: false) }
        // 三个刻度合成一个观察点：在纸上拖一次边界只重排一次。
        .onChange(of: [settings.sideMargin, settings.topMargin, settings.bottomMargin]) { _, _ in
            if usesFullscreenFrame {
                showChrome = false
            }
            rebuild(restore: false)
        }
        .onChange(of: showFrameAdjust) { _, isShowing in
            // 微调时收起工具栏，四条边和画出来的版心就是全部信息；
            // 退出时把工具栏亮回来，否则读者会落在「点哪都没反应」的画面里。
            if isShowing {
                // 等阅读设置那张 sheet 真正退场再收工具栏：收早了，抓手会先于
                // 遮罩出现，看起来像面板内容漏到了阅读页上。
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(350))
                    guard showFrameAdjust else { return }
                    withAnimation(.easeInOut(duration: 0.2)) { showChrome = false }
                }
            } else {
                if usesFullscreenFrame {
                    withAnimation(.easeInOut(duration: 0.2)) { showChrome = false }
                } else {
                    revealChrome()
                }
            }
        }
        .onChange(of: settings.purifyText) { _, _ in rebuild(restore: false) }
        .onChange(of: settings.pageMode) { _, _ in rebuild(restore: false) }
        .onChange(of: settings.fontDesign) { _, _ in rebuild(restore: false) }
        .onChange(of: settings.fontWeight) { _, _ in rebuild(restore: false) }
        .onChange(of: settings.indent) { _, _ in rebuild(restore: false) }
        .onChange(of: settings.hideSourceComments) { _, _ in
            // 段评一关，右侧那条挂胶囊的留白就没有存在的理由了（`ReaderMetrics`
            // 按 `hideSourceComments` 决定要不要留 gutter），正文宽度跟着变，
            // 页表必须重排。漏了这一步，界面已经弹出「已显示段评」，
            // 而正文仍是按旧宽度切的 —— 胶囊要么压住字，要么悬在留白里。
            rebuild(restore: false)
        }
        .onChange(of: chapters.count) { _, _ in
            // 在线书拉到目录、补到正文后章数会变：页表要跟着重建，
            // 否则新下来的章节在书里根本不存在。
            rebuild(restore: true)
        }
        .onChange(of: pageIndex) { _, _ in
            syncProgress()
            loadNextChapterIfNeeded()
        }
        .sheet(isPresented: $showTOC) {
            TOCSheet(chapters: chapters, currentTitle: currentChapterTitle) { title in
                hideChromeAfterDelay()
                showTOC = false
                // 在线书跳到新章节时正文还没拉，先跳过去（会显示加载态）再补正文。
                Task { @MainActor in
                    if isScrollMode {
                        if let paragraph = chapters.first(where: { $0.title == title })?.paragraphs.first {
                            scrollParagraphID = paragraph.id
                        }
                    } else if let index = pageIndex(ofChapterTitled: title) {
                        pageIndex = index
                    }
                    await ensureChapterContent(title: title)
                }
            }
            .presentationDetents([.medium, .large])
            .presentationCornerRadius(38)
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showSettings) {
            ReaderSettingsSheet(
                settings: settings,
                onAdjustFrame: {
                    // 设置面板退场、抓手上场。等面板收完再切换，
                    // 否则抓手会先消失一次，看起来像点了没反应。
                    showSettings = false
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showFrameAdjust = true
                    }
                }
            )
                .presentationDetents([.large])
                .presentationCornerRadius(38)
                .presentationDragIndicator(.visible)
        }
        .sheet(item: $commentParagraph) { paragraph in
            SegmentCommentsSheet(
                book: book,
                chapter: chapterContaining(paragraph: paragraph),
                paragraph: paragraph
            )
            .presentationDetents([.fraction(0.62), .large])
            .presentationCornerRadius(38)
            .presentationDragIndicator(.visible)
        }
        .sheet(item: $selectedParagraph) { paragraph in
            ParagraphActionsSheet(
                paragraph: paragraph,
                onExcerpt: {
                    excerpt(paragraph)
                    selectedParagraph = nil
                },
                onComment: {
                    selectedParagraph = nil
                    commentParagraph = paragraph
                },
                onCopy: {
                    UIPasteboard.general.string = paragraph.text
                    selectedParagraph = nil
                    showFlash("已复制这一段")
                }
            )
            .presentationDetents([.height(240)])
            .presentationCornerRadius(32)
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showBookmarks) {
            BookmarkListSheet(book: book) { bookmark in
                jump(to: bookmark)
            }
            .presentationDetents([.medium, .large])
            .presentationCornerRadius(38)
        }
        .sheet(isPresented: $showListen) {
            ListenSheet(
                book: book,
                chapterTitle: currentChapterTitle,
                text: chapterText,
                segments: SpeechSegmenter.segments(
                    from: chapterText,
                    mapping: SpeechRolePreferences.load().mapping
                )
            )
            .presentationDetents([.large])
            .presentationCornerRadius(38)
        }
        .sheet(isPresented: $showSourceSwitch) {
            SourceSwitchSheet(book: book) { source in
                // 换源现在是真去搜同名书 + 验证，要等网络；
                // 验证通过后 ReaderView 需要重排，所以回调里再重建一次。
                let switched = await store.switchSource(bookID: book.id, to: source.id)
                guard switched else { return false }
                rebuild(restore: true)
                await ensureCurrentChapterContent()
                return true
            }
            .presentationDetents([.medium, .large])
            .presentationCornerRadius(38)
        }
        .sheet(item: $exportFile) { file in
            ExportSheet(file: file, bookTitle: book.title)
                .presentationDetents([.fraction(0.42)])
                .presentationCornerRadius(32)
        }
        .task {
            guard store.eyeCare.enabled, store.eyeCare.restReminder else { return }
            try? await Task.sleep(for: .seconds(store.eyeCare.restMinutes * 60))
            guard !Task.isCancelled else { return }
            showFlash("已读 \(store.eyeCare.restMinutes) 分钟，看看 6 米外 20 秒")
        }
    }

    @MainActor
    private static var windowSafeAreaInsets: EdgeInsets {
        let window = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)
        let insets = window?.safeAreaInsets ?? .zero
        return EdgeInsets(
            top: insets.top,
            leading: insets.left,
            bottom: insets.bottom,
            trailing: insets.right
        )
    }

    @MainActor
    private static var windowBoundsSize: CGSize {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)?.bounds.size ?? UIScreen.main.bounds.size
    }

    /// 正文为空时的失败出口：明确说明原因，并给出返回书架的路，
    /// 不再让用户对着一个永远转不完的进度圈。
    private var emptyContentState: some View {
        VStack(spacing: 12) {
            Image(systemName: "doc.text")
                .font(.system(size: 30, weight: .light))
                .foregroundStyle(readerColor(effectiveSurface.secondary))
            Text("这本书没有可显示的正文")
                .font(.system(size: 15, weight: .semibold, design: .serif))
                .foregroundStyle(readerColor(effectiveSurface.text))
            Text("可能是导入时内容解析失败。可以返回书架重新导入这本书。")
                .font(.system(size: 12))
                .foregroundStyle(readerColor(effectiveSurface.secondary))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 36)
            Button {
                dismiss()
            } label: {
                Text("返回书架")
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(themeTokens.onAccent)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 9)
                    .background(themeTokens.accentSolid, in: Capsule())
            }
            .buttonStyle(PressableStyle(scale: 0.97))
        }
    }

    // MARK: Background

    private var readerBackground: some View {
        ZStack {
            LinearGradient(
                colors: [
                    ThemeEngine.color(effectiveSurface.background, scheme: effectiveSurface.isDark ? .dark : .light),
                    ThemeEngine.color(effectiveSurface.backgroundDeep, scheme: effectiveSurface.isDark ? .dark : .light)
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            if settings.theme == .voyage {
                // 放在 overlay 里：固定 440pt 的圆不能进入 ZStack 的理想尺寸，
                // 否则整个阅读器被撑到 440pt 宽，正文左右都会被切掉。
                Color.clear
                    .overlay {
                        Circle()
                            .fill(
                                RadialGradient(
                                    colors: [Color(hex: 0x2B5C7A).opacity(0.35), .clear],
                                    center: .center,
                                    startRadius: 0,
                                    endRadius: 220
                                )
                            )
                            .frame(width: 440, height: 440)
                            .blur(radius: 60)
                            .offset(x: 120, y: -280)
                    }
                    .allowsHitTesting(false)
            }

            if settings.theme == .paper {
                LinearGradient(
                    colors: [Color(hex: 0xFFFFFF).opacity(0.35), .clear],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }
        }
        .ignoresSafeArea()
    }

    // MARK: Content

    /// 这本书有没有一个字能显示。用来区分「还在排版」和「确实没有正文」——
    /// 后者必须给出失败出口，否则用户只会看到一个永远转不完的圈。
    private var hasContent: Bool {
        chapters.contains { chapter in
            chapter.paragraphs.contains { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        }
    }

    @ViewBuilder
    private var readingContent: some View {
        if isLoadingNetwork && pageCount == 0 {
            VStack(spacing: 10) {
                ProgressView().themedProgress()
                Text("正在加载在线章节…")
                    .font(.system(size: 12))
                    .foregroundStyle(readerColor(effectiveSurface.secondary))
            }
        } else if let networkError, pageCount == 0 {
            VStack(spacing: 10) {
                Image(systemName: "wifi.exclamationmark")
                    .font(.system(size: 24, weight: .light))
                    .foregroundStyle(readerColor(effectiveSurface.secondary))
                Text(networkError)
                    .font(.system(size: 12))
                    .foregroundStyle(readerColor(effectiveSurface.secondary))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)

                Button {
                    Task { @MainActor in await ensureCurrentChapterContent() }
                } label: {
                    Text("重试")
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(themeTokens.onAccent)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 9)
                        .background(themeTokens.accentSolid, in: Capsule())
                }
                .buttonStyle(PressableStyle(scale: 0.97))
            }
        } else if !hasContent {
            emptyContentState
        } else if let pagination, !pagination.isEmpty {
            if settings.pageMode == .slide {
                if settings.pageTurnEffect == .slide {
                    TabView(selection: $pageIndex) {
                        ForEach(Array(pagination.pages.enumerated()), id: \.element.id) { index, page in
                            pageView(pagination, page, index: index)
                                .tag(index)
                        }
                    }
                    .tabViewStyle(.page(indexDisplayMode: .never))
                    .environment(\.layoutDirection, settings.direction.layoutDirection)
                } else {
                    PageFlipReader(
                        pagination: pagination,
                        bookTitle: book.title,
                        pageIndex: $pageIndex,
                        settings: settings,
                        onComment: { commentParagraph = $0 },
                        onSelect: { selectedParagraph = $0 },
                        onTap: handlePageTap
                    )
                }
            } else {
                ScrollReaderView(
                    chapters: chapters,
                    settings: settings,
                    visibleParagraphID: $scrollParagraphID,
                    onComment: { commentParagraph = $0 },
                    onExcerpt: { paragraph in excerpt(paragraph) },
                    onTap: toggleChrome
                )
                .environment(\.layoutDirection, settings.direction.layoutDirection)
                .onChange(of: scrollParagraphID) { _, _ in
                    // 可见段落变化即回写进度；scrollTargetLayout 让每段都是可停靠目标。
                    updateScrollProgress()
                    syncProgress()
                }
            }
        } else if isScrollMode {
            // 滚动模式不需要分页，正文一到就能显示。
            ScrollReaderView(
                chapters: chapters,
                settings: settings,
                visibleParagraphID: $scrollParagraphID,
                onComment: { commentParagraph = $0 },
                onExcerpt: { paragraph in excerpt(paragraph) },
                onTap: toggleChrome
            )
            .environment(\.layoutDirection, settings.direction.layoutDirection)
            .onChange(of: scrollParagraphID) { _, _ in
                updateScrollProgress()
                syncProgress()
            }
        } else {
            ProgressView().themedProgress()
        }
    }

    /// 分页模式的点击分区：左右三分之一翻页，中间三分之一收放工具栏。
    ///
    /// 落点是正文层的坐标（左右已各让出 `sideMargin`），按正文宽度三等分即可。
    /// 不另加全屏遮罩：那会截走 TabView 的左滑与覆盖翻页的拖拽，
    /// 而且会把「点中间」这件事彻底吞掉 —— 这正是之前唤不出工具栏的原因。
    private func handlePageTap(_ point: CGPoint, in size: CGSize) {
        // 工具栏开着的时候，点正文任何地方都是收起 ——
        // 与滚动模式、覆盖翻页保持同一种手感。
        guard !showChrome else {
            toggleChrome()
            return
        }
        let third = max(size.width, 1) / 3
        if point.x < third {
            turnPage(forward: settings.direction == .rtl)
        } else if point.x > size.width - third {
            turnPage(forward: settings.direction == .ltr)
        } else {
            toggleChrome()
        }
    }

    /// 分页模式下的一页。绘制层需要 `PaginatedBook` 才能拿到这一页的排版，
    /// 所以不能只传 `ReadingPage`。
    private func pageView(_ pagination: PaginatedBook, _ page: ReadingPage, index: Int) -> some View {
        ReaderPageView(
            pagination: pagination,
            page: page,
            pageIndex: index,
            bookTitle: book.title,
            settings: settings,
            onComment: { commentParagraph = $0 },
            onSelect: { selectedParagraph = $0 },
            onTap: handlePageTap
        )
    }

    // MARK: Chrome

    private var topBar: some View {
        GlassEffectContainer(spacing: 12) {
            HStack(spacing: 10) {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(chromeColor)
                        .glassCircle(diameter: 40)
                }
                .buttonStyle(PressableStyle())

                Spacer(minLength: 0)

                VStack(spacing: 1) {
                    Text(book.title)
                        .font(.system(size: 13, weight: .semibold, design: .serif))
                        .foregroundStyle(chromeColor)
                        .lineLimit(1)

                    Text(currentChapterTitle)
                        .font(.system(size: 10))
                        .foregroundStyle(readerColor(effectiveSurface.secondary))
                        .lineLimit(1)
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 8)
                .glassCapsule()

                Spacer(minLength: 0)

                Button {
                    store.toggleBookmark(
                        book: book,
                        chapterTitle: currentChapterTitle,
                        pageIndex: pageIndex,
                        progress: progress,
                        paragraphID: currentAnchorParagraphID,
                        offset: currentAnchorOffset
                    )
                } label: {
                    Image(systemName: isBookmarked ? "bookmark.fill" : "bookmark")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(isBookmarked ? themeTokens.accent : chromeColor)
                        .glassCircle(diameter: 40)
                }
                .buttonStyle(PressableStyle())

                Menu {
                    Button {
                        showListen = true
                    } label: {
                        Label("听书 · 当前章节", systemImage: "speaker.wave.2")
                    }

                    Button {
                        showBookmarks = true
                    } label: {
                        Label("书签列表", systemImage: "bookmark")
                    }

                    Button {
                        showSourceSwitch = true
                    } label: {
                        Label("换源", systemImage: "arrow.triangle.swap")
                    }

                    Button {
                        Task { @MainActor in
                            await prefetchFollowingChapters()
                        }
                    } label: {
                        Label("缓存后续章节", systemImage: "arrow.down.circle")
                    }

                    Button {
                        exportFile = exportCurrentBook()
                    } label: {
                        Label("导出正文", systemImage: "square.and.arrow.up")
                    }

                    Divider()

                    Button {
                        withAnimation(.easeInOut(duration: 0.25)) {
                            store.eyeCare.enabled.toggle()
                        }
                        store.saveSnapshot()
                        showFlash(store.eyeCare.enabled ? "已开启护眼滤镜" : "已关闭护眼滤镜")
                    } label: {
                        Label(
                            store.eyeCare.enabled ? "关闭护眼滤镜" : "开启护眼滤镜",
                            systemImage: store.eyeCare.enabled ? "leaf.fill" : "leaf"
                        )
                    }

                    Button {
                        settings.purifyText.toggle()
                        store.saveSnapshot()
                        showFlash(settings.purifyText ? "已净化正文" : "已恢复原文")
                    } label: {
                        Label(settings.purifyText ? "恢复原文" : "净化正文", systemImage: "line.3.horizontal.decrease")
                    }

                    Button {
                        showSettings = true
                    } label: {
                        Label("阅读设置", systemImage: "textformat.size")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(chromeColor)
                        .glassCircle(diameter: 40)
                }
                .buttonStyle(PressableStyle())
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
    }

    private var bottomBar: some View {
        GlassEffectContainer(spacing: 12) {
            VStack(spacing: 12) {
                HStack(spacing: 9) {
                    Text(settings.pageMode == .scroll ? "滚动" : "\(pageIndex + 1) / \(pageCount)")
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .foregroundStyle(readerColor(effectiveSurface.secondary))
                        .monospacedDigit()

                    ProgressBar(
                        value: progress,
                        tint: readerColor(effectiveSurface.accent),
                        track: readerColor(effectiveSurface.text).opacity(0.16),
                        height: 2.5
                    )

                    Text("\(Int(progress * 100))%")
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .foregroundStyle(readerColor(effectiveSurface.secondary))
                        .monospacedDigit()
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 13)
                .glassCapsule(tint: effectiveSurface.isDark ? .white.opacity(0.06) : .white.opacity(0.45))

                HStack(spacing: 0) {
                    toolButton("目录", symbol: "list.bullet") { showTOC = true }
                    toolButton("书签", symbol: isBookmarked ? "bookmark.fill" : "bookmark") {
                        store.toggleBookmark(
                            book: book,
                            chapterTitle: currentChapterTitle,
                            pageIndex: pageIndex,
                            progress: progress,
                            paragraphID: currentAnchorParagraphID,
                            offset: currentAnchorOffset
                        )
                    }
                    toolButton("听书", symbol: "speaker.wave.2") { showListen = true }
                    // 段评与版心的开关已统一迁到「阅读设置」，正文工具栏不再重复放控件。
                    toolButton("设置", symbol: "textformat.size") { showSettings = true }
                }
                .padding(.vertical, 7)
                .padding(.horizontal, 6)
                .glassSurface(cornerRadius: 30, tint: effectiveSurface.isDark ? .white.opacity(0.05) : .white.opacity(0.4))
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 4)
    }

    private func toolButton(_ title: String, symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 5) {
                Image(systemName: symbol)
                    .font(.system(size: 16, weight: .medium))
                Text(title)
                    .font(.system(size: 9.5, weight: .medium))
            }
            .foregroundStyle(chromeColor)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 7)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
    }

    /// 抓手松手后才落地。三个值在同一个事务里改完，合成一个观察点，
    /// 一次拖动只重建一次页表。
    private func applyFrame(sideMargin: Double, topMargin: Double, bottomMargin: Double) {
        guard sideMargin != settings.sideMargin
                || topMargin != settings.topMargin
                || bottomMargin != settings.bottomMargin else { return }
        // 松手后只重排一次，由三个值合在一起的观察点触发；
        // 同一个事务里的多次写入不会被拆成多次排版。
        settings.sideMargin = sideMargin
        settings.topMargin = topMargin
        settings.bottomMargin = bottomMargin
        store.saveSnapshot()
    }

    // MARK: Actions

    private func toggleChrome() {
        withAnimation(.spring(response: 0.34, dampingFraction: 0.86)) {
            showChrome.toggle()
        }
    }

    /// 只在「工具栏是收起的」状态下调用的唤出动作（音量键、外接键盘等路径用）。
    /// 用显式的 true 而不是 toggle：若中途状态被别的路径改过，
    /// toggle 会把工具栏又收回去，读者会以为点击没生效。
    private func revealChrome() {
        guard !showChrome else { return }
        withAnimation(.spring(response: 0.34, dampingFraction: 0.86)) {
            showChrome = true
        }
    }

    private func hideChromeAfterDelay() {
        withAnimation(.spring(response: 0.34, dampingFraction: 0.86)) {
            showChrome = false
        }
    }

    private func excerpt(_ paragraph: Paragraph) {
        store.addExcerpt(
            book: book,
            chapter: currentChapterTitle,
            text: paragraph.text
        )
        showFlash("已摘录这一句")
    }

    private func turnPage(forward: Bool) {
        guard settings.pageMode == .slide else {
            showFlash("上下滚动模式请直接滑动")
            return
        }
        withAnimation(.spring(response: 0.32, dampingFraction: 0.85)) {
            if forward {
                pageIndex = min(pageIndex + 1, max(pageCount - 1, 0))
            } else {
                pageIndex = max(pageIndex - 1, 0)
            }
        }
    }

    private func showFlash(_ text: String) {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            flash = text
        }

        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.5))
            if flash == text {
                withAnimation(.easeOut(duration: 0.24)) {
                    flash = nil
                }
            }
        }
    }

    /// 把这本书已解析的正文导出成 TXT，交给 `ShareLink` 分享。
    /// 用阅读页持有的 `chapters`（段落已经过净化/分段），这样本地书、演示书、
    /// 网络书都能导出同一份「读者此刻看到的内容」，而不是只认在线缓存。
    private func exportCurrentBook() -> ExportedTextFile? {
        let all = store.chapters(for: book)
        guard !all.isEmpty else { return nil }

        var text = book.title + "\n"
        if !book.author.isEmpty { text += "作者：\(book.author)\n" }
        text += "\n"

        var empty = 0
        for chapter in all {
            text += chapter.title + "\n\n"
            let body = chapter.paragraphs.map(\.text).joined(separator: "\n")
            if body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                empty += 1
                text += "【本章正文尚未加载】\n\n"
            } else {
                text += body + "\n\n"
            }
        }

        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("YeHangExports", isDirectory: true)
        let folder = root.appendingPathComponent(UUID().uuidString, isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            // 每次导出换一个 UUID 目录，旧的导出留着不删也无妨——系统会在临时目录
            // 压力下自行回收；这里不做激进删除，避免误删正在被分享面板使用的文件。
            let safeName = book.title
                .components(separatedBy: CharacterSet(charactersIn: "/\\:"))
                .joined(separator: "_")
            let filename = (safeName.isEmpty ? "书籍" : safeName) + ".txt"
            let url = folder.appendingPathComponent(filename)
            try text.write(to: url, atomically: true, encoding: .utf8)
            return ExportedTextFile(url: url, chapterCount: all.count, emptyChapters: empty)
        } catch {
            showFlash("导出失败：\(error.localizedDescription)")
            return nil
        }
    }

    private func bootstrap() {
        if usesFullscreenFrame {
            // 全屏正文不应被首次出现的顶部按钮盖住；点正文仍可唤出工具栏。
            showChrome = false
        }
        rebuild(restore: true, targetChapter: initialChapterTitle)

        // 在线书：本地还没有目录时先拉目录，拉到再重排。
        // 已有缓存就直接显示，避免每次打开都等网络。
        if book.isNetworkBook && (store.customChapters[book.id]?.isEmpty ?? true) {
            isLoadingNetwork = true
            Task { @MainActor in
                let loaded = await store.loadNetworkChapters(for: book)
                isLoadingNetwork = false
                guard !loaded.isEmpty else {
                    networkError = store.engine.lastError ?? "目录加载失败"
                    return
                }
                rebuild(restore: true, targetChapter: initialChapterTitle)
                await ensureCurrentChapterContent()
            }
        } else if book.isNetworkBook {
            // 目录有缓存，但当前章可能还没拉正文。
            Task { @MainActor in await ensureCurrentChapterContent() }
        }

        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        if startInFrameAdjust {
            showChrome = false
            showFrameAdjust = true
        } else if arguments.contains("-showReaderSettings") {
            showSettings = true
        } else if arguments.contains("-showComments") {
            commentParagraph = chapters.flatMap(\.paragraphs).first { !$0.comments.isEmpty }
        } else if arguments.contains("-hideChrome") {
            showChrome = false
        }
        if arguments.contains("-showTOC") { showTOC = true }
        if arguments.contains("-showBookmarks") { showBookmarks = true }
        if arguments.contains("-showListen") { showListen = true }
        if arguments.contains("-showSourceSwitch") { showSourceSwitch = true }
        if arguments.contains("-frameAdjust") {
            showFrameAdjust = true
            showChrome = false
        }
        if arguments.contains("-coverTurn") { settings.pageTurnEffect = .cover }
        if arguments.contains("-noTurn") { settings.pageTurnEffect = .none }
        if arguments.contains("-scrollMode") { settings.pageMode = .scroll }
        if arguments.contains("-slideMode") { settings.pageMode = .slide }
        #endif
    }

    /// 在线书的正文是按章懒加载的：目录阶段只有标题，正文要等翻到这一章才拉。
    /// 拉完重排一次，让分页把新段落算进去。
    private func ensureCurrentChapterContent() async {
        guard book.isNetworkBook, !chapters.isEmpty else { return }
        // pages 为空时 currentChapterTitle 会退到 book.lastPosition，
        // 那可能不是真实章节名，所以优先按「当前页 → 锚点 → 第一章」找。
        let targetTitle = currentPage?.chapterTitle
            ?? store.position(for: book.id)?.chapterTitle
            ?? chapters.first?.title
        guard let targetTitle,
              let chapter = chapters.first(where: { $0.title == targetTitle }),
              chapter.paragraphs.isEmpty else { return }

        isLoadingNetwork = true
        let paragraphs = await store.loadNetworkContent(for: book, chapterID: chapter.id)
        isLoadingNetwork = false

        guard let paragraphs, !paragraphs.isEmpty else {
            networkError = store.engine.lastError ?? "正文加载失败"
            return
        }
        networkError = nil
        rebuild(restore: false, targetChapter: targetTitle)
    }

    /// 按章节标题补正文。目录里点某一章时用，标题可能不带正文。
    private func ensureChapterContent(title: String) async {
        guard book.isNetworkBook,
              let chapter = chapters.first(where: { $0.title == title }),
              chapter.paragraphs.isEmpty else {
            if isScrollMode {
                updateScrollProgress()
                syncProgress()
            }
            return
        }

        isLoadingNetwork = true
        let paragraphs = await store.loadNetworkContent(for: book, chapterID: chapter.id)
        isLoadingNetwork = false

        guard paragraphs?.isEmpty == false else {
            networkError = store.engine.lastError ?? "正文加载失败"
            return
        }
        networkError = nil
        rebuild(restore: true, targetChapter: title)
    }

    /// 预取后续章节正文。`loadNetworkContent` 会把正文写回快照并落盘，
    /// 所以提前拉一遍就是真实可用的离线缓存，不再只更新一个估算数字。
    private func prefetchFollowingChapters() async {
        guard book.isNetworkBook else {
            showFlash("本地书的正文已在设备上，无需缓存")
            return
        }
        let anchor = currentPage?.chapterTitle
            ?? store.position(for: book.id)?.chapterTitle
            ?? chapters.first?.title
        guard let anchor,
              let start = chapters.firstIndex(where: { $0.title == anchor }) else {
            showFlash("还没有可缓存的目录")
            return
        }
        let following = Array(chapters[(start + 1)...].prefix(3))
        let pending = following.filter { $0.paragraphs.isEmpty }
        guard !pending.isEmpty else {
            showFlash(following.isEmpty ? "已经是最后一章" : "后续 \(following.count) 章已在本地")
            return
        }

        isLoadingNetwork = true
        defer { isLoadingNetwork = false }
        var cached = 0
        for chapter in pending {
            let paragraphs = await store.loadNetworkContent(for: book, chapterID: chapter.id)
            if paragraphs?.isEmpty == false { cached += 1 }
        }
        networkError = cached == 0 ? (store.engine.lastError ?? "缓存失败") : nil
        showFlash(cached > 0 ? "已缓存后续 \(cached) 章正文" : "缓存失败，请检查书源或网络")
        rebuild(restore: false)
    }

    /// 找到某个段落所属的章节。段评要按「章 + 段」去书源上取，
    /// 只给段落 ID 拿不到 chapter URL。
    private func chapterContaining(paragraph: Paragraph) -> Chapter? {
        chapters.first { chapter in
            chapter.paragraphs.contains { $0.id == paragraph.id }
        }
    }

    /// 读到最后一段时提前拉下一章，翻页时就不用等。
    /// 只拉当前页所在章节的下一章，避免把整本书的正文都拉下来。
    private func loadNextChapterIfNeeded() {
        guard book.isNetworkBook, let page = currentPage else { return }

        // 只有「下一页已经是另一章」时才算快到章尾。
        let nextPageIndex = pageIndex + 1
        let atChapterEnd: Bool = {
            guard let next = pagination?.page(at: nextPageIndex) else { return true }
            return next.chapterID != page.chapterID
        }()
        guard atChapterEnd,
              let index = chapters.firstIndex(where: { $0.id == page.chapterID }),
              index + 1 < chapters.count,
              chapters[index + 1].paragraphs.isEmpty else { return }

        let next = chapters[index + 1]
        Task { @MainActor in
            let paragraphs = await store.loadNetworkContent(for: book, chapterID: next.id)
            guard paragraphs?.isEmpty == false else { return }
            // 只重排，不跳转：读者还在原页，等他自己翻过去。
            rebuild(restore: false)
        }
    }

    /// 重排整本书。
    ///
    /// 排版放到后台队列：50 万字的整本排完约 0.1 秒，在主线程上做会明显卡住
    /// 拖字号滑块的动画。代价是结果回来得晚一拍，所以带了一个代数（generation）：
    /// 期间又发起了新的重排，这次的结果就直接丢掉 —— 不然晚到的旧排版
    /// 会把新的盖回去，表现为「字号调大了又自己变回去」。
    ///
    /// - Parameters:
    ///   - restore: 是否按持久化的阅读位置落脚。
    ///   - targetChapter: 指定落到这一章的开头（目录跳转、补正文后）。
    private func rebuild(restore: Bool, targetChapter: String? = nil) {
        guard viewport.width > 1, viewport.height > 1 else { return }

        // P2-03 / 技术评审：rebuild 计数器（四任务共用同一口径）。
        // 纯换色必须 rebuild=0；只有字体族真实变化才允许 bump 一次。
        Self.rebuildCount += 1
        #if DEBUG
        DiagnosticLog.shared.record(.info, category: "主题", message: "rebuild #\(Self.rebuildCount)")
        #endif

        // 锚点用「当前页首段的段落 ID」而不是页序号：重排后同一段文字
        // 可能不再是某页的第一段，所以要按「包含该段」去找。
        // 滚动模式下当前页首段没有意义，改取滚动定位到的段落。
        let anchorParagraphID: String? = isScrollMode
            ? scrollParagraphID
            : currentPage?.firstParagraphID
        let anchorChapterID: String? = isScrollMode
            ? nil
            : currentPage?.chapterID
        let previousIndex = pageIndex
        let previousProgress = progress

        let snapshot = chapters
        let text = snapshot.map { chapter in
            ChapterText(
                id: chapter.id,
                title: chapter.title,
                paragraphs: chapter.paragraphs.map {
                    SourceParagraph(
                        id: $0.id,
                        text: ReaderTypography.displayText($0, purify: settings.purifyText)
                    )
                }
            )
        }
        let hasComments = snapshot.contains { chapter in
            chapter.paragraphs.contains { !$0.comments.isEmpty }
        }
        let typeface = ReaderTypography.typeface(settings)
        let size = ReaderMetrics.textSize(
            in: viewport,
            sideMargin: settings.sideMargin,
            topMargin: settings.topMargin,
            bottomMargin: settings.bottomMargin,
            hasComments: hasComments && !settings.hideSourceComments
        )
        let chapterCount = max(snapshot.count, book.chapterCount)

        paginationGeneration += 1
        let generation = paginationGeneration

        Task { @MainActor in
            let pages = await Self.paginate(text, typeface: typeface, size: size)
            guard generation == paginationGeneration else { return }

            let paginated = PaginatedBook(
                chapters: snapshot,
                typeface: typeface,
                size: size,
                pages: pages,
                hasComments: hasComments && !settings.hideSourceComments,
                purifyText: settings.purifyText
            )
            pagination = paginated
            pageIndex = Self.resolveIndex(
                in: paginated,
                restore: restore,
                targetChapter: targetChapter,
                anchorChapterID: anchorChapterID,
                anchorParagraphID: anchorParagraphID,
                progress: previousProgress,
                previousIndex: previousIndex,
                chapterCount: chapterCount,
                position: store.position(for: book.id)
            )

            // 分页算出的落点也是滚动模式的恢复位置：让滚动视图直接滚到那一段。
            if isScrollMode {
                scrollParagraphID = paginated.page(at: pageIndex)?.firstParagraphID
                updateScrollProgress()
            }

            syncProgress()
        }
    }

    /// 后台排版。`ChapterLayout` 持有 `NSAttributedString`，不是线程无关的，
    /// 所以整件事都在同一个后台任务里做完，只把可跨线程的 `[ReadingPage]` 交回来。
    private static func paginate(
        _ chapters: [ChapterText],
        typeface: ReaderTypeface,
        size: CGSize
    ) async -> [ReadingPage] {
        await Task.detached(priority: .userInitiated) {
            ChapterPagination.pages(for: chapters, style: typeface.style(), size: size)
        }.value
    }

    /// 重排后该停在哪一页。
    ///
    /// 优先级是「越具体越优先」：
    /// 1. 指定的章节（目录点击、补完正文）；
    /// 2. 持久化的位置（打开书时）；
    /// 3. 改字号前的锚点段落（最精确，段落 ID 与字号无关）；
    /// 4. 改字号前的页码（段落都没了的极端情况）；
    /// 5. 百分比（连页码都对不上的最后兜底）。
    ///
    /// 每一步都只在真的找到时才用，找不到就往下走 —— 不猜。
    private static func resolveIndex(
        in paginated: PaginatedBook,
        restore: Bool,
        targetChapter: String?,
        anchorChapterID: String?,
        anchorParagraphID: String?,
        progress: Double,
        previousIndex: Int,
        chapterCount: Int,
        position: ReadingPosition?
    ) -> Int {
        let pages = paginated.pages
        guard !pages.isEmpty else { return 0 }

        func index(ofChapterTitled title: String) -> Int? {
            pages.firstIndex { $0.chapterTitle == title }
        }
        func index(ofChapterWithID id: String) -> Int? {
            pages.firstIndex { $0.chapterID == id }
        }
        /// 找到「包含这一段的页」。用包含而不是「首段等于」，因为
        /// 重排后同一段可能不再是某页的第一段。
        func index(containing paragraphID: String, inChapter chapterID: String?) -> Int? {
            pages.firstIndex { page in
                (chapterID == nil || page.chapterID == chapterID)
                    && page.slices.contains { $0.paragraphID == paragraphID }
            }
        }

        if let targetChapter, let index = index(ofChapterTitled: targetChapter) {
            return index
        }

        if restore, let position {
            if let index = index(containing: position.paragraphID, inChapter: nil) {
                return index
            }
            if let index = index(ofChapterTitled: position.chapterTitle) {
                return index
            }
        }

        if !restore {
            if let anchorParagraphID, let index = index(containing: anchorParagraphID, inChapter: anchorChapterID) {
                return index
            }
            if let anchorChapterID, let index = index(ofChapterWithID: anchorChapterID) {
                return index
            }
            if pages.indices.contains(previousIndex) {
                return min(previousIndex, pages.count - 1)
            }
        }

        // 最后兜底：按百分比找最接近的一页。
        // 这条路径会让书签落在段中间也说不定，所以放在最后 ——
        // 前面的锚点都失效时才用。
        return ReadingProgress.pageIndex(nearest: progress, in: pages, chapterCount: chapterCount) ?? 0
    }

    /// 某个章节的首页。章节还没正文时返回 nil，由调用方决定停在原处。
    private func pageIndex(ofChapterTitled title: String) -> Int? {
        pagination?.pages.firstIndex { $0.chapterTitle == title }
    }

    /// 跳转到书签：优先按段落锚点定位，旧书签没有锚点时才回退到页序号。
    private func jump(to bookmark: Bookmark) {
        if isScrollMode {
            scrollParagraphID = bookmark.paragraphID
            updateScrollProgress()
            syncProgress()
            return
        }
        guard let paginated = pagination, !paginated.isEmpty else { return }

        let target: Int? = bookmark.paragraphID.flatMap { id in
            paginated.pages.firstIndex { page in
                page.chapterTitle == bookmark.chapterTitle
                    && page.slices.contains { $0.paragraphID == id }
            }
        }
        let chapterStart = paginated.pages.firstIndex { $0.chapterTitle == bookmark.chapterTitle }
        // 段落在重排后可能已经不是某一页的第一段，也可能整段被换源换掉了。
        // 三级回落：段落 → 该章首页 → 旧页序号。
        let resolved = target
            ?? chapterStart
            ?? min(max(bookmark.pageIndex, 0), paginated.pages.count - 1)
        withAnimation(.spring(response: 0.32, dampingFraction: 0.85)) {
            pageIndex = resolved
        }
    }

    /// 把「当前可见段落在整个阅读顺序中的位置」换算成百分比，与分页模式的口径一致。
    private func updateScrollProgress() {
        var total = 0
        var seen = 0
        var found = false
        for chapter in chapters {
            for paragraph in chapter.paragraphs {
                total += 1
                if !found {
                    if paragraph.id == scrollParagraphID { found = true } else { seen += 1 }
                }
            }
        }
        guard total > 0 else {
            scrollProgress = 0
            return
        }
        scrollProgress = min(max(Double(seen) / Double(total), 0), 1)
    }

    /// 把距上次结算的停留时间计入统计。> 4 小时的间隔视为后台挂起，
    /// 不计入阅读时长，避免把离线时间算成读数。
    private func flushReadingTime() {
        let now = Date()
        let elapsed = now.timeIntervalSince(lastReadingTick)
        lastReadingTick = now
        guard elapsed >= 1, elapsed <= 14_400 else { return }
        store.recordReading(elapsedMilliseconds: Int64(elapsed * 1_000), bookName: book.title)
    }

    private func syncProgress() {
        flushReadingTime()
        if isScrollMode {
            let anchor = scrollAnchor
            guard let chapterTitle = anchor.chapterTitle, let paragraphID = anchor.paragraphID else { return }
            let chapter = chapters.first { $0.title == chapterTitle }
            let offset: Int = {
                guard let chapter,
                      let index = chapter.paragraphs.firstIndex(where: { $0.id == paragraphID }) else { return 0 }
                return chapter.paragraphs.prefix(index).reduce(0) { $0 + $1.text.utf16.count }
            }()
            store.updateProgress(
                bookID: book.id,
                progress: scrollProgress,
                position: chapterTitle,
                chapterTitle: chapterTitle,
                paragraphID: paragraphID,
                offset: offset
            )
            return
        }
        guard let page = currentPage else { return }
        store.updateProgress(
            bookID: book.id,
            progress: progress,
            position: page.chapterTitle,
            chapterTitle: page.chapterTitle,
            paragraphID: page.firstParagraphID,
            offset: page.chapterRange.location
        )
    }
}

// MARK: - Cover pager

struct PageFlipReader: View {
    let pagination: PaginatedBook
    let bookTitle: String
    @Binding var pageIndex: Int
    let settings: ReaderSettings
    let onComment: (Paragraph) -> Void
    let onSelect: (Paragraph) -> Void
    /// 落点与触摸层尺寸：由阅读页决定左右翻页还是唤出工具栏。
    let onTap: (CGPoint, CGSize) -> Void

    @State private var offset: CGFloat = 0

    private var current: ReadingPage? { pagination.page(at: pageIndex) }
    private var next: ReadingPage? { pagination.page(at: pageIndex + 1) }
    private var previous: ReadingPage? { pagination.page(at: pageIndex - 1) }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                if settings.pageTurnEffect == .cover {
                    if offset < 0, let next {
                        pageView(next, index: pageIndex + 1)
                    } else if offset > 0, let previous {
                        pageView(previous, index: pageIndex - 1)
                    }
                }

                if let current {
                    pageView(current, index: pageIndex)
                        .offset(x: offset)
                        .shadow(
                            color: .black.opacity(offset == 0 ? 0 : 0.28),
                            radius: 18,
                            x: offset > 0 ? -10 : 10
                        )
                }
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 12)
                    .onChanged { value in
                        guard settings.pageTurnEffect == .cover else { return }
                        offset = value.translation.width * 0.92
                    }
                    .onEnded { value in
                        let width = geometry.size.width
                        let threshold = min(max(width * 0.18, 48), 120)
                        let translation = value.predictedEndTranslation.width * (settings.direction == .rtl ? -1 : 1)

                        if settings.pageTurnEffect == .cover {
                            if translation < -threshold, next != nil {
                                withAnimation(.easeOut(duration: 0.22)) { offset = -width }
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                                    pageIndex += 1
                                    offset = 0
                                }
                            } else if translation > threshold, previous != nil {
                                withAnimation(.easeOut(duration: 0.22)) { offset = width }
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                                    pageIndex -= 1
                                    offset = 0
                                }
                            } else {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.86)) { offset = 0 }
                            }
                        } else if translation < -threshold, next != nil {
                            pageIndex += 1
                        } else if translation > threshold, previous != nil {
                            pageIndex -= 1
                        }
                    }
            )
        }
    }

    private func pageView(_ page: ReadingPage, index: Int) -> some View {
        ReaderPageView(
            pagination: pagination,
            page: page,
            pageIndex: index,
            bookTitle: bookTitle,
            settings: settings,
            onComment: onComment,
            onSelect: onSelect,
            onTap: onTap
        )
    }
}

// MARK: - Page

/// 一页正文。
///
/// 文字由 CoreText 直接画（`CoreTextPageView`），不用 `Text`：
/// 分页时量的是 `CTFramesetterCreateFrame` 的结果，画的时候必须是同一套
/// 排版，否则量出来放得下、画出来放不下，结局就是文字被裁。
///
/// 段评胶囊是叠在绘制层上的独立按钮：CoreText 画出来的字拿不到 SwiftUI
/// 的点击，所以位置由 `PageParagraphBox` 算好，按钮绝对定位到那一行。
struct ReaderPageView: View {
    @Environment(\.theme) private var appTheme
    @Environment(\.readerTextColor) private var readerTextColor
    let pagination: PaginatedBook
    let page: ReadingPage
    let pageIndex: Int
    let bookTitle: String
    let settings: ReaderSettings
    let onComment: (Paragraph) -> Void
    let onSelect: (Paragraph) -> Void
    /// 落点与触摸层尺寸：由阅读页决定左右翻页还是唤出工具栏。
    let onTap: (CGPoint, CGSize) -> Void

    /// 本页正文的范围。绘制层与命中测试共用同一个区域。
    private var textSize: CGSize { pagination.size }

    private var showsHeader: Bool {
        settings.showHeaderFooter && settings.topMargin >= 24
    }

    private var showsFooter: Bool {
        settings.showHeaderFooter && settings.bottomMargin >= 24
    }

    /// 本页每个段落的盒子里有段评的那些。按段下标索引，用来摆胶囊。
    private var commentBoxes: [(box: PageParagraphBox, paragraph: Paragraph)] {
        guard !settings.hideSourceComments, pagination.hasComments else { return [] }
        return pagination.paragraphBoxes(for: page).compactMap { box in
            guard let chapter = pagination.chapter(withID: page.chapterID),
                  chapter.paragraphs.indices.contains(box.paragraphIndex) else { return nil }
            let paragraph = chapter.paragraphs[box.paragraphIndex]
            guard !paragraph.comments.isEmpty else { return nil }
            return (box, paragraph)
        }
    }

    var body: some View {
        // 页眉页脚浮在正文之外。版面起点必须是 `topMargin` 本身：
        // 微调时抓手画在哪条线上，正文就该从哪条线开始，否则拖到页面最上沿
        // 也挪不动第一行，读者会觉得这个边界是假的。
        textLayer
            .padding(.horizontal, settings.sideMargin)
            .padding(.top, settings.topMargin)
            .padding(.bottom, settings.bottomMargin)
            .overlay(alignment: .top) {
                if showsHeader {
                    HStack {
                        Text(page.chapterTitle)
                        Spacer()
                        // 章内页码：整本页码在几百万字的长篇里会数到好几千，
                        // 读者真正关心的是「这一章还剩几页」。
                        Text("\(page.pageIndexInChapter + 1) / \(pagination.chapterPageCounts[page.chapterID] ?? 1)")
                            .monospacedDigit()
                    }
                    .font(.system(size: 10, weight: .medium))
                    .tracking(0.9)
                    .foregroundStyle(appTheme.secondary)
                    .padding(.horizontal, settings.sideMargin)
                    // 页眉始终落在正文起点之前：上边界拖小后，固定减 32 会把
                    // 页眉推进第一行里，看起来像版心线没生效。留 14 点至少
                    // 容下一行小字的高度。
                    .padding(.top, min(max(settings.topMargin - 32, 8), max(settings.topMargin - 18, 8)))
                }
            }
            .overlay(alignment: .bottom) {
                if showsFooter {
                    HStack {
                        Text(bookTitle)
                        Spacer()
                        Text(page.chapterTitle)
                    }
                    .font(.system(size: 9.5))
                    .foregroundStyle(appTheme.secondary.opacity(0.55))
                    .padding(.horizontal, settings.sideMargin)
                    .padding(.bottom, min(max(settings.bottomMargin - 30, 8), max(settings.bottomMargin - 14, 8)))
                }
            }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .environment(\.layoutDirection, .leftToRight)
    }

    private var textLayer: some View {
        ZStack(alignment: .topLeading) {
            CoreTextPageView(
                text: colored(pagination.text(for: page)),
                size: textSize
            )

            // 触摸层压在文字上：点一下收放工具栏，长按选中一段。
            // 它只装 tap 与 long press，手指一移动就失败，
            // 所以外层的滑动手势不受影响。
            PageTouchSurface(
                onTap: onTap,
                onLongPress: { point in
                    if let paragraph = pagination.paragraph(at: point, in: page) {
                        onSelect(paragraph)
                    }
                }
            )

            ForEach(commentBoxes, id: \.paragraph.id) { item in
                Button {
                    onComment(item.paragraph)
                } label: {
                    HStack(spacing: 2.5) {
                        Image(systemName: "text.bubble.fill")
                        Text("\(item.paragraph.comments.count)")
                            .monospacedDigit()
                    }
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(appTheme.accent)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3.5)
                    .glassCapsule(tint: appTheme.accent.opacity(0.14))
                }
                .buttonStyle(.plain)
                // 贴在段尾那一行的文字末尾。末行通常不满宽，气泡跟在字后；
                // 末行排满时右侧预留的 gutter 正好接住它，不会压到正文。
                .offset(
                    x: item.box.lastLine.maxX + 4,
                    y: item.box.lastLine.minY + 2
                )
            }

            if page.overflows {
                // 连一行都放不下：如实说清楚，而不是把字裁掉装作正常。
                Text("这一页放不下一行，请调小字号或减小留白")
                    .font(.system(size: 11))
                    .foregroundStyle(appTheme.accent)
                    .padding(10)
                    .glassCapsule()
            }
        }
        .frame(width: textSize.width, height: textSize.height, alignment: .topLeading)
    }

    /// 把主题的文字颜色刷进富文本。字体与间距已经在排版里定好，这里只改颜色。
    private func colored(_ text: NSAttributedString) -> NSAttributedString {
        guard text.length > 0 else { return text }
        let copy = NSMutableAttributedString(attributedString: text)
        copy.addAttribute(
            .foregroundColor,
            value: readerTextColor,
            range: NSRange(location: 0, length: copy.length)
        )
        return copy
    }
}

struct ParagraphView: View {
    @Environment(\.theme) private var appTheme
    let paragraph: Paragraph
    let settings: ReaderSettings
    let onComment: (Paragraph) -> Void
    let onExcerpt: (Paragraph) -> Void

    private var showsComments: Bool {
        !paragraph.comments.isEmpty && !settings.hideSourceComments
    }

    private var displayText: String {
        (settings.indent ? "　　" : "") + ReaderTypography.displayText(paragraph, purify: settings.purifyText)
    }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Text(displayText)
                .font(.system(
                    size: settings.fontSize,
                    weight: settings.fontWeight.weight,
                    design: settings.fontDesign.design
                ))
                .lineSpacing(settings.fontSize * settings.lineSpacing)
                .foregroundStyle(appTheme.text)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.trailing, showsComments ? 30 : 0)

            if showsComments {
                Button {
                    onComment(paragraph)
                } label: {
                    HStack(spacing: 2.5) {
                        Image(systemName: "text.bubble.fill")
                        Text("\(paragraph.comments.count)")
                            .monospacedDigit()
                    }
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(appTheme.accent)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3.5)
                    .glassCapsule(tint: appTheme.accent.opacity(0.14))
                }
                .buttonStyle(.plain)
                .offset(y: -2)
            }
        }
        .contextMenu {
            Button {
                onExcerpt(paragraph)
            } label: {
                Label("摘录这一段", systemImage: "quote.opening")
            }

            if !paragraph.comments.isEmpty {
                Button {
                    onComment(paragraph)
                } label: {
                    Label("查看 \(paragraph.comments.count) 条段评", systemImage: "text.bubble")
                }
            }

            Button {
                UIPasteboard.general.string = paragraph.text
            } label: {
                Label("复制", systemImage: "doc.on.doc")
            }
        }
    }
}

struct ScrollReaderView: View {
    @Environment(\.theme) private var appTheme
    let chapters: [Chapter]
    let settings: ReaderSettings
    @Binding var visibleParagraphID: String?
    let onComment: (Paragraph) -> Void
    let onExcerpt: (Paragraph) -> Void
    let onTap: () -> Void

    /// 章节标题与段落拍平成一行行，这样章节标题也能参与滚动定位，段落之间仍保持原有间距。
    /// 标题行用章节的稳定 id 做标识：同名章节（「番外」「序」）标题会重复，
    /// 拿标题拼 id 会让 ForEach 出现重复标识。
    private enum Row: Identifiable {
        case heading(id: String, title: String)
        case paragraph(Paragraph)

        var id: String {
            switch self {
            case .heading(let id, _): return id
            case .paragraph(let paragraph): return paragraph.id
            }
        }
    }

    private var rows: [Row] {
        chapters.flatMap { chapter -> [Row] in
            [.heading(id: "h-\(chapter.id)", title: chapter.title)] + chapter.paragraphs.map { Row.paragraph($0) }
        }
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(rows) { row in
                    switch row {
                    case .heading(_, let title):
                        VStack(alignment: .leading, spacing: 6) {
                            Text(title)
                                .font(.system(size: 13, weight: .semibold, design: .serif))
                                .tracking(1.4)
                                .foregroundStyle(appTheme.secondary)

                            Rectangle()
                                .fill(appTheme.secondary.opacity(0.3))
                                .frame(width: 26, height: 1.5)
                        }
                        .padding(.top, 30)
                        .padding(.bottom, 14)

                    case .paragraph(let paragraph):
                        ParagraphView(
                            paragraph: paragraph,
                            settings: settings,
                            onComment: onComment,
                            onExcerpt: onExcerpt
                        )
                        .padding(.bottom, settings.fontSize * (0.72 + settings.lineSpacing * 0.5))
                    }
                }
            }
            .scrollTargetLayout()
            .padding(.horizontal, settings.sideMargin)
            // 上下留白与分页共用一套刻度：切到滚动模式时版心不会突然变宽变高。
            .padding(.top, max(settings.topMargin - 6, 0))
            .padding(.bottom, max(settings.bottomMargin - 22, 0))
            .environment(\.layoutDirection, .leftToRight)
        }
        .scrollIndicators(.hidden)
        // 绑定当前可见段落：滚动时回写进度，恢复位置时把绑定值设回去即可自动滚到该段。
        .scrollPosition(id: $visibleParagraphID)
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
    }
}

// MARK: - 段落操作

/// 长按选中一段后弹出的操作条。
///
/// 分页模式的正文是 CoreText 直接画的，拿不到系统的文字选择菜单
/// （`Text` 才有）。所以自己命中出是哪一段，在这里给出三件事：
/// 摘录、看段评、复制。范围是**整段**而不是任意选区 ——
/// 做真正的跨段选字需要自己实现一整套选择手柄，而读者在这里要的
/// 往往就是「把这一段留下」。
struct ParagraphActionsSheet: View {
    @Environment(\.theme) private var theme
    let paragraph: Paragraph
    let onExcerpt: () -> Void
    let onComment: () -> Void
    let onCopy: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(paragraph.text)
                .font(.system(size: 13))
                .foregroundStyle(theme.text)
                .lineLimit(3)
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 10) {
                action("摘录", symbol: "quote.opening", action: onExcerpt)
                action(
                    paragraph.comments.isEmpty ? "段评" : "段评 \(paragraph.comments.count)",
                    symbol: "text.bubble",
                    action: onComment
                )
                action("复制", symbol: "doc.on.doc", action: onCopy)
            }

            Spacer(minLength: 0)
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(AppBackdrop())
    }

    private func action(_ title: String, symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: symbol)
                    .font(.system(size: 17, weight: .medium))
                Text(title)
                    .font(.system(size: 10.5, weight: .medium))
            }
            .foregroundStyle(theme.text)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .glassSurface(cornerRadius: 16)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle(scale: 0.97))
    }
}

// MARK: - Frame Adjust

/// 版心微调的四个抓手。
///
/// 拖动过程只改本地值并画一层遮罩，正文一次都不重排；松手才把结果交给阅读页，
/// 由它统一改设置、重排、落盘。这样拖一次最多排一次版，字也不会在指头下跳来跳去。
struct ReaderFrameAdjustOverlay: View {
    @Environment(\.theme) private var appTheme
    let viewport: CGSize
    let theme: ReaderTheme
    let initialSideMargin: Double
    let initialTopMargin: Double
    let initialBottomMargin: Double
    let bottomSafeAreaInset: CGFloat
    let onCommit: (Double, Double, Double) -> Void
    let onDone: () -> Void

    @State private var sideDrag: (start: Double, current: Double)?
    @State private var topDrag: (start: Double, current: Double)?
    @State private var bottomDrag: (start: Double, current: Double)?

    private var sideMargin: Double { sideDrag?.current ?? initialSideMargin }
    private var topMargin: Double { topDrag?.current ?? initialTopMargin }
    private var bottomMargin: Double { bottomDrag?.current ?? initialBottomMargin }

    var body: some View {
        let page = viewport
        // 正文与边界线共用同一组刻度；虚线在绘制时再向外让一点，
        // 免得首尾那个字压在线上。
        let textBox = CGRect(
            x: sideMargin,
            y: topMargin,
            width: max(page.width - sideMargin * 2, 40),
            height: max(page.height - topMargin - bottomMargin, 40)
        )
        // 左右落在正文边缘内 2 点：末端那几个字的笔画会探到版心线外，
        // 不往里收一点，虚线就穿字而过。上下留出一行的高度，不切字头字脚。
        let frame = CGRect(
            x: textBox.minX + 2,
            y: textBox.minY - 2,
            width: max(textBox.width - 4, 8),
            height: max(textBox.height + 4, 8)
        )

        ZStack(alignment: .topLeading) {
            // 版心外按底色遮住。遮成不透明而不是压暗，是因为文字此刻仍是旧版心的
            // 排版：只压暗会看到字从框外继续往外排，读者分不清哪条线才是边界。
            // 遮住之后，框外就是页边，底部按钮也有了一块不会压住正文的地方。
            edgeMasks(outsideOf: frame, in: page)

            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(theme.accent.opacity(0.9), style: StrokeStyle(lineWidth: 1.2, dash: [6, 4]))
                .frame(width: frame.width, height: frame.height)
                .offset(x: frame.minX, y: frame.minY)
                .allowsHitTesting(false)

            ForEach(edges, id: \.self) { edge in
                grabber(for: edge)
                    .position(position(for: edge, in: frame))
            }

            // 控件放在屏幕底部，避开正文起点：放在顶部会压住页眉和第一行。
            VStack(spacing: 8) {
                Spacer()

                // 先给三个整档，再留抓手微调。整档落地的是一次完整重排，
                // 抓手适合「就差一点」，两者混在一起时读者往往会拖到放弃。
                HStack(spacing: 6) {
                    ForEach(FramePreset.allCases, id: \.self) { preset in
                        Button {
                            applyPreset(preset)
                        } label: {
                            Text(preset.title)
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(isActive(preset) ? appTheme.onAccent : theme.text)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 8)
                                .glassCapsule(
                                    tint: isActive(preset) ? appTheme.accentSolid : theme.text.opacity(0.06),
                                    interactive: true
                                )
                        }
                        .buttonStyle(PressableStyle(scale: 0.97))
                    }
                }
                .frame(maxWidth: 250)

                HStack(spacing: 14) {
                    Label("上 \(Int(topMargin))", systemImage: "arrow.up.and.down")
                    Text("左右 \(Int(sideMargin))")
                    Label("下 \(Int(bottomMargin))", systemImage: "arrow.up.and.down")
                }
                .font(.system(size: 10.5, weight: .medium, design: .rounded))
                .foregroundStyle(theme.secondary)
                .monospacedDigit()

                HStack(spacing: 10) {
                    Button {
                        resetFrame()
                    } label: {
                        Image(systemName: "arrow.counterclockwise")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(theme.text)
                            .glassCircle(diameter: 40)
                    }
                    .buttonStyle(PressableStyle())
                    .accessibilityLabel("恢复默认版心")

                    Button {
                        commitAll()
                        onDone()
                    } label: {
                        Text("完成")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(appTheme.onAccent)
                            .frame(maxWidth: 160)
                            .padding(.vertical, 12)
                            .glassCapsule(tint: appTheme.accentSolid.opacity(0.9), interactive: true)
                    }
                    .buttonStyle(PressableStyle(scale: 0.97))
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.bottom, bottomSafeAreaInset + 14)
        }
        .frame(width: page.width, height: page.height, alignment: .topLeading)
        .animation(.easeInOut(duration: 0.18), value: sideDrag == nil)
        .animation(.easeInOut(duration: 0.18), value: topDrag == nil)
        .animation(.easeInOut(duration: 0.18), value: bottomDrag == nil)
    }

    private enum Edge: Hashable {
        case top, bottom, left, right
    }

    private var edges: [Edge] { [.top, .bottom, .left, .right] }

    /// 框外四块遮罩，拼起来正好是「整页减去版心」。用四块矩形而不是
    /// 一个排空路径，是为了让遮罩的边缘不落在版心线上：差半个像素就会
    /// 把虚线擦掉半条。
    private func edgeMasks(outsideOf frame: CGRect, in page: CGSize) -> some View {
        ZStack(alignment: .topLeading) {
            Rectangle()
                .fill(theme.background)
                .frame(width: page.width, height: max(frame.minY, 0))
                .offset(y: 0)

            Rectangle()
                .fill(theme.background)
                .frame(
                    width: page.width,
                    height: max(page.height - frame.maxY, 0)
                )
                .offset(y: frame.maxY)

            Rectangle()
                .fill(theme.background)
                .frame(
                    width: max(frame.minX, 0),
                    height: max(frame.height, 0)
                )
                .offset(x: 0, y: frame.minY)

            Rectangle()
                .fill(theme.background)
                .frame(
                    width: max(page.width - frame.maxX, 0),
                    height: max(frame.height, 0)
                )
                .offset(x: frame.maxX, y: frame.minY)
        }
        .allowsHitTesting(false)
    }

    private func position(for edge: Edge, in frame: CGRect) -> CGPoint {
        switch edge {
        case .top: CGPoint(x: frame.midX, y: frame.minY)
        case .bottom: CGPoint(x: frame.midX, y: frame.maxY)
        case .left: CGPoint(x: frame.minX, y: frame.midY)
        case .right: CGPoint(x: frame.maxX, y: frame.midY)
        }
    }

    @ViewBuilder
    private func grabber(for edge: Edge) -> some View {
        let isVertical = edge == .top || edge == .bottom
        let size = isVertical ? CGSize(width: 72, height: 26) : CGSize(width: 26, height: 72)
        let isDragging = dragState(for: edge) != nil

        // 抓手本身画得很小，可点区域放大到 44pt 以上，手指才不会总是抓空。
        ZStack {
            Capsule()
                .fill(appTheme.accentSolid)
                .frame(
                    width: isVertical ? 34 : 6,
                    height: isVertical ? 6 : 34
                )
                .opacity(isDragging ? 1 : 0.9)

            Image(systemName: isVertical ? "arrow.up.and.down" : "arrow.left.and.right")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(appTheme.onAccent)
                .opacity(isDragging ? 1 : 0)
        }
        .frame(width: size.width, height: size.height)
        .contentShape(Rectangle())
        .gesture(dragGesture(for: edge))
        .accessibilityLabel(accessibilityLabel(for: edge))
    }

    private func dragGesture(for edge: Edge) -> some Gesture {
        DragGesture(minimumDistance: 1)
            .onChanged { value in
                switch edge {
                case .left:
                    let next = clamp(
                        (sideDrag?.start ?? initialSideMargin) + value.translation.width,
                        to: Double(ReaderMetrics.minSide)...Double(ReaderMetrics.maxSide)
                    )
                    sideDrag = (sideDrag?.start ?? initialSideMargin, next)
                case .right:
                    let next = clamp(
                        (sideDrag?.start ?? initialSideMargin) - value.translation.width,
                        to: Double(ReaderMetrics.minSide)...Double(ReaderMetrics.maxSide)
                    )
                    sideDrag = (sideDrag?.start ?? initialSideMargin, next)
                case .top:
                    let next = clamp(
                        (topDrag?.start ?? initialTopMargin) + value.translation.height,
                        to: Double(ReaderMetrics.minTop)...Double(ReaderMetrics.maxTop)
                    )
                    topDrag = (topDrag?.start ?? initialTopMargin, next)
                case .bottom:
                    let next = clamp(
                        (bottomDrag?.start ?? initialBottomMargin) - value.translation.height,
                        to: Double(ReaderMetrics.minBottom)...Double(ReaderMetrics.maxBottom)
                    )
                    bottomDrag = (bottomDrag?.start ?? initialBottomMargin, next)
                }
            }
            .onEnded { _ in
                // 拖的过程中不重排，松手才交给阅读页。
                switch edge {
                case .left, .right:
                    if let sideDrag { commit(side: sideDrag.current) }
                    sideDrag = nil
                case .top:
                    if let topDrag { commit(top: topDrag.current) }
                    topDrag = nil
                case .bottom:
                    if let bottomDrag { commit(bottom: bottomDrag.current) }
                    bottomDrag = nil
                }
            }
    }

    private func dragState(for edge: Edge) -> Double? {
        switch edge {
        case .left, .right: sideDrag?.current
        case .top: topDrag?.current
        case .bottom: bottomDrag?.current
        }
    }

    private func accessibilityLabel(for edge: Edge) -> String {
        switch edge {
        case .top: "上边界"
        case .bottom: "下边界"
        case .left: "左边界"
        case .right: "右边界"
        }
    }

    private func clamp(_ value: Double, to range: ClosedRange<Double>) -> Double {
        min(max(value, range.lowerBound), range.upperBound)
    }

    private func commit(side: Double) {
        onCommit(side, topMargin, bottomMargin)
    }

    private func commit(top: Double) {
        onCommit(sideMargin, top, bottomMargin)
    }

    private func commit(bottom: Double) {
        onCommit(sideMargin, topMargin, bottom)
    }

    private func commitAll() {
        onCommit(sideMargin, topMargin, bottomMargin)
    }

    /// 四个整档：全屏是默认值，正文铺到画布边缘；紧凑贴着工具栏把每页字数
    /// 拉满，宽栏牺牲一些字换行长。左右放宽时同时收紧上下，一行不至于太短。
    private func applyPreset(_ preset: FramePreset) {
        sideDrag = nil
        topDrag = (Double(preset.top), Double(preset.top))
        bottomDrag = (Double(preset.bottom), Double(preset.bottom))
        onCommit(Double(preset.side), Double(preset.top), Double(preset.bottom))
    }

    private func isActive(_ preset: FramePreset) -> Bool {
        abs(sideMargin - Double(preset.side)) < 0.5
            && abs(topMargin - Double(preset.top)) < 0.5
            && abs(bottomMargin - Double(preset.bottom)) < 0.5
    }

    private func resetFrame() {
        sideDrag = (Double(ReaderMetrics.defaultSide), Double(ReaderMetrics.defaultSide))
        topDrag = (Double(ReaderMetrics.defaultTop), Double(ReaderMetrics.defaultTop))
        bottomDrag = (Double(ReaderMetrics.defaultBottom), Double(ReaderMetrics.defaultBottom))
        onCommit(Double(ReaderMetrics.defaultSide), Double(ReaderMetrics.defaultTop), Double(ReaderMetrics.defaultBottom))
    }
}

/// 版心的四个整档。左右是读者抱怨「太空」时最该改的刻度：
/// 全屏档把正文铺到画布边缘；适中与宽栏保留书页留白，
/// 紧凑则让一行排得更短，短章也不至于只剩半页。
enum FramePreset: CaseIterable {
    case compact, balanced, wide, fullScreen

    var title: String {
        switch self {
        case .compact: "紧凑"
        case .balanced: "适中"
        case .wide: "宽栏"
        case .fullScreen: "全屏"
        }
    }

    var side: CGFloat {
        switch self {
        case .compact: 24
        case .balanced: ReaderMetrics.balancedSide
        case .wide: 64
        case .fullScreen: ReaderMetrics.minSide
        }
    }

    var top: CGFloat {
        switch self {
        case .compact: 48
        case .balanced: ReaderMetrics.balancedTop
        case .wide: 112
        case .fullScreen: ReaderMetrics.minTop
        }
    }

    var bottom: CGFloat {
        switch self {
        case .compact: 80
        case .balanced: ReaderMetrics.balancedBottom
        case .wide: 184
        case .fullScreen: ReaderMetrics.minBottom
        }
    }
}

// MARK: - TOC

struct TOCSheet: View {
    @Environment(\.theme) private var theme
    @Environment(\.dismiss) private var dismiss

    let chapters: [Chapter]
    let currentTitle: String
    let onSelect: (String) -> Void

    @State private var query = ""
    @State private var ascending = true

    private var filtered: [Chapter] {
        let result = query.isEmpty
            ? chapters
            : chapters.filter { $0.title.localizedCaseInsensitiveContains(query) }
        return ascending ? result : Array(result.reversed())
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AppBackdrop()

                ScrollView {
                    VStack(spacing: 8) {
                        ForEach(filtered) { chapter in
                            Button {
                                onSelect(chapter.title)
                            } label: {
                                HStack(spacing: 12) {
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(chapter.title)
                                            .font(.system(size: 15, weight: .medium))
                                            .foregroundStyle(theme.text)

                                        Text("\(chapter.paragraphs.count) 段 · \(chapter.paragraphs.reduce(0) { $0 + $1.text.count }) 字")
                                            .font(.system(size: 10.5))
                                            .foregroundStyle(theme.tertiary)
                                    }

                                    Spacer()

                                    if chapter.title == currentTitle {
                                        HStack(spacing: 4) {
                                            Circle()
                                                .fill(theme.accent)
                                                .frame(width: 5, height: 5)
                                            Text("在读")
                                                .font(.system(size: 10, weight: .semibold))
                                                .foregroundStyle(theme.accent)
                                        }
                                    } else {
                                        Image(systemName: "chevron.right")
                                            .font(.system(size: 11, weight: .bold))
                                            .foregroundStyle(theme.tertiary.opacity(0.5))
                                    }
                                }
                                .padding(.horizontal, 14)
                                .padding(.vertical, 12)
                                .glassSurface(
                                    cornerRadius: 18,
                                    tint: chapter.title == currentTitle ? theme.accent.opacity(0.1) : nil
                                )
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(PressableStyle(scale: 0.985))
                        }
                    }
                    .padding(.horizontal, 18)
                    .padding(.bottom, 30)
                }
                .scrollIndicators(.hidden)
            }
            .navigationTitle("目录")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .automatic), prompt: "搜索章节")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            ascending.toggle()
                        }
                    } label: {
                        Label(ascending ? "倒序" : "正序", systemImage: ascending ? "arrow.up" : "arrow.down")
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") { dismiss() }
                        .fontWeight(.semibold)
                }
            }
        }
    }
}

// MARK: - Reader Settings

struct ReaderSettingsSheet: View {
    @Environment(\.theme) private var appTheme
    @Bindable var settings: ReaderSettings
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    /// 退场后由阅读页接管，进入拖动抓手的版心微调。
    var onAdjustFrame: (() -> Void)? = nil
    @State private var eyePreview = false

    var body: some View {
        NavigationStack {
            ZStack {
                AppBackdrop()

                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        preview

                        frameSection
                        commentsSection
                        fontSizeSection
                        lineSpacingSection
                        themeSection
                        pageModeSection
                        typographySection
                        eyeCareSection

                        Toggle(isOn: $settings.purifyText) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("正文净化")
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundStyle(appTheme.text)
                                Text("移除「本章完」、作者说等干扰行")
                                    .font(.system(size: 10.5))
                                    .foregroundStyle(appTheme.tertiary)
                            }
                        }
                        .tint(appTheme.accent)
                        .padding(.horizontal, 15)
                        .padding(.vertical, 12)
                        .glassSurface(cornerRadius: 18)
                    }
                    .padding(18)
                }
                .scrollIndicators(.hidden)
            }
            .navigationTitle("阅读设置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") { dismiss() }
                        .fontWeight(.semibold)
                }
            }
            .onDisappear { store.saveSnapshot() }
        }
    }

    private var preview: some View {
        Text((settings.indent ? "　　" : "") + "夜色漫上船头，灯影落在书页上。远处有人收缆，水声一下一下，像替谁数着日子。")
            .font(.system(
                size: settings.fontSize,
                weight: settings.fontWeight.weight,
                design: settings.fontDesign.design
            ))
            .lineSpacing(settings.fontSize * settings.lineSpacing)
            .foregroundStyle(appTheme.text)
            .padding(.vertical, 16)
            .padding(.horizontal, min(settings.sideMargin, 28))
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(appTheme.reader.background, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(appTheme.text.opacity(0.1), lineWidth: 0.8)
            }
            .overlay(alignment: .topTrailing) {
                Text(settings.theme.rawValue)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(appTheme.secondary)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .glassCapsule(tint: appTheme.reader.isDark ? .white.opacity(0.08) : .white.opacity(0.4))
                    .padding(9)
            }
    }

    private var fontSizeSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeading(text: "字号", trailing: "\(Int(settings.fontSize)) pt")

            HStack(spacing: 14) {
                Text("A")
                    .font(.system(size: 12, design: .serif))
                    .foregroundStyle(appTheme.tertiary)

                Slider(value: $settings.fontSize, in: 14...28, step: 1)
                    .tint(appTheme.accent)

                Text("A")
                    .font(.system(size: 22, design: .serif))
                    .foregroundStyle(appTheme.text)
            }
            .padding(.horizontal, 15)
            .padding(.vertical, 12)
            .glassSurface(cornerRadius: 18)
        }
    }

    private var lineSpacingSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeading(text: "行距", trailing: String(format: "%.1f×", 1 + settings.lineSpacing))

            Slider(value: $settings.lineSpacing, in: 0.3...1.6, step: 0.1)
                .tint(appTheme.accent)
                .padding(.horizontal, 15)
                .padding(.vertical, 14)
                .glassSurface(cornerRadius: 18)
        }
    }

    private var themeSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeading(text: "主题")

            LazyVGrid(
                columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())],
                spacing: 10
            ) {
                ForEach(ReaderTheme.allCases) { theme in
                    let selected = settings.theme == theme
                    Button {
                        withAnimation(.spring(response: 0.34, dampingFraction: 0.86)) {
                            settings.theme = theme
                        }
                    } label: {
                        VStack(spacing: 7) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 13, style: .continuous)
                                    .fill(
                                        LinearGradient(
                                            colors: [theme.background, theme.backgroundDeep],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                    )

                                Text("文")
                                    .font(.system(size: 20, design: .serif))
                                    .foregroundStyle(theme.text)

                                if selected {
                                    VStack {
                                        HStack {
                                            Spacer()
                                            Image(systemName: "checkmark.circle.fill")
                                                .font(.system(size: 13))
                                                .foregroundStyle(theme.accent)
                                        }
                                        Spacer()
                                    }
                                    .padding(6)
                                }
                            }
                            .frame(height: 62)
                            .overlay {
                                RoundedRectangle(cornerRadius: 13, style: .continuous)
                                    .strokeBorder(
                                        selected ? theme.accent : appTheme.hairline,
                                        lineWidth: selected ? 1.8 : 0.8
                                    )
                            }

                            Text(theme.rawValue)
                                .font(.system(size: 10.5, weight: selected ? .semibold : .regular))
                                .foregroundStyle(selected ? appTheme.text : appTheme.tertiary)
                        }
                    }
                    .buttonStyle(PressableStyle())
                }
            }
            .padding(12)
            .glassSurface(cornerRadius: 20)
        }
    }

    private var pageModeSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeading(text: "翻页方式")

            HStack(spacing: 9) {
                ForEach(PageMode.allCases) { mode in
                    optionCard(
                        title: mode.rawValue,
                        symbol: mode.symbol,
                        selected: settings.pageMode == mode
                    ) {
                        withAnimation(.spring(response: 0.34, dampingFraction: 0.86)) {
                            settings.pageMode = mode
                        }
                    }
                }
            }

            HStack(spacing: 9) {
                ForEach(PageTurnEffect.allCases) { effect in
                    optionCard(
                        title: effect.rawValue,
                        symbol: effect.symbol,
                        selected: settings.pageTurnEffect == effect
                    ) {
                        withAnimation(.spring(response: 0.34, dampingFraction: 0.86)) {
                            settings.pageTurnEffect = effect
                        }
                    }
                }
            }

            GlassSegmented(
                items: ReadingDirection.allCases,
                title: { $0.rawValue },
                selection: $settings.direction
            )
        }
    }

    private var typographySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeading(text: "排版")

            VStack(alignment: .leading, spacing: 10) {
                Text("字体")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(appTheme.tertiary)

                GlassSegmented(
                    items: ReaderFontDesign.allCases,
                    title: { $0.rawValue },
                    selection: $settings.fontDesign
                )

                GlassSegmented(
                    items: ReaderWeight.allCases,
                    title: { $0.rawValue },
                    selection: $settings.fontWeight
                )

                Toggle("首行缩进", isOn: $settings.indent)
                    .font(.system(size: 13))
                    .tint(appTheme.accent)

                Toggle("显示页眉页脚", isOn: $settings.showHeaderFooter)
                    .font(.system(size: 13))
                    .tint(appTheme.accent)

                Toggle("音量键翻页", isOn: $settings.volumeKeyTurn)
                    .font(.system(size: 13))
                    .tint(appTheme.accent)

                Text("真机连接后生效；模拟器可用硬件音量键测试。")
                    .font(.system(size: 9.5))
                    .foregroundStyle(appTheme.tertiary)
            }
            .padding(14)
            .glassSurface(cornerRadius: 20)
        }
    }

    private var eyeCareSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeading(text: "护眼", trailing: store.eyeCare.enabled ? "已开启" : "关闭")

            VStack(spacing: 12) {
                Toggle(isOn: Binding(
                    get: { store.eyeCare.enabled },
                    set: { store.eyeCare.enabled = $0; store.saveSnapshot() }
                )) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("暖色滤光")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(appTheme.text)
                        Text("降低蓝光刺激，阅读页与书架同步生效")
                            .font(.system(size: 10.5))
                            .foregroundStyle(appTheme.tertiary)
                    }
                }
                .tint(appTheme.jade)

                sliderRow(
                    title: "暖度",
                    value: Binding(
                        get: { store.eyeCare.warmth },
                        set: { store.eyeCare.warmth = $0; store.saveSnapshot() }
                    ),
                    range: 0.05...0.75
                )

                sliderRow(
                    title: "亮度",
                    value: Binding(
                        get: { store.eyeCare.dim },
                        set: { store.eyeCare.dim = $0; store.saveSnapshot() }
                    ),
                    range: 0...0.35
                )

                Toggle("每 \(store.eyeCare.restMinutes) 分钟提醒休息", isOn: Binding(
                    get: { store.eyeCare.restReminder },
                    set: { store.eyeCare.restReminder = $0; store.saveSnapshot() }
                ))
                .font(.system(size: 13))
                .tint(appTheme.jade)

                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        eyePreview.toggle()
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "eye")
                        Text("预览休息提醒")
                    }
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(appTheme.jade)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .glassCapsule(tint: appTheme.jade.opacity(0.1), interactive: true)
                }
                .buttonStyle(PressableStyle())

                if eyePreview {
                    Text("已读 20 分钟。看看 6 米外，让眼睛休息 20 秒。")
                        .font(.system(size: 11.5))
                        .foregroundStyle(appTheme.secondary)
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .glassSurface(cornerRadius: 14, tint: appTheme.jade.opacity(0.08))
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            .padding(14)
            .glassSurface(cornerRadius: 20)
        }
    }

    /// 段评显示策略。原来正文工具栏的「段评」按钮已迁到这里，
    /// 开关依旧绑定 `hideSourceComments`，默认值和已有配置不变。
    private var commentsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeading(
                text: "段评",
                trailing: settings.hideSourceComments ? "已屏蔽" : "已显示"
            )

            VStack(spacing: 12) {
                Toggle(isOn: $settings.hideSourceComments) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("屏蔽书源段评")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(appTheme.text)
                        Text("开启后隐藏段评胶囊与段落菜单里的段评入口，只保留干净正文")
                            .font(.system(size: 10.5))
                            .foregroundStyle(appTheme.tertiary)
                    }
                }
                .tint(appTheme.accent)

                Text("已有段评数据与显示配置都会保留，随时可以恢复显示。")
                    .font(.system(size: 10))
                    .foregroundStyle(appTheme.tertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(14)
            .glassSurface(cornerRadius: 20)
        }
    }

    /// 版心的完整形状：上下左右四个刻度，加上按真实比例画出来的预览。
    /// 预览盒子的比例就是屏幕，版心框的位置对应正文真正落笔的地方。
    private var frameSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeading(
                text: "版心",
                trailing: "\(Int(settings.topMargin)) · \(Int(settings.sideMargin)) · \(Int(settings.bottomMargin))"
            )

            VStack(spacing: 12) {
                Text("预设与滑块共用同一组留白数据，调整后正文立即重新排版。")
                    .font(.system(size: 10.5))
                    .foregroundStyle(appTheme.tertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                framePreview

                HStack(spacing: 6) {
                    ForEach(FramePreset.allCases, id: \.self) { preset in
                        Button {
                            settings.sideMargin = Double(preset.side)
                            settings.topMargin = Double(preset.top)
                            settings.bottomMargin = Double(preset.bottom)
                        } label: {
                            Text(preset.title)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(isFramePresetActive(preset) ? appTheme.onAccent : appTheme.text)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 8)
                                .glassCapsule(
                                    tint: isFramePresetActive(preset) ? appTheme.accentSolid : appTheme.text.opacity(0.06),
                                    interactive: true
                                )
                        }
                        .buttonStyle(PressableStyle(scale: 0.97))
                    }
                }

                frameSlider("上边界", value: $settings.topMargin, range: ReaderMetrics.minTop...ReaderMetrics.maxTop)
                frameSlider("左右", value: $settings.sideMargin, range: ReaderMetrics.minSide...ReaderMetrics.maxSide)
                frameSlider("下边界", value: $settings.bottomMargin, range: ReaderMetrics.minBottom...ReaderMetrics.maxBottom)

                if let onAdjustFrame {
                    Button {
                        onAdjustFrame()
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "hand.draw")
                            Text("在正文上直接拖边界")
                        }
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(appTheme.accent)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .glassCapsule(tint: appTheme.accent.opacity(0.1), interactive: true)
                    }
                    .buttonStyle(PressableStyle())
                }
            }
            .padding(14)
            .glassSurface(cornerRadius: 20)
        }
    }

    private var framePreview: some View {
        GeometryReader { geometry in
            let page = geometry.size
            let scaleX = page.width / max(previewViewport.width, 1)
            let scaleY = page.height / max(previewViewport.height, 1)
            let frame = CGRect(
                x: settings.sideMargin * scaleX,
                y: settings.topMargin * scaleY,
                width: max(page.width - settings.sideMargin * 2 * scaleX, 4),
                height: max(page.height - (settings.topMargin + settings.bottomMargin) * scaleY, 4)
            )

            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(appTheme.reader.background)

                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(appTheme.text.opacity(0.055))
                    .overlay {
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .strokeBorder(appTheme.accent.opacity(0.65), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                    }
                    .frame(width: frame.width, height: frame.height)
                    .offset(x: frame.minX, y: frame.minY)
            }
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(appTheme.text.opacity(0.1), lineWidth: 0.8)
            }
        }
        .frame(height: 150)
    }

    /// 预览按 iPhone 竖屏比例缩放，与阅读页上看到的画面同一套几何。
    private var previewViewport: CGSize { CGSize(width: 390, height: 844) }

    private func isFramePresetActive(_ preset: FramePreset) -> Bool {
        abs(settings.sideMargin - Double(preset.side)) < 0.5
            && abs(settings.topMargin - Double(preset.top)) < 0.5
            && abs(settings.bottomMargin - Double(preset.bottom)) < 0.5
    }

    private func frameSlider(_ title: String, value: Binding<Double>, range: ClosedRange<Double>) -> some View {
        HStack(spacing: 10) {
            Text(title)
                .font(.system(size: 12))
                .foregroundStyle(appTheme.secondary)
                .frame(width: 52, alignment: .leading)
            Slider(value: value, in: range, step: 1)
                .tint(appTheme.accent)
            Text("\(Int(value.wrappedValue))")
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(appTheme.tertiary)
                .monospacedDigit()
                .frame(width: 26, alignment: .trailing)
        }
    }

    private func optionCard(
        title: String,
        symbol: String,
        selected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: symbol)
                    .font(.system(size: 12, weight: .medium))
                Text(title)
                    .font(.system(size: 12, weight: selected ? .semibold : .medium))
            }
            .foregroundStyle(selected ? appTheme.text : appTheme.secondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 11)
            .glassSurface(
                cornerRadius: 15,
                tint: selected ? appTheme.accent.opacity(0.16) : nil,
                interactive: true
            )
        }
        .buttonStyle(PressableStyle())
    }

    private func sliderRow(title: String, value: Binding<Double>, range: ClosedRange<Double>) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 12))
                .foregroundStyle(appTheme.secondary)
                .frame(width: 42, alignment: .leading)
            Slider(value: value, in: range)
                .tint(appTheme.jade)
            Text("\(Int(value.wrappedValue * 100))%")
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundStyle(appTheme.tertiary)
                .monospacedDigit()
                .frame(width: 32)
        }
    }
}

// MARK: - Segment Comments

struct SegmentCommentsSheet: View {
    @Environment(\.theme) private var theme
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    let book: Book
    /// 段落所属章节；在线书要靠它拿章节地址去书源取评论。
    let chapter: Chapter?
    let paragraph: Paragraph

    @State private var comments: [SegmentComment] = []
    @State private var hiddenCount = 0
    /// 在线书的评论是异步拉的，三种状态要分开显示。
    @State private var isLoading = false
    @State private var remoteError = ""
    /// 这次显示的是书源真实评论，还是书里自带的本地演示评论。
    @State private var isRemote = false
    /// 书源返回的是整章评论（Legado 的 ruleReview 没有段落粒度）。
    @State private var isChapterWide = false

    private static let bannedWords = ["加群", "微信", "广告", "代写", "私聊"]

    var body: some View {
        NavigationStack {
            ZStack {
                AppBackdrop()

                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        quoteBlock

                        HStack {
                            // Legado 的 ruleReview 是「按章」返回评论的，没有段落粒度。
                            // 拿到的是整章的评论就必须写「本章」，不能声称是「本段」。
                            SectionHeading(text: isChapterWide ? "本章 \(comments.count) 条段评" : "本段 \(comments.count) 条段评")
                            Spacer()
                            Text(isRemote ? (isChapterWide ? "只读 · 来自书源 · 整章" : "只读 · 来自书源") : "演示评论")
                                .font(.system(size: 9.5, weight: .medium))
                                .foregroundStyle(isRemote ? theme.jade : theme.tertiary)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 3)
                                .glassCapsule(tint: (isRemote ? theme.jade : theme.faint).opacity(0.12))
                        }

                        if isChapterWide {
                            Text("书源的评论规则只提供章级粒度，下面是这一章的评论，不是单独针对这一段。")
                                .font(.system(size: 10))
                                .foregroundStyle(theme.tertiary)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        if hiddenCount > 0 {
                            Text("已按本地词表隐藏 \(hiddenCount) 条内容")
                                .font(.system(size: 10))
                                .foregroundStyle(theme.tertiary)
                        }

                        if isLoading {
                            HStack(spacing: 9) {
                                ProgressView().themedProgress()
                                Text("正在向书源请求段评…")
                                    .font(.system(size: 11.5))
                                    .foregroundStyle(theme.tertiary)
                            }
                            .padding(.top, 24)
                        } else if !remoteError.isEmpty && comments.isEmpty {
                            // 书源有规则但抓取失败：显示原因，不假装「没有评论」。
                            VStack(alignment: .leading, spacing: 7) {
                                HStack(spacing: 7) {
                                    Image(systemName: "exclamationmark.triangle.fill")
                                        .font(.system(size: 11))
                                        .foregroundStyle(theme.accent)
                                    Text("段评获取失败")
                                        .font(.system(size: 11.5, weight: .semibold))
                                        .foregroundStyle(theme.text)
                                }
                                Text(remoteError)
                                    .font(.system(size: 10.5))
                                    .foregroundStyle(theme.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                                Button {
                                    Task { await loadRemote() }
                                } label: {
                                    Text("重试")
                                        .font(.system(size: 11, weight: .semibold))
                                        .foregroundStyle(theme.jade)
                                }
                                .buttonStyle(PressableStyle())
                            }
                            .padding(13)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .glassSurface(cornerRadius: 18, tint: theme.accent.opacity(0.06))
                        } else if comments.isEmpty {
                            Text(remoteError.isEmpty ? "这一段还没有段评。" : remoteError)
                                .font(.system(size: 11))
                                .foregroundStyle(theme.tertiary)
                                .padding(.top, 18)
                        }

                        ForEach(Array(comments.enumerated()), id: \.element.id) { index, comment in
                            commentCard(comment, index: index)
                        }

                        Button {
                            store.settings.hideSourceComments = true
                            store.saveSnapshot()
                            dismiss()
                        } label: {
                            Label("屏蔽此源段评", systemImage: "eye.slash")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(theme.accent)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .glassSurface(cornerRadius: 18, tint: theme.accent.opacity(0.06), interactive: true)
                        }
                        .buttonStyle(PressableStyle())
                    }
                    .padding(.horizontal, 18)
                    .padding(.top, 8)
                    .padding(.bottom, 26)
                }
                .scrollIndicators(.hidden)
            }
            .navigationTitle("段评")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") { dismiss() }
                        .fontWeight(.semibold)
                }
            }
            .task { await load() }
        }
    }

    /// 本地书用书里自带的演示评论；在线书向书源真实请求。
    private func load() async {
        guard store.settings.hideSourceComments == false else { return }
        if book.isNetworkBook {
            await loadRemote()
            return
        }
        applyLocalComments()
    }

    private func applyLocalComments() {
        let visible = paragraph.comments.filter { comment in
            !Self.bannedWords.contains { comment.text.localizedCaseInsensitiveContains($0) }
        }
        hiddenCount = paragraph.comments.count - visible.count
        comments = visible
        isRemote = false
    }

    /// 书源评论是按「章」返回的：一次请求拿整章的评论，
    /// 再按段落正文去匹配。Legado 的 ruleReview 没有「按段落」这个粒度。
    private func loadRemote() async {
        guard let chapter, let chapterURL = chapter.networkURL else {
            remoteError = "这一章没有可用的书源地址"
            return
        }
        guard let appSource = store.sources.first(where: { $0.id == book.sourceID }),
              let engineSource = LegadoBridge.engineSource(from: appSource) else {
            remoteError = "书源已被移除或规则无法解析"
            return
        }
        guard let bookURL = book.networkBookURL else {
            remoteError = "这本书缺少书源地址"
            return
        }

        isLoading = true
        remoteError = ""

        var engineChapter = BookChapter(
            url: chapterURL,
            title: chapter.title,
            bookUrl: bookURL,
            index: 0
        )
        engineChapter.baseUrl = bookURL
        let engineBook = LegadoCore.Book(
            bookUrl: bookURL,
            name: book.title,
            author: book.author,
            origin: engineSource.bookSourceUrl
        )

        let result = await store.engine.chapterComments(
            engineBook: engineBook, chapter: engineChapter, source: engineSource
        )
        isLoading = false

        if let error = result.error {
            // 抓取失败就把原因显示出来，不要静默退回演示评论 ——
            // 那样用户会以为看到的是书源评论，实际上一条都没拿到。
            remoteError = error
            comments = []
            hiddenCount = 0
            isRemote = false
            return
        }

        // 书源的评论是整章的。能按段落正文匹配就过滤，匹配不上就全显示，
        // 但标清「整章」而不是假装是这一段（见 isChapterWide）。
        let matched = result.comments.filter { comment in
            !Self.bannedWords.contains { comment.content.localizedCaseInsensitiveContains($0) }
        }
        hiddenCount = result.comments.count - matched.count
        // 只有整章里恰好能对上本段正文的评论，才算「本段」。
        isChapterWide = !matched.isEmpty && !matched.contains { comment in
            comment.content.localizedCaseInsensitiveContains(paragraph.text)
        }
        comments = matched.enumerated().map { index, comment in
            SegmentComment(
                id: "src-\(index)-\(Self.stableCommentID(comment.id))",
                author: comment.author ?? "读者",
                text: comment.content,
                likes: 0,
                liked: false,
                minutesAgo: 0
            )
        }
        isRemote = true
    }

    /// 评论 ID 只在这次会话里用于列表去重，用 FNV-1a 而不是 hashValue：
    /// 同一批评论重复打开时行 ID 应该稳定，否则列表每次重建。
    private static func stableCommentID(_ text: String) -> UInt64 {
        var hash: UInt64 = 0xCBF2_9CE4_8422_2325
        for byte in text.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01B3
        }
        return hash
    }

    private var quoteBlock: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 6) {
                Image(systemName: "quote.opening")
                    .font(.system(size: 10, weight: .semibold))
                Text("原文")
                    .font(.system(size: 9.5, weight: .semibold))
                    .tracking(1.2)
            }
            .foregroundStyle(theme.accent)

            Text(paragraph.text)
                .font(.system(size: 14, design: .serif))
                .lineSpacing(5)
                .foregroundStyle(theme.secondary)
        }
        .padding(15)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassSurface(cornerRadius: 20, tint: theme.accent.opacity(0.07))
    }

    private func commentCard(_ comment: SegmentComment, index: Int) -> some View {
        let idx = abs(index) % theme.covers.count
        let colors = (theme.covers[idx], theme.coversDeep[idx])
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                // 头像色块
                Text(String(comment.author.prefix(1)))
                    .font(.system(size: 12, weight: .semibold, design: .serif))
                    .foregroundStyle(.white)
                    .frame(width: 26, height: 26)
                    .background(
                        LinearGradient(
                            colors: [colors.0, colors.1],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        in: Circle()
                    )

                VStack(alignment: .leading, spacing: 1) {
                    Text(comment.author)
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(theme.text)

                    Text(relativeTime(comment.minutesAgo))
                        .font(.system(size: 9.5))
                        .foregroundStyle(theme.tertiary)
                }

                Spacer()

                if comment.likes > 0 {
                    HStack(spacing: 3.5) {
                        Image(systemName: "heart")
                            .font(.system(size: 10, weight: .semibold))
                        Text("\(comment.likes)")
                            .font(.system(size: 10, weight: .medium))
                            .monospacedDigit()
                    }
                    .foregroundStyle(theme.tertiary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .glassCapsule(tint: theme.glassTint)
                }
            }

            Text(comment.text)
                .font(.system(size: 14, design: .serif))
                .lineSpacing(4)
                .foregroundStyle(theme.text)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(14)
        .glassSurface(cornerRadius: 20)
    }

    private func relativeTime(_ minutes: Int) -> String {
        if minutes < 1 { return "刚刚" }
        if minutes < 60 { return "\(minutes) 分钟前" }
        if minutes < 1_440 { return "\(minutes / 60) 小时前" }
        return "\(minutes / 1_440) 天前"
    }
}

// MARK: - 正文导出

/// 导出结果。`id` 每次导出都是新的，保证连导两次也能重弹分享面板。
struct ExportedTextFile: Identifiable {
    let id = UUID()
    let url: URL
    let chapterCount: Int
    let emptyChapters: Int
}

struct ExportSheet: View {
    @Environment(\.theme) private var theme
    let file: ExportedTextFile
    let bookTitle: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "doc.text")
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(theme.accent)

            Text("已生成《\(bookTitle)》正文")
                .font(.system(size: 16, weight: .semibold, design: .serif))
                .foregroundStyle(theme.text)

            Text(summary)
                .font(.system(size: 12))
                .foregroundStyle(theme.secondary)
                .multilineTextAlignment(.center)

            ShareLink(item: file.url, preview: SharePreview(bookTitle + ".txt")) {
                Label("分享 TXT 文件", systemImage: "square.and.arrow.up")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(theme.onAccent)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(theme.accentSolid, in: Capsule())
            }
            .buttonStyle(PressableStyle())
            .padding(.horizontal, 24)

            Button("完成") { dismiss() }
                .font(.system(size: 13))
                .foregroundStyle(theme.secondary)
                .buttonStyle(PressableStyle())
        }
        .padding(.top, 26)
        .padding(.bottom, 14)
    }

    private var summary: String {
        if file.emptyChapters == 0 {
            return "共 \(file.chapterCount) 章，正文已全部导出。文件只留在临时目录。"
        }
        return "共 \(file.chapterCount) 章，其中 \(file.emptyChapters) 章正文尚未加载，已用占位文字标注。"
    }
}

// MARK: - Volume keys

struct VolumeKeyReader: UIViewRepresentable {
    let onVolumeUp: () -> Void
    let onVolumeDown: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onVolumeUp: onVolumeUp, onVolumeDown: onVolumeDown)
    }

    func makeUIView(context: Context) -> UIView {
        context.coordinator.start()
        return UIView(frame: .zero)
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.onVolumeUp = onVolumeUp
        context.coordinator.onVolumeDown = onVolumeDown
    }

    static func dismantleUIView(_ uiView: UIView, coordinator: Coordinator) {
        coordinator.stop()
    }

    final class Coordinator {
        var onVolumeUp: () -> Void
        var onVolumeDown: () -> Void
        private var observation: NSKeyValueObservation?
        private var lastVolume: Float = 0

        init(onVolumeUp: @escaping () -> Void, onVolumeDown: @escaping () -> Void) {
            self.onVolumeUp = onVolumeUp
            self.onVolumeDown = onVolumeDown
        }

        func start() {
            let session = AVAudioSession.sharedInstance()
            try? session.setActive(true)
            lastVolume = session.outputVolume
            observation = session.observe(\.outputVolume, options: [.new]) { [weak self] _, change in
                guard let self, let value = change.newValue else { return }
                let delta = value - self.lastVolume
                self.lastVolume = value
                guard abs(delta) > 0.001 else { return }
                DispatchQueue.main.async {
                    if delta > 0 {
                        self.onVolumeUp()
                    } else {
                        self.onVolumeDown()
                    }
                }
            }
        }

        func stop() {
            observation?.invalidate()
            observation = nil
        }
    }
}
