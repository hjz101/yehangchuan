import SwiftUI

enum ShelfStatus: String, CaseIterable, Identifiable {
    case all = "全部"
    case reading = "在读"
    case finished = "已读完"

    var id: String { rawValue }
}

struct ShelfView: View {
    @Environment(AppStore.self) private var store

    @State private var filter: BookKind?
    @State private var status: ShelfStatus = .all
    @State private var query = ""
    @State private var groupFilter: String?
    @State private var readerTarget: ReaderTarget?
    @State private var detailBook: Book?
    @State private var comicBook: Book?
    @State private var showImport = false
    @State private var showNewGroup = false
    @State private var newGroupName = ""
    @State private var showSearch = false
    @State private var columns = 3

    private var filteredBooks: [Book] {
        store.books.filter { book in
            let kindMatches = filter == nil || book.kind == filter
            let statusMatches = switch status {
            case .all: true
            case .reading: !book.isFinished
            case .finished: book.isFinished
            }
            let queryMatches = query.isEmpty
                || book.title.localizedCaseInsensitiveContains(query)
                || book.author.localizedCaseInsensitiveContains(query)
            let groupMatches = groupFilter == nil || book.group == groupFilter
            return kindMatches && statusMatches && queryMatches && groupMatches
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AppBackdrop()

                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 22) {
                        if let book = store.continueBook, query.isEmpty {
                            hero(book)
                        }

                        filterBar

                        if filteredBooks.isEmpty {
                            emptyState
                        } else {
                            grid
                        }
                    }
                    .padding(.horizontal, 18)
                    .padding(.top, 6)
                    .padding(.bottom, 28)
                }
                .scrollIndicators(.hidden)
                .contentMargins(.bottom, 170, for: .scrollContent)
            }
            .navigationTitle("夜航船")
            .navigationSubtitle(subtitle)
            .toolbarTitleDisplayMode(.inlineLarge)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showSearch = true
                    } label: {
                        Image(systemName: "magnifyingglass")
                    }
                    .accessibilityLabel("搜索书架")
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        withAnimation(.spring(response: 0.36, dampingFraction: 0.85)) {
                            columns = columns == 3 ? 2 : 3
                        }
                    } label: {
                        Image(systemName: columns == 3 ? "rectangle.grid.2x2" : "rectangle.grid.3x2")
                    }
                    .accessibilityLabel("切换网格密度")
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button {
                            showImport = true
                        } label: {
                            Label("导入本地书", systemImage: "square.and.arrow.down")
                        }

                        Button {
                            showNewGroup = true
                        } label: {
                            Label("新建分组", systemImage: "folder.badge.plus")
                        }

                        if !store.groups.isEmpty {
                            Menu("书架分组") {
                                Button("全部") { groupFilter = nil }
                                ForEach(store.groups, id: \.self) { group in
                                    Button(group) { groupFilter = group }
                                }
                            }
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .accessibilityLabel("更多书架操作")
                }
            }
        }
        .fullScreenCover(item: $readerTarget) { target in
            ReaderView(book: target.book, initialChapterTitle: target.chapterTitle)
        }
        .fullScreenCover(item: $comicBook) { book in
            ComicReaderView(book: book)
        }
        .sheet(item: $detailBook) { book in
            MediaDetailView(book: book)
                .presentationDetents([.fraction(0.72), .large])
                .presentationDragIndicator(.visible)
                .presentationCornerRadius(38)
        }
        .sheet(isPresented: $showSearch) {
            ShelfSearchSheet(query: $query)
                .presentationDetents([.large])
                .presentationCornerRadius(38)
                .themedChrome(store)
        }
        .sheet(isPresented: $showImport) {
            SmartImportSheet()
                .presentationDetents([.large])
                .presentationCornerRadius(38)
                .themedChrome(store)
        }
        .alert("新建分组", isPresented: $showNewGroup) {
            TextField("分组名称", text: $newGroupName)
            Button("取消", role: .cancel) { newGroupName = "" }
            Button("创建") {
                store.addGroup(newGroupName)
                newGroupName = ""
            }
        } message: {
            Text("分组保存在本机，可长按书籍移动。")
        }
        .task {
            #if DEBUG
            let arguments = ProcessInfo.processInfo.arguments
            if arguments.contains("-openReader"), readerTarget == nil {
                if let book = store.books.first(where: { $0.id == "yehangchuan" }) {
                    readerTarget = ReaderTarget(book: book)
                }
            }
            if arguments.contains("-openSearch") {
                showSearch = true
            }
            if arguments.contains("-openImport") {
                showImport = true
            }
            if arguments.contains("-openComic"), let book = store.books.first(where: { $0.kind == .comic }) {
                comicBook = book
            }
            #endif
        }
    }

    private var subtitle: String {
        if store.readingCount == 0 {
            return "书架空着，去书源找一本"
        }
        return "\(store.readingCount) 本在读 · \(store.finishedCount) 本读完"
    }

    // MARK: Hero

    private func hero(_ book: Book) -> some View {
        Button {
            open(book)
        } label: {
            HStack(spacing: 16) {
                BookCover(book: book, cornerRadius: 10, prominent: true)
                    .frame(width: 78)

                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(Palette.accent)
                            .frame(width: 5, height: 5)

                        Text("继续阅读")
                            .font(.system(size: 10, weight: .semibold))
                            .tracking(1.4)
                            .foregroundStyle(Palette.accent)
                    }

                    Text(book.title)
                        .font(.system(size: 21, weight: .semibold, design: .serif))
                        .foregroundStyle(Palette.text)
                        .lineLimit(1)

                    Text(book.lastPosition)
                        .font(.system(size: 11.5))
                        .foregroundStyle(Palette.secondary)
                        .lineLimit(1)

                    HStack(spacing: 8) {
                        ProgressBar(value: book.progress, tint: Palette.accent, height: 3)

                        Text("\(Int(book.progress * 100))%")
                            .font(.system(size: 10, weight: .semibold, design: .rounded))
                            .foregroundStyle(Palette.tertiary)
                            .monospacedDigit()
                    }
                    .padding(.top, 2)
                }

                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Palette.tertiary.opacity(0.6))
            }
            .padding(15)
            .glassSurface(cornerRadius: 26, tint: Palette.accent.opacity(0.10), interactive: true)
            .contentShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        }
        .buttonStyle(PressableStyle(scale: 0.985))
    }

    // MARK: Filters

    private var filterBar: some View {
        HStack(spacing: 8) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    chip("全部", selected: filter == nil, tint: Palette.accent) {
                        filter = nil
                    }

                    ForEach(BookKind.allCases) { kind in
                        chip(kind.rawValue, selected: filter == kind, tint: kind.tint) {
                            filter = kind
                        }
                    }

                    if let groupFilter {
                        chip(groupFilter, selected: true, tint: Palette.jade) {
                            self.groupFilter = nil
                        }
                    }
                }
                .padding(.vertical, 2)
            }
            .scrollClipDisabled()

            Menu {
                Picker("阅读状态", selection: $status) {
                    ForEach(ShelfStatus.allCases) { item in
                        Text(item.rawValue).tag(item)
                    }
                }
            } label: {
                Image(systemName: status == .all ? "line.3.horizontal.decrease" : "line.3.horizontal.decrease.circle.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(status == .all ? Palette.secondary : Palette.jade)
                    .frame(width: 36, height: 36)
                    .glassCircle(diameter: 36, tint: status == .all ? nil : Palette.jade.opacity(0.16))
            }
            .accessibilityLabel("阅读状态筛选")
        }
    }

    private func chip(_ title: String, selected: Bool, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13, weight: selected ? .semibold : .medium))
                .foregroundStyle(selected ? Palette.onAccent : Palette.secondary)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background {
                    if selected {
                        Capsule().fill(tint)
                    }
                }
                .glassCapsule(tint: selected ? nil : Palette.glassTint, interactive: true)
                .contentShape(Capsule())
        }
        .buttonStyle(PressableStyle())
    }

    // MARK: Grid

    private var grid: some View {
        LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(), spacing: 14, alignment: .top), count: columns),
            alignment: .leading,
            spacing: 20
        ) {
            ForEach(filteredBooks) { book in
                ShelfBookCell(book: book, showProgress: columns == 2)
                    .onTapGesture { open(book) }
                    .contextMenu {
                        Button {
                            store.toggleFinished(book.id)
                        } label: {
                            Label(book.isFinished ? "标记为在读" : "标记为读完",
                                  systemImage: book.isFinished ? "arrow.uturn.backward" : "checkmark.circle")
                        }

                        Button {
                            detailBook = book
                        } label: {
                            Label("查看详情", systemImage: "info.circle")
                        }

                        if !store.groups.isEmpty {
                            Menu {
                                Button("未分组") { store.setGroup(nil, for: book.id) }
                                ForEach(store.groups, id: \.self) { group in
                                    Button(group) { store.setGroup(group, for: book.id) }
                                }
                            } label: {
                                Label("移动到分组", systemImage: "folder")
                            }
                        }

                        if book.kind == .audio {
                            Button {
                                store.player.load(book)
                            } label: {
                                Label("开始收听", systemImage: "play.circle")
                            }
                        }

                        Button(role: .destructive) {
                            store.removeBook(book.id)
                        } label: {
                            Label("从书架移除", systemImage: "trash")
                        }
                    }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "books.vertical")
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(Palette.tertiary)

            Text(query.isEmpty ? "这里还没有书" : "没有找到匹配的书")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Palette.text)

            Text(query.isEmpty ? "去书源页搜索并加入书架" : "换个关键词试试")
                .font(.system(size: 12))
                .foregroundStyle(Palette.secondary)

            if !query.isEmpty {
                Button("清除搜索") { query = "" }
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Palette.accent)
                    .padding(.top, 2)
            } else {
                Button {
                    showImport = true
                } label: {
                    Label("导入本地书", systemImage: "square.and.arrow.down")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Palette.accent)
                        .padding(.top, 4)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
    }

    private func open(_ book: Book) {
        switch book.kind {
        case .novel:
            readerTarget = ReaderTarget(book: book)
        case .audio:
            store.player.load(book)
        case .comic:
            comicBook = book
        }
    }
}

