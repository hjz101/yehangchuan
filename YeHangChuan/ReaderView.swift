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

    private var settings: ReaderSettings { store.settings }
    private var chapters: [Chapter] { MockData.chapters(for: book) }
    private var currentPage: ReaderPage? { pages.indices.contains(pageIndex) ? pages[pageIndex] : nil }

    private var progress: Double {
        pages.count <= 1 ? 0 : Double(pageIndex) / Double(pages.count - 1)
    }

    var body: some View {
        ZStack {
            settings.theme.background.ignoresSafeArea()

            readingContent

            if showChrome {
                topBar
                bottomBar
            }

            if let flash {
                Text(flash)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(settings.theme.text)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(.regularMaterial, in: Capsule())
                    .transition(.opacity)
            }
        }
        .preferredColorScheme(settings.theme.isDark ? .dark : .light)
        .statusBarHidden(!showChrome)
        .onAppear {
            rebuild(restore: true)

            #if DEBUG
            let arguments = ProcessInfo.processInfo.arguments
            if arguments.contains("-showReaderSettings") {
                showSettings = true
            } else if arguments.contains("-showComments") {
                commentParagraph = chapters.flatMap(\.paragraphs).first { !$0.comments.isEmpty }
            }
            #endif
        }
        .onChange(of: settings.fontSize) { _, _ in
            rebuild(restore: false)
        }
        .onChange(of: settings.pageMode) { _, _ in
            rebuild(restore: false)
        }
        .onChange(of: pageIndex) { _, _ in
            syncProgress()
        }
        .sheet(isPresented: $showTOC) {
            TOCSheet(
                chapters: chapters,
                currentTitle: currentPage?.chapterTitle ?? ""
            ) { title in
                if let index = pages.firstIndex(where: { $0.chapterTitle == title }) {
                    pageIndex = index
                    withAnimation(.easeOut(duration: 0.2)) {
                        showChrome = false
                    }
                }
                showTOC = false
            }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showSettings) {
            ReaderSettingsSheet(settings: settings)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .sheet(item: $commentParagraph) { paragraph in
            SegmentCommentsSheet(paragraph: paragraph)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
    }

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
                onTap: toggleChrome
            )
        }
    }

    private var topBar: some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 16, weight: .semibold))
                        .frame(width: 28, height: 28)
                }

                VStack(alignment: .leading, spacing: 1) {
                    Text(book.title)
                        .font(.system(size: 13, weight: .semibold, design: .serif))

                    Text(currentPage?.chapterTitle ?? book.lastPosition)
                        .font(.system(size: 10))
                        .foregroundStyle(settings.theme.secondary)
                }

                Spacer()

                Button {
                    isBookmarked.toggle()
                    showFlash(isBookmarked ? "已添加书签" : "已移除书签")
                } label: {
                    Image(systemName: isBookmarked ? "bookmark.fill" : "bookmark")
                        .font(.system(size: 15, weight: .medium))
                        .frame(width: 28, height: 28)
                }
            }
            .foregroundStyle(settings.theme.text)
            .padding(.horizontal, 18)
            .padding(.top, 6)
            .padding(.bottom, 10)
            .background(.ultraThinMaterial, ignoresSafeAreaEdges: .top)

            Spacer()
        }
        .transition(.move(edge: .top).combined(with: .opacity))
    }

    private var bottomBar: some View {
        VStack(spacing: 12) {
            HStack(spacing: 10) {
                Text("\(Int(progress * 100))%")

                ProgressView(value: progress)
                    .tint(Theme.accent)
                    .scaleEffect(y: 0.8)

                Text(settings.pageMode == .scroll ? "滚动" : "\(pageIndex + 1) / \(pages.count)")
            }
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(settings.theme.secondary)

            HStack(spacing: 0) {
                toolButton("目录", symbol: "list.bullet") {
                    showTOC = true
                }

                toolButton("书签", symbol: isBookmarked ? "bookmark.fill" : "bookmark") {
                    isBookmarked.toggle()
                    showFlash(isBookmarked ? "已添加书签" : "已移除书签")
                }

                toolButton(
                    "段评",
                    symbol: settings.hideSourceComments ? "text.bubble" : "text.bubble.fill"
                ) {
                    settings.hideSourceComments.toggle()
                    showFlash(settings.hideSourceComments ? "已屏蔽段评" : "已显示段评")
                }

                toolButton("设置", symbol: "textformat.size") {
                    showSettings = true
                }
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 10)
        .padding(.bottom, 2)
        .background(.ultraThinMaterial, ignoresSafeAreaEdges: .bottom)
        .frame(maxHeight: .infinity, alignment: .bottom)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    private func toolButton(_ title: String, symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 5) {
                Image(systemName: symbol)
                    .font(.system(size: 16, weight: .medium))

                Text(title)
                    .font(.system(size: 10))
            }
            .foregroundStyle(settings.theme.text)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
    }

    private func toggleChrome() {
        withAnimation(.easeOut(duration: 0.2)) {
            showChrome.toggle()
        }
    }

    private func showFlash(_ text: String) {
        withAnimation(.easeOut(duration: 0.15)) {
            flash = text
        }

        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.4))
            if flash == text {
                withAnimation(.easeOut(duration: 0.2)) {
                    flash = nil
                }
            }
        }
    }

    private func rebuild(restore: Bool) {
        let anchor = pages.indices.contains(pageIndex) ? pages[pageIndex] : nil
        let newPages = Paginator.pages(for: chapters, fontSize: settings.fontSize)
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

struct ReaderPageView: View {
    let page: ReaderPage
    let pageIndex: Int
    let total: Int
    let bookTitle: String
    let settings: ReaderSettings
    let onComment: (Paragraph) -> Void
    let onTap: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(page.chapterTitle)
                Spacer()
                Text("\(pageIndex + 1) / \(total)")
            }
            .font(.system(size: 10, weight: .medium))
            .tracking(0.8)
            .foregroundStyle(settings.theme.secondary)
            .padding(.bottom, 18)

            VStack(alignment: .leading, spacing: settings.fontSize * 0.85) {
                ForEach(page.paragraphs) { paragraph in
                    ParagraphView(
                        paragraph: paragraph,
                        settings: settings,
                        onComment: onComment
                    )
                }
            }

            Spacer(minLength: 0)

            HStack {
                Text(bookTitle)
                Spacer()
                Text(page.chapterTitle)
            }
            .font(.system(size: 10))
            .foregroundStyle(settings.theme.secondary.opacity(0.7))
        }
        .padding(.horizontal, 26)
        .padding(.top, 62)
        .padding(.bottom, 104)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
    }
}

