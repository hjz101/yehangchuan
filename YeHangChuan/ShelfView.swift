import SwiftUI

enum ShelfStatus: String, CaseIterable, Identifiable {
    case all = "全部"
    case reading = "在读"
    case finished = "已读"

    var id: String { rawValue }
}

struct ShelfView: View {
    @Environment(AppStore.self) private var store

    @State private var filter: BookKind?
    @State private var status: ShelfStatus = .all
    @State private var query = ""
    @State private var readingBook: Book?
    @State private var detailBook: Book?

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
            return kindMatches && statusMatches && queryMatches
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AppBackground()

                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        header
                        searchBar

                        if let book = store.continueBook, query.isEmpty, filter == nil, status == .all {
                            continueBand(book)
                        }

                        filterRow

                        if filteredBooks.isEmpty {
                            emptyState
                        } else {
                            grid
                        }
                    }
                    .padding(.top, 16)
                    .padding(.bottom, 112)
                }
                .scrollIndicators(.hidden)
            }
            .toolbar(.hidden, for: .navigationBar)
        }
        .fullScreenCover(item: $readingBook) { book in
            ReaderView(book: book)
        }
        .sheet(item: $detailBook) { book in
            MediaDetailView(book: book)
                .presentationDetents([.fraction(0.62)])
                .presentationDragIndicator(.visible)
        }
        .task {
            #if DEBUG
            let arguments = ProcessInfo.processInfo.arguments
            if arguments.contains("-openReader"), readingBook == nil {
                readingBook = store.books.first { $0.id == "yehangchuan" }
            }
            #endif
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline, spacing: 9) {
                Text("夜航船")
                    .font(.system(size: 32, weight: .bold, design: .serif))
                    .foregroundStyle(Theme.text)

                Text("DEMO")
                    .font(.system(size: 9, weight: .bold))
                    .tracking(1.2)
                    .foregroundStyle(Theme.accent)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .overlay {
                        RoundedRectangle(cornerRadius: 3)
                            .stroke(Theme.accent.opacity(0.5))
                    }
            }

            Text("夜读，是一次缓慢的远行")
                .font(.system(size: 13, design: .serif))
                .foregroundStyle(Theme.secondary)
        }
        .padding(.horizontal, 20)
    }

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Theme.secondary)

            TextField("搜索书名或作者", text: $query)
                .font(.system(size: 14))
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()

            if !query.isEmpty {
                Button {
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(Theme.secondary.opacity(0.7))
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 11)
        .glassSurface(cornerRadius: 16, interactive: true)
        .padding(.horizontal, 20)
    }

    private func continueBand(_ book: Book) -> some View {
        Button {
            readingBook = book
        } label: {
            HStack(alignment: .center, spacing: 14) {
                BookCover(book: book, compact: true)
                    .frame(width: 48)

                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 7) {
                Text("继续阅读")
                            .font(.system(size: 9, weight: .semibold))
                            .tracking(1.5)
                    .foregroundStyle(Theme.secondary)

                        Text(book.title)
                            .font(.system(size: 17, weight: .semibold, design: .serif))
                    .foregroundStyle(Theme.text)
                            .lineLimit(1)
                    }

                    Text("上次读到 \(book.lastPosition)")
                        .font(.system(size: 11))
                    .foregroundStyle(Theme.secondary)
                        .lineLimit(1)

                ProgressBar(
                    value: book.progress,
                    tint: Theme.accent,
                    track: Theme.secondary.opacity(0.22)
                )
                        .frame(height: 2)
                        .padding(.top, 2)
                }

                Spacer(minLength: 4)

                VStack(spacing: 4) {
                    Text("\(Int(book.progress * 100))%")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(Theme.secondary)

                    Image(systemName: "arrow.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.accent)
                }
            }
            .padding(14)
            .glassSurface(cornerRadius: 18, tint: Theme.ink.opacity(0.4), interactive: true)
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 20)
    }

    private var filterRow: some View {
        HStack(spacing: 10) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    chip("全部", selected: filter == nil) {
                        filter = nil
                    }

                    ForEach(BookKind.allCases) { kind in
                        chip(kind.rawValue, selected: filter == kind) {
                            filter = kind
                        }
                    }
                }
            }

            Menu {
                Picker("阅读状态", selection: $status) {
                    ForEach(ShelfStatus.allCases) { item in
                        Text(item.rawValue).tag(item)
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "line.3.horizontal.decrease")
                    Text(status == .all ? "筛选" : status.rawValue)
                }
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Theme.text)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .glassSurface(cornerRadius: 14, interactive: true)
            }
        }
        .padding(.horizontal, 20)
    }

    private func chip(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13, weight: selected ? .semibold : .regular))
                .foregroundStyle(Theme.text)
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .glassSurface(
                    cornerRadius: 16,
                    tint: selected ? Theme.ink.opacity(0.55) : nil,
                    interactive: true
                )
        }
        .buttonStyle(.plain)
    }

    private var grid: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 104), spacing: 16, alignment: .top)],
            alignment: .leading,
            spacing: 24
        ) {
            ForEach(filteredBooks) { book in
                BookTile(book: book)
                    .onTapGesture {
                        open(book)
                    }
                    .contextMenu {
                        Button {
                            store.toggleFinished(book.id)
                        } label: {
                            Label(book.isFinished ? "标记为未读" : "标记为已读", systemImage: "checkmark.circle")
                        }

                        Button {
                            detailBook = book
                        } label: {
                            Label("查看详情", systemImage: "info.circle")
                        }

                        Button(role: .destructive) {
                            store.removeBook(book.id)
                        } label: {
                            Label("从书架移除", systemImage: "trash")
                        }
                    }
            }
        }
        .padding(.horizontal, 20)
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "books.vertical")
                .font(.system(size: 30, weight: .light))
                .foregroundStyle(Theme.secondary.opacity(0.6))

            Text(query.isEmpty ? "这里还没有书" : "没有找到匹配的书")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Theme.text)

            Text(query.isEmpty ? "去书源页搜索并加入书架" : "换个关键词试试")
                .font(.system(size: 12))
                .foregroundStyle(Theme.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 56)
    }

    private func open(_ book: Book) {
        if book.kind == .novel {
            readingBook = book
        } else {
            detailBook = book
        }
    }
}