// MARK: - Cell

struct ShelfBookCell: View {
    let book: Book
    var showProgress = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            BookCover(book: book, cornerRadius: 11)
                .overlay(alignment: .topTrailing) {
                    if book.isFinished {
                        Image(systemName: "checkmark")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(Palette.onAccent)
                            .frame(width: 18, height: 18)
                            .background(Palette.jade, in: Circle())
                            .padding(7)
                    }
                }
                .overlay(alignment: .bottomLeading) {
                    if book.progress > 0 && !book.isFinished {
                        HStack(spacing: 4) {
                            Text("\(Int(book.progress * 100))%")
                                .font(.system(size: 9, weight: .semibold, design: .rounded))
                                .foregroundStyle(.white)
                                .monospacedDigit()

                            ProgressBar(value: book.progress, tint: .white, track: .white.opacity(0.3), height: 2)
                                .frame(width: 26)
                        }
                        .padding(.horizontal, 6)
                        .padding(.vertical, 4)
                        .glassCapsule(tint: .black.opacity(0.28))
                        .padding(7)
                    }
                }

            VStack(alignment: .leading, spacing: 2) {
                Text(book.title)
                    .font(.system(size: showProgress ? 14 : 12.5, weight: .semibold, design: .serif))
                    .foregroundStyle(Palette.text)
                    .lineLimit(1)

                Text(book.kind == .novel ? book.author : "\(book.kind.rawValue) · \(book.author)")
                    .font(.system(size: showProgress ? 11 : 10))
                    .foregroundStyle(Palette.tertiary)
                    .lineLimit(1)
            }
        }
        .contentShape(Rectangle())
    }
}