struct ParagraphView: View {
    let paragraph: Paragraph
    let settings: ReaderSettings
    let onComment: (Paragraph) -> Void

    private var showsComments: Bool {
        !paragraph.comments.isEmpty && !settings.hideSourceComments
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Text("　　" + paragraph.text)
                .font(.system(size: settings.fontSize, design: .serif))
                .lineSpacing(settings.fontSize * settings.lineSpacing)
                .foregroundStyle(settings.theme.text)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.trailing, showsComments ? 26 : 0)

            if showsComments {
                Button {
                    onComment(paragraph)
                } label: {
                    HStack(spacing: 2) {
                        Image(systemName: "text.bubble.fill")
                        Text("\(paragraph.comments.count)")
                    }
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Theme.accent)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 3)
                    .background(Theme.accent.opacity(0.09), in: Capsule())
                }
                .buttonStyle(.plain)
            }
        }
    }
}

struct ScrollReaderView: View {
    let chapters: [Chapter]
    let settings: ReaderSettings
    let onComment: (Paragraph) -> Void
    let onTap: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                ForEach(chapters) { chapter in
                    Text(chapter.title)
                        .font(.system(size: 12, weight: .semibold))
                        .tracking(1.2)
                        .foregroundStyle(settings.theme.secondary)

                    ForEach(chapter.paragraphs) { paragraph in
                        ParagraphView(
                            paragraph: paragraph,
                            settings: settings,
                            onComment: onComment
                        )
                    }
                }
            }
            .padding(.horizontal, 26)
            .padding(.top, 70)
            .padding(.bottom, 120)
        }
        .scrollIndicators(.hidden)
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
    }
}

struct TOCSheet: View {
    @Environment(\.dismiss) private var dismiss

    let chapters: [Chapter]
    let currentTitle: String
    let onSelect: (String) -> Void

    var body: some View {
        NavigationStack {
            List {
                ForEach(chapters) { chapter in
                    Button {
                        onSelect(chapter.title)
                    } label: {
                        HStack {
                            Text(chapter.title)
                                .font(.system(size: 15))
                                .foregroundStyle(Theme.text)

                            Spacer()

                            if chapter.title == currentTitle {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(Theme.accent)
                            }
                        }
                        .padding(.vertical, 5)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.paper)
            .navigationTitle("目录")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") { dismiss() }
                }
            }
        }
    }
}

