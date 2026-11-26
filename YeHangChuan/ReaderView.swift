import SwiftUI
import AVFoundation
import MediaPlayer
import LegadoCore

struct ReaderView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    let book: Book
    var initialChapterTitle: String? = nil

    @State private var pages: [ReaderPage] = []
    @State private var pageIndex = 0
    @State private var showChrome = true
    @State private var showTOC = false
    @State private var showSettings = false
    @State private var showBookmarks = false
    @State private var showListen = false
    @State private var showSourceSwitch = false
    @State private var commentParagraph: Paragraph?
    @State private var flash: String?
    /// 在线书正在拉目录或正文。
    @State private var isLoadingNetwork = false
    /// 在线书加载失败的原因，显示在正文区而不是静默空白。
    @State private var networkError: String?
    @State private var viewport: CGSize = CGSize(width: 390, height: 844)
    /// 滚动模式下当前可见段落的 ID，与 ScrollReaderView 的 scrollPosition 双向绑定。
    @State private var scrollParagraphID: String?
    /// 滚动模式下据此把段落位置换算成与分页模式一致的百分比。
    @State private var scrollProgress: Double = 0

    private var settings: ReaderSettings { store.settings }
    private var chapters: [Chapter] { store.chapters(for: book) }
    private var currentPage: ReaderPage? { pages.indices.contains(pageIndex) ? pages[pageIndex] : nil }

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
    private var anchorParagraphID: String? { currentPage?.paragraphs.first?.id }

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
        return anchorOffset
    }

    /// 当前页首段在所属章节内的 UTF-16 偏移，仅用于展示与兼容旧数据。
    private var anchorOffset: Int {
        guard let page = currentPage,
              let chapter = chapters.first(where: { $0.title == page.chapterTitle }),
              let first = page.paragraphs.first,
              let index = chapter.paragraphs.firstIndex(where: { $0.id == first.id }) else { return 0 }
        return chapter.paragraphs.prefix(index).reduce(0) { $0 + $1.text.utf16.count }
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
        return pages.count <= 1 ? 0 : Double(pageIndex) / Double(pages.count - 1)
    }

    private var chapterText: String {
        if isScrollMode {
            let title = scrollAnchor.chapterTitle ?? ""
            let paragraphs = chapters.first { $0.title == title }?.paragraphs ?? []
            return paragraphs.map(\.text).joined(separator: "\n")
        }
        let title = currentPage?.chapterTitle ?? ""
        let paragraphs = chapters.first { $0.title == title }?.paragraphs ?? currentPage?.paragraphs ?? []
        return paragraphs.map(\.text).joined(separator: "\n")
    }

    private var chromeColor: Color {
        settings.theme.isDark ? .white : Palette.text
    }

    var body: some View {
        ZStack {
            readerBackground

            readingContent

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
                    .foregroundStyle(settings.theme.text)
                    .padding(.horizontal, 15)
                    .padding(.vertical, 9)
                    .glassCapsule(tint: settings.theme.isDark ? .white.opacity(0.08) : .white.opacity(0.5))
                    .transition(.scale(scale: 0.9).combined(with: .opacity))
            }

            // 边缘翻页热区
            if settings.pageMode == .slide && settings.pageTurnEffect == .slide && showChrome == false {
                HStack(spacing: 0) {
                    tapZone(.backward)
                    tapZone(.forward)
                }
            }

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

            EyeCareLayer(settings: store.eyeCare)
        }
        .onGeometryChange(for: CGSize.self) { $0.size } action: { newSize in
            guard newSize.width > 1, newSize.height > 1 else { return }
            guard abs(newSize.width - viewport.width) > 1 || abs(newSize.height - viewport.height) > 1 else { return }
            viewport = newSize
            guard !pages.isEmpty else { return }
            rebuild(restore: false)
        }
        .preferredColorScheme(settings.theme.isDark ? .dark : .light)
        .statusBarHidden(!showChrome)
        .persistentSystemOverlays(.hidden)
        .onAppear(perform: bootstrap)
        .onChange(of: settings.fontSize) { _, _ in rebuild(restore: false) }
        .onChange(of: settings.lineSpacing) { _, _ in rebuild(restore: false) }
        .onChange(of: settings.sideMargin) { _, _ in rebuild(restore: false) }
        .onChange(of: settings.purifyText) { _, _ in rebuild(restore: false) }
        .onChange(of: settings.pageMode) { _, _ in rebuild(restore: false) }
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
                    } else if let index = pages.firstIndex(where: { $0.chapterTitle == title }) {
                        pageIndex = index
                    } else if let index = chapters.firstIndex(where: { $0.title == title }) {
                        // 该章还没正文，分页里根本不存在，按章节序号估算落点。
                        pageIndex = min(index, max(pages.count - 1, 0))
                    }
                    await ensureChapterContent(title: title)
                }
            }
            .presentationDetents([.medium, .large])
            .presentationCornerRadius(38)
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showSettings) {
            ReaderSettingsSheet(settings: settings)
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
                text: chapterText
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
        .task {
            guard store.eyeCare.enabled, store.eyeCare.restReminder else { return }
            try? await Task.sleep(for: .seconds(store.eyeCare.restMinutes * 60))
            guard !Task.isCancelled else { return }
            showFlash("已读 \(store.eyeCare.restMinutes) 分钟，看看 6 米外 20 秒")
        }
    }

    // MARK: Background

    private var readerBackground: some View {
        ZStack {
            LinearGradient(
                colors: [settings.theme.background, settings.theme.backgroundDeep],
                startPoint: .top,
                endPoint: .bottom
            )

            if settings.theme == .voyage {
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

    @ViewBuilder
    private var readingContent: some View {
        if isLoadingNetwork && pages.isEmpty {
            VStack(spacing: 10) {
                ProgressView()
                Text("正在加载在线章节…")
                    .font(.system(size: 12))
                    .foregroundStyle(settings.theme.secondary)
            }
        } else if let networkError, pages.isEmpty {
            VStack(spacing: 10) {
                Image(systemName: "wifi.exclamationmark")
                    .font(.system(size: 24, weight: .light))
                    .foregroundStyle(settings.theme.secondary)
                Text(networkError)
                    .font(.system(size: 12))
                    .foregroundStyle(settings.theme.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)

                Button {
                    Task { @MainActor in await ensureCurrentChapterContent() }
                } label: {
                    Text("重试")
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(Palette.onAccent)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 9)
                        .background(Palette.accentSolid, in: Capsule())
                }
                .buttonStyle(PressableStyle(scale: 0.97))
            }
        } else if pages.isEmpty {
            ProgressView()
        } else if settings.pageMode == .slide {
            if settings.pageTurnEffect == .slide {
                TabView(selection: $pageIndex) {
                    ForEach(Array(pages.enumerated()), id: \.element.id) { index, page in
                        ReaderPageView(
                            page: page,
                            pageIndex: index,
                            total: pages.count,
                            bookTitle: book.title,
                            settings: settings,
                            onComment: { commentParagraph = $0 },
                            onExcerpt: { paragraph in excerpt(paragraph) },
                            onTap: toggleChrome
                        )
                        .tag(index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .environment(\.layoutDirection, settings.direction.layoutDirection)
            } else {
                PageFlipReader(
                    pages: pages,
                    pageIndex: $pageIndex,
                    bookTitle: book.title,
                    settings: settings,
                    onComment: { commentParagraph = $0 },
                    onExcerpt: { paragraph in excerpt(paragraph) },
                    onTap: toggleChrome
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
    }

    private enum TapZone { case backward, forward }

    private func tapZone(_ zone: TapZone) -> some View {
        Color.clear
            .contentShape(Rectangle())
            .onTapGesture {
                withAnimation(.spring(response: 0.32, dampingFraction: 0.85)) {
                    let movingForward = settings.direction == .ltr ? zone == .forward : zone == .backward
                    if !movingForward {
                        pageIndex = max(pageIndex - 1, 0)
                    } else {
                        pageIndex = min(pageIndex + 1, pages.count - 1)
                    }
                }
            }
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
                        .foregroundStyle(settings.theme.secondary)
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
                        .foregroundStyle(isBookmarked ? Palette.accent : chromeColor)
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
                            let count = await store.backend.download(book: book, count: 3)
                            // 演示工程没有真实章节可下载，这里只更新估算的缓存量，
                            // 文案里如实标出「演示」，别让读者以为真的离线可用。
                            showFlash("已记录 \(count) 章缓存（演示数据）")
                        }
                    } label: {
                        Label("缓存后续章节", systemImage: "arrow.down.circle")
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
                    Text(settings.pageMode == .scroll ? "滚动" : "\(pageIndex + 1) / \(pages.count)")
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .foregroundStyle(settings.theme.secondary)
                        .monospacedDigit()

                    ProgressBar(
                        value: progress,
                        tint: settings.theme.accent,
                        track: settings.theme.text.opacity(0.16),
                        height: 2.5
                    )

                    Text("\(Int(progress * 100))%")
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .foregroundStyle(settings.theme.secondary)
                        .monospacedDigit()
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 13)
                .glassCapsule(tint: settings.theme.isDark ? .white.opacity(0.06) : .white.opacity(0.45))

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
                    toolButton(
                        "段评",
                        symbol: settings.hideSourceComments ? "text.bubble" : "text.bubble.fill"
                    ) {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                            settings.hideSourceComments.toggle()
                        }
                        showFlash(settings.hideSourceComments ? "已屏蔽段评" : "已显示段评")
                    }
                    toolButton("设置", symbol: "textformat.size") { showSettings = true }
                }
                .padding(.vertical, 7)
                .padding(.horizontal, 6)
                .glassSurface(cornerRadius: 30, tint: settings.theme.isDark ? .white.opacity(0.05) : .white.opacity(0.4))
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

    // MARK: Actions

    private func toggleChrome() {
        withAnimation(.spring(response: 0.34, dampingFraction: 0.86)) {
            showChrome.toggle()
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
                pageIndex = min(pageIndex + 1, max(pages.count - 1, 0))
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

    private func bootstrap() {
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
        if arguments.contains("-showReaderSettings") {
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
        if arguments.contains("-coverTurn") { settings.pageTurnEffect = .cover }
        if arguments.contains("-noTurn") { settings.pageTurnEffect = .none }
        if arguments.contains("-scrollMode") { settings.pageMode = .scroll }
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
        guard book.isNetworkBook, pages.indices.contains(pageIndex) else { return }
        let currentTitle = pages[pageIndex].chapterTitle

        // 只有「下一页已经是另一章」时才算快到章尾。
        let nextPageIndex = pageIndex + 1
        let atChapterEnd: Bool = {
            guard pages.indices.contains(nextPageIndex) else { return true }
            return pages[nextPageIndex].chapterTitle != currentTitle
        }()
        guard atChapterEnd,
              let index = chapters.firstIndex(where: { $0.title == currentTitle }),
              index + 1 < chapters.count,
              chapters[index + 1].paragraphs.isEmpty else { return }

        let next = chapters[index + 1]
        Task { @MainActor in
            let paragraphs = await store.loadNetworkContent(for: book, chapterID: next.id)
            guard paragraphs?.isEmpty == false else { return }
            // 只重排，不跳转：读者还在原页，等他自己翻过去。
            rebuild(restore: false, targetChapter: currentTitle)
        }
    }

    private func rebuild(restore: Bool, targetChapter: String? = nil) {
        // 锚点用「当前页首段的段落 ID」而不是页序号：重排后同一段文字可能不再是某页的第一段，
        // 所以要按「包含该段」来找，而不是按页 id 相等来找。
        // 滚动模式下当前页首段没有意义，改取滚动定位到的段落。
        let anchorParagraphID: String? = isScrollMode
            ? scrollParagraphID
            : (pages.indices.contains(pageIndex) ? pages[pageIndex].paragraphs.first?.id : nil)
        let anchorChapter: String? = isScrollMode
            ? scrollAnchor.chapterTitle
            : (pages.indices.contains(pageIndex) ? pages[pageIndex].chapterTitle : nil)
        let newPages = Paginator.pages(
            for: chapters,
            fontSize: settings.fontSize,
            lineSpacing: settings.lineSpacing,
            viewport: viewport,
            sideMargin: settings.sideMargin
        )
        pages = newPages

        guard !newPages.isEmpty else {
            pageIndex = 0
            return
        }

        if restore, let targetChapter, let index = pageIndexContaining(chapterTitle: targetChapter, paragraphID: nil, in: newPages) {
            pageIndex = index
        } else if restore, let position = store.position(for: book.id) {
            if let index = pageIndexContaining(chapterTitle: position.chapterTitle, paragraphID: position.paragraphID, in: newPages) {
                pageIndex = index
            } else {
                let target = Int((book.progress * Double(max(newPages.count - 1, 0))).rounded())
                pageIndex = min(max(target, 0), newPages.count - 1)
            }
        } else if restore {
            let target = Int((book.progress * Double(max(newPages.count - 1, 0))).rounded())
            pageIndex = min(max(target, 0), newPages.count - 1)
        } else if let anchorParagraphID,
                  let index = pageIndexContaining(chapterTitle: anchorChapter, paragraphID: anchorParagraphID, in: newPages) {
            pageIndex = index
        } else {
            pageIndex = min(pageIndex, newPages.count - 1)
        }

        // 分页算出的落点也是滚动模式的恢复位置：让滚动视图直接滚到那一段。
        if isScrollMode {
            scrollParagraphID = newPages.indices.contains(pageIndex)
                ? newPages[pageIndex].paragraphs.first?.id
                : nil
            updateScrollProgress()
        }

        syncProgress()
    }

    /// 找到包含指定段落的页；段落 ID 缺失时退化为「该章的第一页」。
    private func pageIndexContaining(chapterTitle: String?, paragraphID: String?, in pages: [ReaderPage]) -> Int? {
        guard let chapterTitle else { return nil }
        if let paragraphID,
           let index = pages.firstIndex(where: {
               $0.chapterTitle == chapterTitle && $0.paragraphs.contains { $0.id == paragraphID }
           }) {
            return index
        }
        return pages.firstIndex { $0.chapterTitle == chapterTitle }
    }

    /// 跳转到书签：优先按段落锚点定位，旧书签没有锚点时才回退到页序号。
    private func jump(to bookmark: Bookmark) {
        if isScrollMode {
            scrollParagraphID = bookmark.paragraphID
            updateScrollProgress()
            syncProgress()
            return
        }
        let target = pageIndexContaining(
            chapterTitle: bookmark.chapterTitle,
            paragraphID: bookmark.paragraphID,
            in: pages
        )
        let resolved = target ?? min(max(bookmark.pageIndex, 0), max(pages.count - 1, 0))
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

    private func syncProgress() {
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
        guard !pages.isEmpty, let page = currentPage else { return }
        store.updateProgress(
            bookID: book.id,
            progress: progress,
            position: page.chapterTitle,
            chapterTitle: page.chapterTitle,
            paragraphID: page.paragraphs.first?.id,
            offset: anchorOffset
        )
    }
}

// MARK: - Cover pager

struct PageFlipReader: View {
    let pages: [ReaderPage]
    @Binding var pageIndex: Int
    let bookTitle: String
    let settings: ReaderSettings
    let onComment: (Paragraph) -> Void
    let onExcerpt: (Paragraph) -> Void
    let onTap: () -> Void

    @State private var offset: CGFloat = 0

    private var current: ReaderPage? {
        pages.indices.contains(pageIndex) ? pages[pageIndex] : nil
    }

    private var next: ReaderPage? {
        pages.indices.contains(pageIndex + 1) ? pages[pageIndex + 1] : nil
    }

    private var previous: ReaderPage? {
        pages.indices.contains(pageIndex - 1) ? pages[pageIndex - 1] : nil
    }

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

    private func pageView(_ page: ReaderPage, index: Int) -> some View {
        ReaderPageView(
            page: page,
            pageIndex: index,
            total: pages.count,
            bookTitle: bookTitle,
            settings: settings,
            onComment: onComment,
            onExcerpt: onExcerpt,
            onTap: onTap
        )
    }
}

// MARK: - Page

struct ReaderPageView: View {
    let page: ReaderPage
    let pageIndex: Int
    let total: Int
    let bookTitle: String
    let settings: ReaderSettings
    let onComment: (Paragraph) -> Void
    let onExcerpt: (Paragraph) -> Void
    let onTap: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if settings.showHeaderFooter {
                HStack {
                    Text(page.chapterTitle)
                    Spacer()
                    Text("\(pageIndex + 1) / \(total)")
                        .monospacedDigit()
                }
                .font(.system(size: 10, weight: .medium))
                .tracking(0.9)
                .foregroundStyle(settings.theme.secondary)
                .padding(.bottom, 20)
            }

            VStack(alignment: .leading, spacing: settings.fontSize * (0.72 + settings.lineSpacing * 0.5)) {
                ForEach(page.paragraphs) { paragraph in
                    ParagraphView(
                        paragraph: paragraph,
                        settings: settings,
                        onComment: onComment,
                        onExcerpt: onExcerpt
                    )
                }
            }

            Spacer(minLength: 0)

            if settings.showHeaderFooter {
                HStack {
                    Text(bookTitle)
                    Spacer()
                    Text(page.chapterTitle)
                }
                .font(.system(size: 9.5))
                .foregroundStyle(settings.theme.secondary.opacity(0.55))
            }
        }
        .padding(.horizontal, settings.sideMargin)
        .padding(.top, 72)
        .padding(.bottom, 134)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
        .environment(\.layoutDirection, .leftToRight)
    }
}

struct ParagraphView: View {
    let paragraph: Paragraph
    let settings: ReaderSettings
    let onComment: (Paragraph) -> Void
    let onExcerpt: (Paragraph) -> Void

    private var showsComments: Bool {
        !paragraph.comments.isEmpty && !settings.hideSourceComments
    }

    private var displayText: String {
        var text = paragraph.text
        if settings.purifyText {
            text = text.replacingOccurrences(
                of: #"[(（【][^)）】]{0,24}(本章完|求票|作者说)[^)）】]*[)）】]"#,
                with: "",
                options: .regularExpression
            )
            text = text.replacingOccurrences(
                of: #"(?m)^\s*(作者说|PS|ps)[:：].*$"#,
                with: "",
                options: .regularExpression
            )
        }
        return (settings.indent ? "　　" : "") + text
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Text(displayText)
                .font(.system(
                    size: settings.fontSize,
                    weight: settings.fontWeight.weight,
                    design: settings.fontDesign.design
                ))
                .lineSpacing(settings.fontSize * settings.lineSpacing)
                .foregroundStyle(settings.theme.text)
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
                    .foregroundStyle(settings.theme.accent)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3.5)
                    .glassCapsule(tint: settings.theme.accent.opacity(0.14))
                }
                .buttonStyle(.plain)
                .offset(y: 2)
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
    let chapters: [Chapter]
    let settings: ReaderSettings
    @Binding var visibleParagraphID: String?
    let onComment: (Paragraph) -> Void
    let onExcerpt: (Paragraph) -> Void
    let onTap: () -> Void

    /// 章节标题与段落拍平成一行行，这样章节标题也能参与滚动定位，段落之间仍保持原有间距。
    private enum Row: Identifiable {
        case heading(String)
        case paragraph(Paragraph)

        var id: String {
            switch self {
            case .heading(let title): return "h-\(title)"
            case .paragraph(let paragraph): return paragraph.id
            }
        }
    }

    private var rows: [Row] {
        chapters.flatMap { chapter -> [Row] in
            [.heading(chapter.title)] + chapter.paragraphs.map { Row.paragraph($0) }
        }
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(rows) { row in
                    switch row {
                    case .heading(let title):
                        VStack(alignment: .leading, spacing: 6) {
                            Text(title)
                                .font(.system(size: 13, weight: .semibold, design: .serif))
                                .tracking(1.4)
                                .foregroundStyle(settings.theme.secondary)

                            Rectangle()
                                .fill(settings.theme.secondary.opacity(0.3))
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
            .padding(.top, 90)
            .padding(.bottom, 130)
            .environment(\.layoutDirection, .leftToRight)
        }
        .scrollIndicators(.hidden)
        // 绑定当前可见段落：滚动时回写进度，恢复位置时把绑定值设回去即可自动滚到该段。
        .scrollPosition(id: $visibleParagraphID)
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
    }
}

// MARK: - TOC

struct TOCSheet: View {
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
                                            .foregroundStyle(Palette.text)

                                        Text("\(chapter.paragraphs.count) 段 · \(chapter.paragraphs.reduce(0) { $0 + $1.text.count }) 字")
                                            .font(.system(size: 10.5))
                                            .foregroundStyle(Palette.tertiary)
                                    }

                                    Spacer()

                                    if chapter.title == currentTitle {
                                        HStack(spacing: 4) {
                                            Circle()
                                                .fill(Palette.accent)
                                                .frame(width: 5, height: 5)
                                            Text("在读")
                                                .font(.system(size: 10, weight: .semibold))
                                                .foregroundStyle(Palette.accent)
                                        }
                                    } else {
                                        Image(systemName: "chevron.right")
                                            .font(.system(size: 11, weight: .bold))
                                            .foregroundStyle(Palette.tertiary.opacity(0.5))
                                    }
                                }
                                .padding(.horizontal, 14)
                                .padding(.vertical, 12)
                                .glassSurface(
                                    cornerRadius: 18,
                                    tint: chapter.title == currentTitle ? Palette.accent.opacity(0.1) : nil
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
    @Bindable var settings: ReaderSettings
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var eyePreview = false

    var body: some View {
        NavigationStack {
            ZStack {
                AppBackdrop()

                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        preview

                        fontSizeSection
                        lineSpacingSection
                        themeSection
                        pageModeSection
                        typographySection
                        eyeCareSection

                        Toggle(isOn: $settings.hideSourceComments) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("屏蔽书源段评")
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundStyle(Palette.text)
                                Text("只保留干净的正文")
                                    .font(.system(size: 10.5))
                                    .foregroundStyle(Palette.tertiary)
                            }
                        }
                        .tint(Palette.accent)
                        .padding(.horizontal, 15)
                        .padding(.vertical, 12)
                        .glassSurface(cornerRadius: 18)

                        Toggle(isOn: $settings.purifyText) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("正文净化")
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundStyle(Palette.text)
                                Text("移除「本章完」、作者说等干扰行")
                                    .font(.system(size: 10.5))
                                    .foregroundStyle(Palette.tertiary)
                            }
                        }
                        .tint(Palette.accent)
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
            .foregroundStyle(settings.theme.text)
            .padding(.vertical, 16)
            .padding(.horizontal, min(settings.sideMargin, 28))
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(settings.theme.background, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(settings.theme.text.opacity(0.1), lineWidth: 0.8)
            }
            .overlay(alignment: .topTrailing) {
                Text(settings.theme.rawValue)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(settings.theme.secondary)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .glassCapsule(tint: settings.theme.isDark ? .white.opacity(0.08) : .white.opacity(0.4))
                    .padding(9)
            }
    }

    private var fontSizeSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeading(text: "字号", trailing: "\(Int(settings.fontSize)) pt")

            HStack(spacing: 14) {
                Text("A")
                    .font(.system(size: 12, design: .serif))
                    .foregroundStyle(Palette.tertiary)

                Slider(value: $settings.fontSize, in: 14...28, step: 1)
                    .tint(Palette.accent)

                Text("A")
                    .font(.system(size: 22, design: .serif))
                    .foregroundStyle(Palette.text)
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
                .tint(Palette.accent)
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
                                        selected ? theme.accent : Palette.hairline,
                                        lineWidth: selected ? 1.8 : 0.8
                                    )
                            }

                            Text(theme.rawValue)
                                .font(.system(size: 10.5, weight: selected ? .semibold : .regular))
                                .foregroundStyle(selected ? Palette.text : Palette.tertiary)
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
                    .foregroundStyle(Palette.tertiary)

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

                HStack {
                    Text("左右留白")
                        .font(.system(size: 12))
                        .foregroundStyle(Palette.secondary)
                    Slider(value: $settings.sideMargin, in: 16...46, step: 1)
                        .tint(Palette.accent)
                    Text("\(Int(settings.sideMargin))")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(Palette.tertiary)
                        .monospacedDigit()
                        .frame(width: 22)
                }

                Toggle("首行缩进", isOn: $settings.indent)
                    .font(.system(size: 13))
                    .tint(Palette.accent)

                Toggle("显示页眉页脚", isOn: $settings.showHeaderFooter)
                    .font(.system(size: 13))
                    .tint(Palette.accent)

                Toggle("音量键翻页", isOn: $settings.volumeKeyTurn)
                    .font(.system(size: 13))
                    .tint(Palette.accent)

                Text("真机连接后生效；模拟器可用硬件音量键测试。")
                    .font(.system(size: 9.5))
                    .foregroundStyle(Palette.tertiary)
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
                            .foregroundStyle(Palette.text)
                        Text("降低蓝光刺激，阅读页与书架同步生效")
                            .font(.system(size: 10.5))
                            .foregroundStyle(Palette.tertiary)
                    }
                }
                .tint(Palette.jade)

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
                .tint(Palette.jade)

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
                    .foregroundStyle(Palette.jade)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .glassCapsule(tint: Palette.jade.opacity(0.1), interactive: true)
                }
                .buttonStyle(PressableStyle())

                if eyePreview {
                    Text("已读 20 分钟。看看 6 米外，让眼睛休息 20 秒。")
                        .font(.system(size: 11.5))
                        .foregroundStyle(Palette.secondary)
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .glassSurface(cornerRadius: 14, tint: Palette.jade.opacity(0.08))
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            .padding(14)
            .glassSurface(cornerRadius: 20)
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
            .foregroundStyle(selected ? Palette.text : Palette.secondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 11)
            .glassSurface(
                cornerRadius: 15,
                tint: selected ? Palette.accent.opacity(0.16) : nil,
                interactive: true
            )
        }
        .buttonStyle(PressableStyle())
    }

    private func sliderRow(title: String, value: Binding<Double>, range: ClosedRange<Double>) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 12))
                .foregroundStyle(Palette.secondary)
                .frame(width: 42, alignment: .leading)
            Slider(value: value, in: range)
                .tint(Palette.jade)
            Text("\(Int(value.wrappedValue * 100))%")
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundStyle(Palette.tertiary)
                .monospacedDigit()
                .frame(width: 32)
        }
    }
}