// MARK: - Search

struct ShelfSearchSheet: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Binding var query: String

    @FocusState private var focused: Bool

    private var results: [Book] {
        guard !query.isEmpty else { return store.books }
        return store.books.filter {
            $0.title.localizedCaseInsensitiveContains(query) || $0.author.localizedCaseInsensitiveContains(query)
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AppBackdrop()

                ScrollView {
                    VStack(spacing: 10) {
                        ForEach(results) { book in
                            HStack(spacing: 13) {
                                BookCover(book: book, cornerRadius: 8)
                                    .frame(width: 48)

                                VStack(alignment: .leading, spacing: 3) {
                                    Text(book.title)
                                        .font(.system(size: 15, weight: .semibold, design: .serif))
                                        .foregroundStyle(Palette.text)

                                    Text("\(book.author) · \(book.kind.rawValue)")
                                        .font(.system(size: 11))
                                        .foregroundStyle(Palette.secondary)
                                }

                                Spacer()

                                Text(book.lastPosition)
                                    .font(.system(size: 10))
                                    .foregroundStyle(Palette.tertiary)
                                    .lineLimit(1)
                            }
                            .padding(11)
                            .glassSurface(cornerRadius: 18)
                        }

                        if results.isEmpty {
                            ContentUnavailableView("没有这本书", systemImage: "magnifyingglass", description: Text("试试书名或作者"))
                                .padding(.top, 40)
                        }
                    }
                    .padding(.horizontal, 18)
                    .padding(.bottom, 30)
                }
                .scrollIndicators(.hidden)
            }
            .navigationTitle("搜索书架")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $query, placement: .toolbar, prompt: "书名或作者")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") { dismiss() }
                        .fontWeight(.semibold)
                }
            }
            .onAppear { focused = true }
        }
    }
}

// MARK: - Media Detail

