import SwiftUI

struct ReaderView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    let book: Book

    @State private var pages: [ReaderPage] = []
    @State private var pageIndex = 0
    @State private var showChrome = true
    @State private var showTOC = false
    @State private var showSettings = false
    @State private var commentParagraph: Paragraph?
    @State private var isBookmarked = false
    @State private var flash: String?
    @State private var viewport: CGSize = CGSize(width: 390, height: 844)

    private var settings: ReaderSettings { store.settings }
    private var chapters: [Chapter] { MockData.chapters(for: book) }
    private var currentPage: ReaderPage? { pages.indices.contains(pageIndex) ? pages[pageIndex] : nil }

    private var progress: Double {
        pages.count <= 1 ? 0 : Double(pageIndex) / Double(pages.count - 1)
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
            if settings.pageMode == .slide && showChrome == false {
                HStack(spacing: 0) {
                    tapZone(.backward)
                    tapZone(.forward)
                }
            }
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
        .onChange(of: settings.pageMode) { _, _ in rebuild(restore: false) }
        .onChange(of: pageIndex) { _, _ in syncProgress() }
        .sheet(isPresented: $showTOC) {
            TOCSheet(chapters: chapters, currentTitle: currentPage?.chapterTitle ?? "") { title in
                if let index = pages.firstIndex(where: { $0.chapterTitle == title }) {
                    pageIndex = index
                    hideChromeAfterDelay()
                }
                showTOC = false
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
            SegmentCommentsSheet(paragraph: paragraph)
                .presentationDetents([.fraction(0.62), .large])
                .presentationCornerRadius(38)
                .presentationDragIndicator(.visible)
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
        if pages.isEmpty {
            ProgressView()
        } else if settings.pageMode == .slide {
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
        } else {
            ScrollReaderView(
                chapters: chapters,
                settings: settings,
                onComment: { commentParagraph = $0 },
                onExcerpt: { paragraph in excerpt(paragraph) },
                onTap: toggleChrome
            )
        }
    }

    private enum TapZone { case backward, forward }

    private func tapZone(_ zone: TapZone) -> some View {
        Color.clear
            .contentShape(Rectangle())
            .onTapGesture {
                withAnimation(.spring(response: 0.32, dampingFraction: 0.85)) {
                    if zone == .backward {
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

                    Text(currentPage?.chapterTitle ?? book.lastPosition)
                        .font(.system(size: 10))
                        .foregroundStyle(settings.theme.secondary)
                        .lineLimit(1)
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 8)
                .glassCapsule()

                Spacer(minLength: 0)

                Button {
                    isBookmarked.toggle()
                    showFlash(isBookmarked ? "已添加书签" : "已移除书签")
            } label: {
                Image(systemName: isBookmarked ? "bookmark.fill" : "bookmark")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(isBookmarked ? Palette.accent : chromeColor)
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
                        isBookmarked.toggle()
                        showFlash(isBookmarked ? "已添加书签" : "已移除书签")
                    }
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
            chapter: currentPage?.chapterTitle ?? book.lastPosition,
            text: paragraph.text
        )
        showFlash("已摘录这一句")
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
        rebuild(restore: true)

        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("-showReaderSettings") {
            showSettings = true
        } else if arguments.contains("-showComments") {
            commentParagraph = chapters.flatMap(\.paragraphs).first { !$0.comments.isEmpty }
        } else if arguments.contains("-hideChrome") {
            showChrome = false
        }
        #endif
    }

    private func rebuild(restore: Bool) {
        let anchor = pages.indices.contains(pageIndex) ? pages[pageIndex] : nil
        let newPages = Paginator.pages(
            for: chapters,
            fontSize: settings.fontSize,
            lineSpacing: settings.lineSpacing,
            viewport: viewport
        )
        pages = newPages

        guard !newPages.isEmpty else {
            pageIndex = 0
            return
        }

        if restore {
            let target = Int((book.progress * Double(max(newPages.count - 1, 0))).rounded())
            pageIndex = min(max(target, 0), newPages.count - 1)
        } else if let anchor, let index = newPages.firstIndex(where: { $0.id == anchor.id }) {
            pageIndex = index
        } else {
            pageIndex = min(pageIndex, newPages.count - 1)
        }

        syncProgress()
    }

    private func syncProgress() {
        guard !pages.isEmpty else { return }
        store.updateProgress(
            bookID: book.id,
            progress: progress,
            position: currentPage?.chapterTitle ?? book.lastPosition
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

            HStack {
                Text(bookTitle)
                Spacer()
                Text(page.chapterTitle)
            }
            .font(.system(size: 9.5))
            .foregroundStyle(settings.theme.secondary.opacity(0.55))
        }
        .padding(.horizontal, 28)
        .padding(.top, 72)
        .padding(.bottom, 134)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
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

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Text("　　" + paragraph.text)
                .font(.system(size: settings.fontSize, design: .serif))
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
    let onComment: (Paragraph) -> Void
    let onExcerpt: (Paragraph) -> Void
    let onTap: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 30) {
                ForEach(chapters) { chapter in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(chapter.title)
                            .font(.system(size: 13, weight: .semibold, design: .serif))
                            .tracking(1.4)
                            .foregroundStyle(settings.theme.secondary)

                        Rectangle()
                            .fill(settings.theme.secondary.opacity(0.3))
                            .frame(width: 26, height: 1.5)
                    }
                    .padding(.top, 8)

                    VStack(alignment: .leading, spacing: settings.fontSize * (0.72 + settings.lineSpacing * 0.5)) {
                        ForEach(chapter.paragraphs) { paragraph in
                            ParagraphView(
                                paragraph: paragraph,
                                settings: settings,
                                onComment: onComment,
                                onExcerpt: onExcerpt
                            )
                        }
                    }
                }
            }
            .padding(.horizontal, 28)
            .padding(.top, 90)
            .padding(.bottom, 130)
        }
        .scrollIndicators(.hidden)
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

    private var filtered: [Chapter] {
        guard !query.isEmpty else { return chapters }
        return chapters.filter { $0.title.localizedCaseInsensitiveContains(query) }
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
    @Environment(\.dismiss) private var dismiss

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
        }
    }

    private var preview: some View {
        Text("　　夜色漫上船头，灯影落在书页上。远处有人收缆，水声一下一下，像替谁数着日子。")
            .font(.system(size: settings.fontSize, design: .serif))
            .lineSpacing(settings.fontSize * settings.lineSpacing)
            .foregroundStyle(settings.theme.text)
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(settings.theme.background, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(settings.theme.text.opacity(0.1), lineWidth: 0.8)
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

            HStack(spacing: 9) {
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
                    let selected = settings.pageMode == mode
                    Button {
                        withAnimation(.spring(response: 0.34, dampingFraction: 0.86)) {
                            settings.pageMode = mode
                        }
                    } label: {
                        HStack(spacing: 7) {
                            Image(systemName: mode.symbol)
                                .font(.system(size: 13, weight: .medium))
                            Text(mode.rawValue)
                                .font(.system(size: 13, weight: selected ? .semibold : .medium))
                        }
                        .foregroundStyle(selected ? Palette.text : Palette.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .glassSurface(
                            cornerRadius: 16,
                            tint: selected ? Palette.accent.opacity(0.16) : nil,
                            interactive: true
                        )
                    }
                    .buttonStyle(PressableStyle())
                }
            }
        }
    }
}