// MARK: - Segment Comments

struct SegmentCommentsSheet: View {
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

    private static let bannedWords = ["加群", "微信", "广告", "代写", "私聊"]

    var body: some View {
        NavigationStack {
            ZStack {
                AppBackdrop()

                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        quoteBlock

                        HStack {
                            SectionHeading(text: "本段 \(comments.count) 条段评")
                            Spacer()
                            Text(isRemote ? "只读 · 来自书源" : "演示评论")
                                .font(.system(size: 9.5, weight: .medium))
                                .foregroundStyle(isRemote ? Palette.jade : Palette.tertiary)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 3)
                                .glassCapsule(tint: (isRemote ? Palette.jade : Palette.faint).opacity(0.12))
                        }

                        if hiddenCount > 0 {
                            Text("已按本地词表隐藏 \(hiddenCount) 条内容")
                                .font(.system(size: 10))
                                .foregroundStyle(Palette.tertiary)
                        }

                        if isLoading {
                            HStack(spacing: 9) {
                                ProgressView()
                                Text("正在向书源请求段评…")
                                    .font(.system(size: 11.5))
                                    .foregroundStyle(Palette.tertiary)
                            }
                            .padding(.top, 24)
                        } else if !remoteError.isEmpty && comments.isEmpty {
                            // 书源有规则但抓取失败：显示原因，不假装「没有评论」。
                            VStack(alignment: .leading, spacing: 7) {
                                HStack(spacing: 7) {
                                    Image(systemName: "exclamationmark.triangle.fill")
                                        .font(.system(size: 11))
                                        .foregroundStyle(Palette.accent)
                                    Text("段评获取失败")
                                        .font(.system(size: 11.5, weight: .semibold))
                                        .foregroundStyle(Palette.text)
                                }
                                Text(remoteError)
                                    .font(.system(size: 10.5))
                                    .foregroundStyle(Palette.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                                Button {
                                    Task { await loadRemote() }
                                } label: {
                                    Text("重试")
                                        .font(.system(size: 11, weight: .semibold))
                                        .foregroundStyle(Palette.jade)
                                }
                                .buttonStyle(PressableStyle())
                            }
                            .padding(13)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .glassSurface(cornerRadius: 18, tint: Palette.accent.opacity(0.06))
                        } else if comments.isEmpty {
                            Text(remoteError.isEmpty ? "这一段还没有段评。" : remoteError)
                                .font(.system(size: 11))
                                .foregroundStyle(Palette.tertiary)
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
                                .foregroundStyle(Palette.accent)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .glassSurface(cornerRadius: 18, tint: Palette.accent.opacity(0.06), interactive: true)
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
            remoteError = error
            applyLocalComments()
            return
        }

        // 书源的评论可能是整章的。能按段落正文匹配就过滤，匹配不上就全显示，
        // 但标清「整章」而不是假装是这一段。
        let matched = result.comments.filter { comment in
            !Self.bannedWords.contains { comment.content.localizedCaseInsensitiveContains($0) }
        }
        hiddenCount = result.comments.count - matched.count
        comments = matched.enumerated().map { index, comment in
            SegmentComment(
                id: "src-\(index)-\(comment.id.hashValue)",
                author: comment.author ?? "读者",
                text: comment.content,
                likes: 0,
                liked: false,
                minutesAgo: 0
            )
        }
        isRemote = true
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
            .foregroundStyle(Palette.accent)

            Text(paragraph.text)
                .font(.system(size: 14, design: .serif))
                .lineSpacing(5)
                .foregroundStyle(Palette.secondary)
        }
        .padding(15)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassSurface(cornerRadius: 20, tint: Palette.accent.opacity(0.07))
    }

    private func commentCard(_ comment: SegmentComment, index: Int) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                // 头像色块
                Text(String(comment.author.prefix(1)))
                    .font(.system(size: 12, weight: .semibold, design: .serif))
                    .foregroundStyle(.white)
                    .frame(width: 26, height: 26)
                    .background(
                        LinearGradient(
                            colors: [Palette.cover(index).0, Palette.cover(index).1],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        in: Circle()
                    )

                VStack(alignment: .leading, spacing: 1) {
                    Text(comment.author)
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(Palette.text)

                    Text(relativeTime(comment.minutesAgo))
                        .font(.system(size: 9.5))
                        .foregroundStyle(Palette.tertiary)
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
                    .foregroundStyle(Palette.tertiary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .glassCapsule(tint: Palette.glassTint)
                }
            }

            Text(comment.text)
                .font(.system(size: 14, design: .serif))
                .lineSpacing(4)
                .foregroundStyle(Palette.text)
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