struct MediaDetailView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    let book: Book
    @State private var showComic = false
    @State private var showReader = false
    @State private var showListen = false

    var body: some View {
        ZStack {
            AppBackdrop()

            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    header
                    meta
                    content
                    Spacer(minLength: 0)
                }
                .padding(20)
                .padding(.top, 10)
            }
            .scrollIndicators(.hidden)
        }
        .safeAreaInset(edge: .bottom) {
            actionBar
        }
        .fullScreenCover(isPresented: $showComic) {
            ComicReaderView(book: book)
        }
        .fullScreenCover(isPresented: $showReader) {
            ReaderView(book: book)
        }
        .sheet(isPresented: $showListen) {
            ListenSheet(
                book: book,
                chapterTitle: book.lastPosition,
                text: book.kind == .novel
                    ? store.chapters(for: book).flatMap(\.paragraphs).map(\.text).joined(separator: "\n")
                    : MockData.audioScript(for: book)
            )
            .presentationDetents([.large])
            .presentationCornerRadius(38)
            .themedChrome(store)
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 16) {
            BookCover(book: book, cornerRadius: 12, prominent: true)
                .frame(width: 104)

            VStack(alignment: .leading, spacing: 7) {
                Text(book.kind.rawValue)
                    .font(.system(size: 9, weight: .bold))
                    .tracking(1.6)
                    .foregroundStyle(book.kind.tint)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(book.kind.tint.opacity(0.14), in: Capsule())

                Text(book.title)
                    .font(.system(size: 24, weight: .semibold, design: .serif))
                    .foregroundStyle(Palette.text)
                    .lineLimit(2)

                Text("\(book.author) · \(book.chapterCountLabel)")
                    .font(.system(size: 12))
                    .foregroundStyle(Palette.secondary)

                Text(book.lastPosition)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Palette.jade)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var meta: some View {
        HStack(spacing: 0) {
            metaItem("进度", "\(Int(book.progress * 100))%")
            metaDivider
            metaItem("章节", book.chapterCount > 0 ? "\(book.chapterCount)" : (book.isNetworkBook ? "待加载" : "0"))
            metaDivider
            metaItem(book.kind == .audio ? "时长" : "摘录", book.kind == .audio ? (book.duration ?? "—") : "\(store.excerpts(for: book.id).count)")
        }
        .padding(.vertical, 14)
        .glassSurface(cornerRadius: 20)
    }

    private var metaDivider: some View {
        Rectangle()
            .fill(Palette.hairline)
            .frame(width: 0.6, height: 26)
    }

    private func metaItem(_ title: String, _ value: String) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(size: 17, weight: .semibold, design: .rounded))
                .foregroundStyle(Palette.text)
            Text(title)
                .font(.system(size: 10))
                .foregroundStyle(Palette.tertiary)
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private var content: some View {
        if book.kind == .comic {
            comicPreview
        } else {
            audioPreview
        }
    }

    private var comicPreview: some View {
        VStack(alignment: .leading, spacing: 11) {
            SectionHeading(text: "页面预览", trailing: "单页模式")

            ComicCoverStrip(book: book)

            Text("共 \(book.pageCount ?? 0) 页")
                .font(.system(size: 11))
                .foregroundStyle(Palette.tertiary)
        }
        .padding(16)
        .glassSurface(cornerRadius: 22)
    }

    private var audioPreview: some View {
        VStack(alignment: .leading, spacing: 13) {
            SectionHeading(text: "音轨", trailing: book.duration)

            HStack(alignment: .center, spacing: 3) {
                ForEach(0..<40, id: \.self) { index in
                    Capsule()
                        .fill(index < 14 ? Palette.accent : Palette.faint)
                        .frame(width: 3, height: CGFloat(8 + (index * 11) % 28))
                }
            }
            .frame(height: 36)

            Text("上次听到 01:12")
                .font(.system(size: 11))
                .foregroundStyle(Palette.tertiary)
        }
        .padding(16)
        .glassSurface(cornerRadius: 22)
    }

    private var actionBar: some View {
        HStack(spacing: 10) {
            Button {
                showListen = true
            } label: {
                Image(systemName: "speaker.wave.2")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(Palette.text)
                    .glassCircle(diameter: 50)
            }
            .buttonStyle(PressableStyle())

            Button {
                store.toggleFinished(book.id)
            } label: {
                Image(systemName: book.isFinished ? "checkmark.circle.fill" : "checkmark.circle")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(book.isFinished ? Palette.jade : Palette.secondary)
                    .glassCircle(diameter: 50)
            }
            .buttonStyle(PressableStyle())

            Button {
                switch book.kind {
                case .audio:
                    store.player.load(book)
                case .comic:
                    showComic = true
                case .novel:
                    showReader = true
                }
            } label: {
                HStack(spacing: 7) {
                    Image(systemName: book.kind == .audio ? "play.fill" : "book.fill")
                        .font(.system(size: 13, weight: .bold))
                    Text(book.kind == .audio ? "开始收听" : "继续阅读")
                        .font(.system(size: 15, weight: .semibold))
                }
                .foregroundStyle(Palette.onAccent)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 15)
                .background(Palette.accentSolid, in: Capsule())
            }
            .buttonStyle(PressableStyle(scale: 0.97))
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 6)
    }
}