struct ReaderSettingsSheet: View {
    @Bindable var settings: ReaderSettings
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.paper.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 26) {
                        VStack(alignment: .leading, spacing: 12) {
                            SectionHeading(text: "字号")

                            HStack(spacing: 14) {
                                Text("A")
                                    .font(.system(size: 12, design: .serif))
                                    .foregroundStyle(Theme.secondary)

                                Slider(value: $settings.fontSize, in: 15...26, step: 1)
                                    .tint(Theme.accent)

                                Text("A")
                                    .font(.system(size: 24, design: .serif))
                                    .foregroundStyle(Theme.text)
                            }

                            Text("\(Int(settings.fontSize)) pt")
                                .font(.system(size: 11))
                                .foregroundStyle(Theme.secondary)
                        }

                        VStack(alignment: .leading, spacing: 12) {
                            SectionHeading(text: "行距")
                            Slider(value: $settings.lineSpacing, in: 0.3...1.4, step: 0.1)
                                .tint(Theme.accent)
                        }

                        VStack(alignment: .leading, spacing: 12) {
                            SectionHeading(text: "主题")

                            HStack(spacing: 10) {
                                ForEach(ReaderTheme.allCases) { theme in
                                    Button {
                                        settings.theme = theme
                                    } label: {
                                        VStack(spacing: 7) {
                                            RoundedRectangle(cornerRadius: 6)
                                                .fill(theme.background)
                                                .frame(height: 56)
                                                .overlay {
                                                    Text("文")
                                                        .font(.system(size: 19, design: .serif))
                                                        .foregroundStyle(theme.text)
                                                }
                                                .overlay {
                                                    RoundedRectangle(cornerRadius: 6)
                                                        .stroke(
                                                            settings.theme == theme ? Theme.accent : Theme.hairline,
                                                            lineWidth: settings.theme == theme ? 2 : 1
                                                        )
                                                }

                                            Text(theme.rawValue)
                                                .font(.system(size: 11, weight: settings.theme == theme ? .semibold : .regular))
                                                .foregroundStyle(settings.theme == theme ? Theme.accent : Theme.secondary)
                                        }
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }

                        VStack(alignment: .leading, spacing: 12) {
                            SectionHeading(text: "翻页方式")

                            Picker("翻页方式", selection: $settings.pageMode) {
                                ForEach(PageMode.allCases) { mode in
                                    Text(mode.rawValue).tag(mode)
                                }
                            }
                            .pickerStyle(.segmented)
                        }

                        Toggle("屏蔽书源段评", isOn: $settings.hideSourceComments)
                            .font(.system(size: 15))
                            .tint(Theme.accent)
                            .foregroundStyle(Theme.text)

                        Text("　　夜色漫上船头，灯影落在书页上。远处有人收缆，水声一下一下，像替谁数着日子。")
                            .font(.system(size: settings.fontSize, design: .serif))
                            .lineSpacing(settings.fontSize * settings.lineSpacing)
                            .foregroundStyle(settings.theme.text)
                            .padding(16)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(settings.theme.background, in: RoundedRectangle(cornerRadius: 8))
                            .overlay {
                                RoundedRectangle(cornerRadius: 8).stroke(Theme.hairline)
                            }
                    }
                    .padding(20)
                }
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
}

struct SegmentCommentsSheet: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    let paragraph: Paragraph

    var body: some View {
        @Bindable var settings = store.settings

        NavigationStack {
            ZStack {
                Theme.paper.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        Text(paragraph.text)
                            .font(.system(size: 14, design: .serif))
                            .foregroundStyle(Theme.secondary)
                            .lineSpacing(5)
                            .padding(.bottom, 6)

                        HStack {
                            SectionHeading(text: "本段 \(paragraph.comments.count) 条段评")
                            Spacer()
                            Text("来自书源 · 只读")
                                .font(.system(size: 10))
                                .foregroundStyle(Theme.secondary.opacity(0.8))
                        }

                        ForEach(paragraph.comments) { comment in
                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    Text(comment.author)
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundStyle(Theme.text)

                                    Spacer()

                                    Image(systemName: "quote.opening")
                                        .font(.system(size: 9))
                                        .foregroundStyle(Theme.accent.opacity(0.5))
                                }

                                Text(comment.text)
                                    .font(.system(size: 14, design: .serif))
                                    .foregroundStyle(Theme.text)
                                    .lineSpacing(4)
                            }
                            .padding(14)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.white.opacity(0.6), in: RoundedRectangle(cornerRadius: 8))
                        }

                    }
                    .padding(20)
                }
            }
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: 0) {
                    Divider().overlay(Theme.hairline)

                    Toggle("屏蔽此源段评", isOn: $settings.hideSourceComments)
                        .font(.system(size: 14))
                        .tint(Theme.accent)
                        .foregroundStyle(Theme.text)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 14)
                        .background(.regularMaterial)
                }
            }
            .navigationTitle("段评")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") { dismiss() }
                }
            }
        }
    }
}