// MARK: - Segment Comments

struct SegmentCommentsSheet: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    let paragraph: Paragraph

    @State private var comments: [SegmentComment] = []

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
                            Text("来自书源")
                                .font(.system(size: 9.5, weight: .medium))
                                .foregroundStyle(Palette.tertiary)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 3)
                                .glassCapsule(tint: Palette.jade.opacity(0.12))
                        }

                        ForEach(Array(comments.enumerated()), id: \.element.id) { index, comment in
                            commentCard(comment, index: index)
                        }
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
            .onAppear { comments = paragraph.comments }
        }
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

                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        if let i = comments.firstIndex(where: { $0.id == comment.id }) {
                            comments[i].liked.toggle()
                            comments[i].likes += comments[i].liked ? 1 : -1
                        }
                    }
                } label: {
                    HStack(spacing: 3.5) {
                        Image(systemName: comment.liked ? "heart.fill" : "heart")
                            .font(.system(size: 10, weight: .semibold))
                        Text("\(comment.likes)")
                            .font(.system(size: 10, weight: .medium))
                            .monospacedDigit()
                    }
                    .foregroundStyle(comment.liked ? Palette.accent : Palette.tertiary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .glassCapsule(tint: comment.liked ? Palette.accent.opacity(0.14) : nil)
                }
                .buttonStyle(PressableStyle(scale: 0.9))
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