struct BookTile: View {
    let book: Book

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            BookCover(book: book)
                .overlay(alignment: .bottom) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(book.title)
                            .font(.system(size: 13, weight: .semibold, design: .serif))
                            .foregroundStyle(Theme.text)
                            .lineLimit(1)

                        HStack(spacing: 4) {
                            Text(book.kind == .novel ? book.author : "\(book.kind.rawValue) · \(book.author)")
                                .lineLimit(1)

                            Spacer(minLength: 0)

                            if book.progress > 0 && !book.isFinished {
                                Text("\(Int(book.progress * 100))%")
                            }
                        }
                        .font(.system(size: 10))
                        .foregroundStyle(Theme.secondary)

                        ProgressBar(
                            value: book.progress,
                            tint: Theme.accent,
                            track: Theme.secondary.opacity(0.18)
                        )
                        .opacity(book.progress > 0 && !book.isFinished ? 1 : 0)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 7)
                    .glassSurface(cornerRadius: 10, tint: Theme.ink.opacity(0.32))
                    .padding(5)
                }
        }
        .contentShape(Rectangle())
    }
}

struct MediaDetailView: View {
    let book: Book
    @State private var showDemoAlert = false

    var body: some View {
        ZStack {
            AppBackground()

            VStack(spacing: 0) {
                HStack(alignment: .top, spacing: 16) {
                    BookCover(book: book)
                        .frame(width: 96)

                    VStack(alignment: .leading, spacing: 8) {
                        Text(book.kind.rawValue)
                            .font(.system(size: 10, weight: .semibold))
                            .tracking(1.5)
                            .foregroundStyle(Theme.accent)

                        Text(book.title)
                            .font(.system(size: 23, weight: .semibold, design: .serif))
                            .foregroundStyle(Theme.text)

                        Text("\(book.author) · \(book.chapterCount) \(book.kind == .comic ? "话" : "章")")
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.secondary)

                        Text(book.lastPosition)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Theme.jade)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(20)

                Divider().overlay(Theme.hairline)

                if book.kind == .comic {
                    comicPreview
                } else {
                    audioPreview
                }

                Spacer(minLength: 12)

                Button {
                    showDemoAlert = true
                } label: {
                    Text(book.kind == .comic ? "继续阅读（演示）" : "开始播放（演示）")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Theme.text)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 13)
                        .glassSurface(cornerRadius: 16, tint: Theme.ink.opacity(0.45), interactive: true)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 18)
            }
        }
        .alert("演示版本", isPresented: $showDemoAlert) {
            Button("好", role: .cancel) {}
        } message: {
            Text(book.kind == .comic ? "漫画阅读器将在后续版本接入，这里先展示书架与入口形态。" : "音频播放器将在 v2.0 接入，这一版只展示音频书在书架中的呈现。")
        }
    }

    private var comicPreview: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeading(text: "页面预览")

            HStack(spacing: 8) {
                ForEach(0..<3, id: \.self) { index in
                    ZStack {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(index == 0 ? Color(hex: 0x2C3A48) : Color.white.opacity(0.07))

                        Image(systemName: index == 0 ? "cloud.moon" : "photo")
                            .font(.system(size: 18, weight: .light))
                            .foregroundStyle(Theme.secondary.opacity(0.7))
                    }
                    .frame(height: 92)
                }
            }

            HStack {
                Text("第 12 页 / \(book.pageCount ?? 0) 页")
                Spacer()
                Text("单页模式")
            }
            .font(.system(size: 11))
            .foregroundStyle(Theme.secondary)
        }
        .padding(20)
    }

    private var audioPreview: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeading(text: "音轨")

            HStack(alignment: .center, spacing: 3) {
                ForEach(0..<34, id: \.self) { index in
                    Capsule()
                        .fill(index < 12 ? Theme.accent : Theme.hairline)
                        .frame(width: 3, height: CGFloat(8 + (index * 7) % 26))
                }
            }
            .frame(height: 34)

            HStack {
                Text("01:12")
                Spacer()
                Text(book.duration ?? "")
            }
            .font(.system(size: 11))
            .foregroundStyle(Theme.secondary)
        }
        .padding(20)
    }
}
