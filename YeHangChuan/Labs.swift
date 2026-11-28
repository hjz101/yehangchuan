import SwiftUI
import UIKit
import LegadoCore

extension Book {
    /// 实验室功能（AI 试听、声音实验室）没有真实书籍时使用的占位书。
    /// Release 构建不带演示数据，空书架时没有书可用；直接下标取演示书会越界。
    /// 这里只提供显示用的书名，不会插入书架。
    static var labSample: Book {
        Book(
            id: "lab-sample",
            title: "夜航船",
            author: "试听",
            kind: .novel,
            coverStyle: 0,
            chapterCount: 0,
            progress: 0,
            lastPosition: "未开始",
            pageCount: nil,
            duration: nil,
            isFinished: false
        )
    }
}

// MARK: - Export

struct DataExportSheet: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var tab: ExportTab = .json
    @State private var message = ""
    @State private var fileURL: URL?
    @State private var zipURL: URL?

    enum ExportTab: String, CaseIterable, Identifiable {
        case json = "books.json"
        case notes = "notes.md"
        case annotations = "annotations.md"

        var id: String { rawValue }
    }

    private struct Payload: Codable {
        let exportedAt: Date
        let settings: ReaderSnapshot
        let books: [Book]
        let positions: [ReadingPosition]
        let bookmarks: [Bookmark]
        let excerpts: [Excerpt]
    }

    private var content: String { content(for: tab) }

    private func content(for tab: ExportTab) -> String {
        switch tab {
        case .json:
            let payload = Payload(
                exportedAt: Date(),
                settings: store.settings.snapshot,
                books: store.books,
                positions: Array(store.positions.values),
                bookmarks: store.bookmarks,
                excerpts: store.excerpts
            )
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            guard let data = try? encoder.encode(payload),
                  let text = String(data: data, encoding: .utf8) else { return "{}" }
            return text
        case .notes:
            var rows = ["# 夜航船 · 摘录与笔记", ""]
            for excerpt in store.excerpts {
                rows.append("## \(excerpt.bookTitle) · \(excerpt.chapterTitle)")
                rows.append("")
                rows.append("> \(excerpt.text)")
                if !excerpt.note.isEmpty {
                    rows.append("")
                    rows.append("**笔记**：\(excerpt.note)")
                }
                rows.append("")
            }
            return rows.joined(separator: "\n")
        case .annotations:
            var rows = ["# 夜航船 · 书签与批注", ""]
            for bookmark in store.bookmarks {
                rows.append("- **\(bookmark.bookTitle)** · \(bookmark.chapterTitle) · \(bookmark.percentLabel)")
                if !bookmark.note.isEmpty {
                    rows.append("  - \(bookmark.note)")
                }
            }
            return rows.joined(separator: "\n")
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AppBackdrop()

                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack(spacing: 10) {
                            metric("书籍", "\(store.books.count)")
                            metric("书签", "\(store.bookmarks.count)")
                            metric("摘录", "\(store.excerpts.count)")
                        }

                        GlassSegmented(
                            items: ExportTab.allCases,
                            title: { $0.rawValue },
                            selection: $tab
                        )

                        Text(content)
                            .font(.system(size: 10.5, design: .monospaced))
                            .foregroundStyle(Palette.secondary)
                            .textSelection(.enabled)
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .glassSurface(cornerRadius: 18)

                        HStack(spacing: 9) {
                            Button {
                                UIPasteboard.general.string = content
                                message = "已复制到剪贴板"
                            } label: {
                                Label("复制", systemImage: "doc.on.doc")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(Palette.text)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 12)
                                    .glassSurface(cornerRadius: 18, tint: Palette.glassTint, interactive: true)
                            }
                            .buttonStyle(PressableStyle())

                            if let fileURL {
                                ShareLink(item: fileURL) {
                                    Label("分享文件", systemImage: "square.and.arrow.up")
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundStyle(Palette.onAccent)
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 12)
                                        .background(Palette.accentSolid, in: Capsule())
                                }
                                .buttonStyle(PressableStyle())
                            }
                        }

                        Button {
                            makeZip()
                        } label: {
                            Label("打包为 ZIP（三个文件）", systemImage: "doc.zipper")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(Palette.jade)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .glassSurface(cornerRadius: 18, tint: Palette.glassTint, interactive: true)
                        }
                        .buttonStyle(PressableStyle())

                        if let zipURL {
                            ShareLink(item: zipURL) {
                                Label("分享 ZIP 包", systemImage: "square.and.arrow.up")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(Palette.onAccent)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 12)
                                    .background(Palette.accentSolid, in: Capsule())
                            }
                            .buttonStyle(PressableStyle())
                        }

                        if !message.isEmpty {
                            Text(message)
                                .font(.system(size: 10.5))
                                .foregroundStyle(Palette.tertiary)
                        }

                        Text("books.json、notes.md、annotations.md 可单独预览或复制；「打包为 ZIP」会把三份内容写成真正的 zip 文件，分享到临时目录，不修改书架数据。")
                            .font(.system(size: 10))
                            .foregroundStyle(Palette.tertiary)
                    }
                    .padding(18)
                }
                .scrollIndicators(.hidden)
            }
            .navigationTitle("导出数据")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") { dismiss() }
                        .fontWeight(.semibold)
                }
            }
            .task(id: tab) {
                let url = FileManager.default.temporaryDirectory.appendingPathComponent(tab.rawValue)
                try? content.write(to: url, atomically: true, encoding: .utf8)
                fileURL = url
            }
        }
    }

    private func makeZip() {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmm"
        let name = "夜航船-导出-\(formatter.string(from: Date())).zip"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        do {
            try ArchiveExporter.write(ExportTab.allCases.map { tab in
                ArchiveExportItem(name: tab.rawValue, data: Data(content(for: tab).utf8))
            }, to: url)
            zipURL = url
            message = "已生成 ZIP 包（含 3 个文件）"
        } catch {
            message = "打包失败：\(error.localizedDescription)"
        }
    }

    private func metric(_ title: String, _ value: String) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(size: 19, weight: .semibold, design: .rounded))
                .foregroundStyle(Palette.text)
            Text(title)
                .font(.system(size: 9.5))
                .foregroundStyle(Palette.tertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .glassSurface(cornerRadius: 18)
    }
}

// MARK: - AI studio

struct AIStudioSheet: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var provider = "自定义兼容服务"
    @State private var endpoint = "https://api.openai.com/v1"
    @State private var model = "demo-model"
    @State private var key = CredentialSettings.shared.keychain.read("ai:default") ?? ""
    @State private var showKey = false
    @State private var summary = ""
    @State private var coverIdeas: [AICoverIdea] = []
    @State private var isBusy = false
    @State private var message = ""
    @State private var showTTS = false

    struct AICoverIdea: Identifiable {
        let id = UUID()
        let name: String
        let colors: (Color, Color)
    }

    private static let coverPalette: [(Color, Color)] = [
        (Color(hex: 0x8C4A32), Color(hex: 0x2A1711)),
        (Color(hex: 0x4F7890), Color(hex: 0x132430)),
        (Color(hex: 0x3D5663), Color(hex: 0xE0CEAA)),
        (Color(hex: 0x6A5B86), Color(hex: 0x1C1830))
    ]

    private var configuration: AIConfiguration {
        AIConfiguration(
            baseURL: URL(string: endpoint.trimmingCharacters(in: .whitespaces)) ?? URL(string: "https://api.invalid")!,
            apiKey: key.trimmingCharacters(in: .whitespaces),
            model: model.trimmingCharacters(in: .whitespaces)
        )
    }

    /// 只上传当前书正文的前 4000 字，避免把整库塞给第三方服务。
    private var sourceExcerpt: String {
        guard let book = store.books.first else {
            return "夜航船靠岸时，雾还没有散。"
        }
        let text = store.chapters(for: book).flatMap(\.paragraphs).map(\.text).joined(separator: "\n")
        return String(text.prefix(4000)).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func persistKey() {
        CredentialSettings.shared.keychain.write("ai:default", key)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AppBackdrop()

                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        configCard
                        summaryCard
                        coverCard
                        ttsCard
                        boundaryNote
                    }
                    .padding(18)
                }
                .scrollIndicators(.hidden)
            }
            .navigationTitle("AI 阅读助手")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") { dismiss() }
                        .fontWeight(.semibold)
                }
            }
            .sheet(isPresented: $showTTS) {
                ListenSheet(
                    book: store.books.first ?? .labSample,
                    chapterTitle: "AI 摘要试听",
                    text: summary.isEmpty ? "夜航船在水面上缓慢前行，灯影落在书页上。" : summary
                )
                .presentationDetents([.large])
                .presentationCornerRadius(38)
                .appChrome(store)
            }
        }
    }

    private var configCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeading(text: "服务配置", trailing: "Key 存入 Keychain")

            GlassSegmented(
                items: ["自定义兼容服务", "本地服务"],
                title: { $0 },
                selection: $provider
            )
            .onChange(of: provider) { _, newValue in
                endpoint = newValue == "本地服务"
                    ? "http://127.0.0.1:11434/v1"
                    : "https://api.openai.com/v1"
            }

            TextField("兼容服务地址（含 /v1）", text: $endpoint)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .glassSurface(cornerRadius: 14)

            if provider == "本地服务" {
                Button("放行本机地址（仅本次会话）") {
                    PrivateHostAllowList.shared.update(["127.0.0.1", "localhost"])
                    message = "已放行本机地址；私网其他地址仍需单独放行"
                }
                .font(.system(size: 11))
                .foregroundStyle(Palette.jade)
            }

            HStack(spacing: 9) {
                TextField("模型", text: $model)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .glassSurface(cornerRadius: 14)

                Button {
                    showKey.toggle()
                } label: {
                    Image(systemName: showKey ? "eye.slash" : "eye")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Palette.secondary)
                        .glassCircle(diameter: 36)
                }
                .buttonStyle(PressableStyle())
            }

            Group {
                if showKey {
                    TextField("API Key（写入系统 Keychain）", text: $key)
                } else {
                    SecureField("API Key（写入系统 Keychain）", text: $key)
                }
            }
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .onChange(of: key) { _, _ in persistKey() }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .glassSurface(cornerRadius: 14)
        }
        .padding(14)
        .glassSurface(cornerRadius: 22)
    }

    private var summaryCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeading(text: "AI 摘要", trailing: "真实请求")

            if summary.isEmpty {
                Text("选择一个片段，生成 3 句话的阅读摘要与人物关系提示。")
                    .font(.system(size: 11.5))
                    .foregroundStyle(Palette.tertiary)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .glassSurface(cornerRadius: 16)
            } else {
                Text(summary)
                    .font(.system(size: 13, design: .serif))
                    .lineSpacing(5)
                    .foregroundStyle(Palette.text)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .glassSurface(cornerRadius: 16, tint: Palette.accent.opacity(0.06))
            }

            Button {
                Task { @MainActor in await generateSummary() }
            } label: {
                actionLabel("生成摘要", symbol: "sparkles", tint: Palette.accentSolid)
            }
            .buttonStyle(PressableStyle(scale: 0.97))
            .disabled(isBusy)
        }
        .padding(14)
        .glassSurface(cornerRadius: 22)
    }

    private var coverCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeading(text: "AI 封面", trailing: "\(coverIdeas.count) 个方案")

            if coverIdeas.isEmpty {
                Text("根据书名、作者与正文氛围生成竖版封面候选。")
                    .font(.system(size: 11.5))
                    .foregroundStyle(Palette.tertiary)
            } else {
                HStack(spacing: 9) {
                    ForEach(coverIdeas) { idea in
                        ZStack(alignment: .bottomLeading) {
                            LinearGradient(colors: [idea.colors.0, idea.colors.1], startPoint: .topLeading, endPoint: .bottomTrailing)
                            Text(idea.name)
                                .font(.system(size: 9, weight: .semibold, design: .serif))
                                .foregroundStyle(.white.opacity(0.9))
                                .padding(8)
                        }
                        .aspectRatio(0.71, contentMode: .fit)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                }
            }

            Button {
                Task { @MainActor in await generateCovers() }
            } label: {
                actionLabel("生成封面", symbol: "photo.on.rectangle", tint: Palette.jade)
            }
            .buttonStyle(PressableStyle(scale: 0.97))
        }
        .padding(14)
        .glassSurface(cornerRadius: 22)
    }

    private var ttsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeading(text: "AI 朗读", trailing: "系统语音真实播放")

            Text("把摘要交给系统语音试听；正式版可切换 AI TTS 服务。")
                .font(.system(size: 11.5))
                .foregroundStyle(Palette.secondary)

            Button {
                showTTS = true
            } label: {
                actionLabel("试听摘要", symbol: "speaker.wave.2", tint: Palette.gold)
            }
            .buttonStyle(PressableStyle(scale: 0.97))
        }
        .padding(14)
        .glassSurface(cornerRadius: 22)
    }

    private var boundaryNote: some View {
        VStack(alignment: .leading, spacing: 6) {
            if !message.isEmpty {
                Text(message)
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(Palette.jade)
            }
            Text("摘要与封面会向自配的兼容服务发起真实 HTTP 请求，并只上传当前书正文前 4000 字；Key 存系统 Keychain、费用自付。私网地址默认被拦截，需显式放行。试听仍用系统语音，不调用 AI TTS。")
                .font(.system(size: 10))
                .foregroundStyle(Palette.tertiary)
        }
    }

    private func generateSummary() async {
        guard !key.trimmingCharacters(in: .whitespaces).isEmpty else {
            message = "请先填写 API Key"
            return
        }
        isBusy = true
        defer { isBusy = false }
        do {
            let prompt = "请用三句话概括下面这段小说的情节与人物关系，只输出概括正文：\n\(sourceExcerpt)"
            summary = try await AIService().chat(prompt, configuration: configuration)
            message = "摘要由 \(configuration.model) 真实生成"
        } catch {
            message = "请求失败：\(error.localizedDescription)"
        }
    }

    private func generateCovers() async {
        guard !key.trimmingCharacters(in: .whitespaces).isEmpty else {
            message = "请先填写 API Key"
            return
        }
        isBusy = true
        defer { isBusy = false }
        do {
            let title = store.books.first?.title ?? "夜航船"
            let prompt = "为小说《\(title)》给出三个竖版封面方案名称，每行一个，不要编号与解释：\n\(sourceExcerpt)"
            let text = try await AIService().chat(prompt, configuration: configuration)
            let names = text.components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "-·•1234567890. ")) }
                .filter { !$0.isEmpty }
                .prefix(3)
            guard !names.isEmpty else {
                message = "服务没有返回可用的封面方案"
                return
            }
            coverIdeas = names.enumerated().map { index, name in
                AICoverIdea(name: String(name), colors: Self.coverPalette[index % Self.coverPalette.count])
            }
            message = "封面方案由 \(configuration.model) 真实生成"
        } catch {
            message = "请求失败：\(error.localizedDescription)"
        }
    }

    private func actionLabel(_ title: String, symbol: String, tint: Color) -> some View {
        Label(title, systemImage: symbol)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(Palette.onAccent)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(tint, in: Capsule())
    }
}

// MARK: - Online discovery

/// 在线发现：只用已启用书源里声明了 `exploreUrl` 的那几个真实抓取分类。
///
/// 原来的实现是伪造数据 —— 分类写死「古风 / 奇幻 / 都市」，
/// 书目来自 `MockData.searchResults`，跟书源毫无关系。
/// 现在分类从书源的 `exploreUrl` 里解析出来，书目是真发请求拿的。
struct DiscoverSheet: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var isLoading = false
    @State private var isLoadingMore = false
    @State private var entries: [CategoryEntry] = []
    @State private var selectedID: String?
    @State private var results: [DiscoverHit] = []
    @State private var errorMessage = ""
    @State private var page = 1
    @State private var hasMore = false
    @State private var loadTask: Task<Void, Never>?

    /// 一个可点开的分类：属于哪个书源、引擎是什么、分类本身。
    struct CategoryEntry: Identifiable {
        let sourceID: String
        let sourceName: String
        let engineSource: LegadoCore.BookSource
        let kind: ExploreKind

        var id: String { "\(sourceID)#\(kind.id)" }
    }

    struct DiscoverHit: Identifiable {
        let book: Book
        let sourceName: String
        var id: String { book.id }
    }

    private var enabledSources: [BookSource] { store.sources.filter(\.enabled) }

    var body: some View {
        NavigationStack {
            ZStack {
                AppBackdrop()

                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        header

                        if enabledSources.isEmpty {
                            emptyHint(
                                "没有启用的书源",
                                detail: "回到书源页启用一个支持发现的源"
                            )
                        } else if isLoading && entries.isEmpty {
                            loadingHint("正在读取书源分类…")
                        } else if entries.isEmpty {
                            emptyHint(
                                "已启用书源都没有发现分类",
                                detail: "发现需要书源配置 exploreUrl；只有搜索规则的书源不提供分类"
                            )
                        } else {
                            categoryRow

                            if isLoading {
                                loadingHint("正在抓取该分类…")
                            } else if !errorMessage.isEmpty && results.isEmpty {
                                errorCard
                            } else if results.isEmpty {
                                emptyHint("这个分类没有返回书目", detail: "可能是分类为空，或规则未命中")
                            } else {
                                ForEach(results) { hit in
                                    resultRow(hit)
                                }
                                if hasMore {
                                    loadMoreButton
                                }
                            }
                        }
                    }
                    .padding(18)
                }
                .scrollIndicators(.hidden)
            }
            .navigationTitle("在线发现")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") { dismiss() }
                        .fontWeight(.semibold)
                }
            }
            .task {
                guard entries.isEmpty else { return }
                await loadKinds()
            }
            .onDisappear { loadTask?.cancel() }
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "safari")
                .font(.system(size: 20, weight: .light))
                .foregroundStyle(Palette.jade)
                .frame(width: 40, height: 40)
                .glassCircle(diameter: 40, tint: Palette.jade.opacity(0.1))

            VStack(alignment: .leading, spacing: 3) {
                // 这里没有订阅功能，标题就别写「发现与订阅」。
                Text("在线发现")
                    .font(.system(size: 16, weight: .semibold, design: .serif))
                    .foregroundStyle(Palette.text)
                Text(subtitle)
                    .font(.system(size: 10.5))
                    .foregroundStyle(Palette.tertiary)
            }
            Spacer()
        }
        .padding(14)
        .glassSurface(cornerRadius: 22)
    }

    private var subtitle: String {
        if entries.isEmpty {
            return "读取 \(enabledSources.count) 个已启用书源的发现分类"
        }
        let sourcesWithKinds = Set(entries.map(\.sourceID)).count
        return "\(sourcesWithKinds) 个书源共 \(entries.count) 个分类 · 全部真实抓取"
    }

    private var categoryRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(entries) { entry in
                    let selected = entry.id == selectedID
                    Button {
                        selectedID = entry.id
                        Task { await load(pages: 1, reset: true) }
                    } label: {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(entry.kind.title)
                                .font(.system(size: 12, weight: selected ? .semibold : .medium))
                                .foregroundStyle(selected ? Palette.onAccent : Palette.secondary)
                            // 同名分类在不同书源里意思可能不同，标出来源。
                            Text(entry.sourceName)
                                .font(.system(size: 8.5))
                                .foregroundStyle(selected ? Palette.onAccent.opacity(0.75) : Palette.tertiary)
                        }
                        .padding(.horizontal, 13)
                        .padding(.vertical, 7)
                        .background {
                            if selected { Capsule().fill(Palette.jade) }
                        }
                        .glassCapsule(tint: selected ? nil : Palette.glassTint, interactive: true)
                    }
                    .buttonStyle(PressableStyle())
                }
            }
        }
        .scrollClipDisabled()
    }

    private func resultRow(_ hit: DiscoverHit) -> some View {
        HStack(spacing: 12) {
            BookCover(book: hit.book, cornerRadius: 8)
                .frame(width: 54)

            VStack(alignment: .leading, spacing: 3) {
                Text(hit.book.title)
                    .font(.system(size: 15, weight: .semibold, design: .serif))
                    .foregroundStyle(Palette.text)
                    .lineLimit(1)
                Text("\(hit.book.author) · \(hit.book.kind.rawValue) · \(hit.book.chapterCountLabel)")
                    .font(.system(size: 10.5))
                    .foregroundStyle(Palette.tertiary)
                Text(hit.sourceName)
                    .font(.system(size: 9.5))
                    .foregroundStyle(Palette.jade)
            }

            Spacer()

            Button {
                store.addToShelf(hit.book)
            } label: {
                Image(systemName: store.isOnShelf(hit.book.id) ? "checkmark" : "plus")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(store.isOnShelf(hit.book.id) ? Palette.jade : Palette.onAccent)
                    .frame(width: 34, height: 34)
                    .background(
                        store.isOnShelf(hit.book.id) ? Palette.jade.opacity(0.14) : Palette.accentSolid,
                        in: Circle()
                    )
            }
            .buttonStyle(PressableStyle())
            .disabled(store.isOnShelf(hit.book.id))
        }
        .padding(12)
        .glassSurface(cornerRadius: 18)
    }

    private var loadMoreButton: some View {
        Button {
            Task { await load(pages: page + 1, reset: false) }
        } label: {
            HStack(spacing: 8) {
                if isLoadingMore { ProgressView() }
                Text(isLoadingMore ? "正在加载第 \(page + 1) 页" : "加载更多")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Palette.jade)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .glassSurface(cornerRadius: 16, tint: Palette.jade.opacity(0.08), interactive: true)
        }
        .buttonStyle(PressableStyle())
        .disabled(isLoadingMore)
    }

    private var errorCard: some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 12))
                .foregroundStyle(Palette.accent)
            Text(errorMessage)
                .font(.system(size: 11))
                .foregroundStyle(Palette.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassSurface(cornerRadius: 16, tint: Palette.accent.opacity(0.06))
    }

    private func loadingHint(_ text: String) -> some View {
        HStack(spacing: 9) {
            ProgressView()
            Text(text)
                .font(.system(size: 11.5))
                .foregroundStyle(Palette.tertiary)
        }
        .padding(.top, 30)
    }

    private func emptyHint(_ title: String, detail: String) -> some View {
        VStack(spacing: 7) {
            Image(systemName: "safari")
                .font(.system(size: 24, weight: .light))
                .foregroundStyle(Palette.tertiary)
            Text(title)
                .font(.system(size: 13))
                .foregroundStyle(Palette.secondary)
            Text(detail)
                .font(.system(size: 10))
                .foregroundStyle(Palette.tertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 44)
        .padding(.horizontal, 20)
    }

    // MARK: 数据

    /// 逐个书源读分类。没有 `exploreUrl` 的源直接跳过，不算失败。
    private func loadKinds() async {
        isLoading = true
        errorMessage = ""
        var collected: [CategoryEntry] = []

        for source in enabledSources {
            guard let engineSource = LegadoBridge.engineSource(from: source) else { continue }
            let result = await store.engine.exploreKinds(source: engineSource)
            for kind in result.kinds where kind.navigableURL != nil {
                collected.append(
                    CategoryEntry(
                        sourceID: source.id,
                        sourceName: source.name,
                        engineSource: engineSource,
                        kind: kind
                    )
                )
            }
        }

        entries = collected
        isLoading = false

        guard let first = collected.first else { return }
        selectedID = first.id
        await load(pages: 1, reset: true)
    }

    /// 抓一页。`reset` 为 false 时追加，用于「加载更多」。
    private func load(pages: Int, reset: Bool) async {
        guard let entry = entries.first(where: { $0.id == selectedID }) else { return }
        if reset {
            isLoading = true
            errorMessage = ""
            results = []
            page = 1
            hasMore = false
        } else {
            isLoadingMore = true
        }

        loadTask?.cancel()
        let target = pages
        let requestedID = entry.id
        loadTask = Task { @MainActor in
            let outcome = await store.engine.explore(
                source: entry.engineSource, kind: entry.kind, page: target
            )
            guard !Task.isCancelled else { return }
            // 用户可能已经切到别的分类：这时候别把旧分类的结果写进来。
            guard selectedID == requestedID else { return }

            let mapped = outcome.books.map { book in
                DiscoverHit(
                    book: book.appBook(
                        sourceID: entry.sourceID,
                        coverStyle: StableID.coverStyle(for: book.name)
                    ),
                    sourceName: entry.sourceName
                )
            }
            let fresh: [DiscoverHit]
            if reset {
                results = mapped
                fresh = mapped
            } else {
                // 同一本书在翻页时可能重复出现，按 ID 去重。
                let existing = Set(results.map(\.id))
                fresh = mapped.filter { !existing.contains($0.id) }
                results += fresh
            }
            page = target
            // 「有没有下一页」只能看这一页有没有带来新书。
            // 原来写的是 `!mapped.isEmpty`：只要书源忽略 page 参数（很常见），
            // 每一页都会返回同样的书，这个按钮就永远点不完。
            hasMore = !fresh.isEmpty
            if let diagnostic = outcome.diagnostics.first(where: { $0.severity == .error }) {
                errorMessage = diagnostic.message
            }
            isLoading = false
            isLoadingMore = false
        }
        await loadTask?.value
    }
}

// MARK: - Voice lab

struct VoiceLabSheet: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var speed = 1.0
    @State private var carPlay = CarPlaySupport.enabled
    @State private var preferences = SpeechRolePreferences.load()

    private var voices: [SpeechVoiceOption] { VoiceCatalog.availableVoices }

    private func voiceLabel(for role: String) -> String {
        guard let id = preferences.mapping[role] else { return "系统默认" }
        return voices.first { $0.id == id }?.label ?? "系统默认"
    }

    private var demoSegments: [SpeechSegment] {
        [
            SpeechSegment(text: "夜航船靠岸的时候，雾还没有散。",
                          role: VoiceCatalog.narrator,
                          voiceIdentifier: preferences.mapping[VoiceCatalog.narrator]),
            SpeechSegment(text: "船家，劳烦靠岸。",
                          role: "卖布老人",
                          voiceIdentifier: preferences.mapping["卖布老人"]),
            SpeechSegment(text: "老人回头朝我点了点头，脚步声慢慢远去。",
                          role: VoiceCatalog.narrator,
                          voiceIdentifier: preferences.mapping[VoiceCatalog.narrator])
        ]
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AppBackdrop()

                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        previewCard
                        roleCard
                        backgroundCard
                        boundaryNote
                    }
                    .padding(18)
                }
                .scrollIndicators(.hidden)
            }
            .navigationTitle("声音实验室")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") { dismiss() }
                        .fontWeight(.semibold)
                }
            }
            .onDisappear {
                if store.speech.isPlaying { store.speech.pause() }
            }
        }
    }

    private var previewCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeading(text: "系统语音试听", trailing: store.speech.isPlaying ? "播放中" : "已暂停")

            Button {
                if !store.speech.isPlaying && !store.speech.isPaused {
                    store.speech.load(
                        book: store.books.first ?? .labSample,
                        chapterTitle: "声音实验室",
                        segments: demoSegments
                    )
                    store.speech.setSpeed(speed)
                }
                store.speech.toggle()
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: store.speech.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(Palette.onAccent)
                        .frame(width: 42, height: 42)
                        .background(Palette.accentSolid, in: Circle())

                    VStack(alignment: .leading, spacing: 3) {
                        Text("多角色段落试听")
                            .font(.system(size: 13.5, weight: .semibold))
                            .foregroundStyle(Palette.text)
                        Text("系统语音真实发声 · 进度 \(Int(store.speech.progress * 100))%")
                            .font(.system(size: 10.5))
                            .foregroundStyle(Palette.tertiary)
                    }

                    Spacer()
                }
                .padding(12)
                .glassSurface(cornerRadius: 18)
            }
            .buttonStyle(PressableStyle())

            HStack {
                Text("语速")
                    .font(.system(size: 11.5))
                    .foregroundStyle(Palette.secondary)
                Slider(value: $speed, in: 0.75...1.75, step: 0.25)
                    .tint(Palette.accent)
                    .onChange(of: speed) { _, newValue in
                        store.speech.setSpeed(newValue)
                    }
                Text(SpeedLabel.text(speed))
                    .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                    .foregroundStyle(Palette.tertiary)
                    .monospacedDigit()
            }
        }
        .padding(14)
        .glassSurface(cornerRadius: 22)
    }

    private var roleCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeading(text: "角色与声音", trailing: "\(voices.count) 种系统声线")

            VStack(spacing: 0) {
                ForEach(VoiceCatalog.roles, id: \.self) { role in
                    HStack {
                        Text(role)
                            .font(.system(size: 12.5))
                            .foregroundStyle(Palette.text)
                        Spacer()
                        Menu {
                            ForEach(voices) { voice in
                                Button(voice.label) {
                                    preferences.mapping[role] = voice.id
                                    preferences.save()
                                }
                            }
                        } label: {
                            HStack(spacing: 5) {
                                Text(voiceLabel(for: role))
                                Image(systemName: "chevron.up.chevron.down")
                                    .font(.system(size: 8, weight: .bold))
                            }
                            .font(.system(size: 11))
                            .foregroundStyle(Palette.jade)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .glassCapsule(tint: Palette.jade.opacity(0.1), interactive: true)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)

                    if role != VoiceCatalog.roles.last {
                        Rectangle()
                            .fill(Palette.hairline)
                            .frame(height: 0.6)
                            .padding(.leading, 12)
                    }
                }
            }
            .glassSurface(cornerRadius: 18)
        }
    }

    private var backgroundCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeading(text: "播放")

            VStack(alignment: .leading, spacing: 12) {
                Toggle("CarPlay", isOn: $carPlay)
                    .font(.system(size: 12.5))
                    .tint(Palette.accent)
                    .onChange(of: carPlay) { _, newValue in CarPlaySupport.enabled = newValue }

                VStack(alignment: .leading, spacing: 3) {
                    Label("后台播放与锁屏信息始终开启", systemImage: "checkmark.circle")
                        .font(.system(size: 12))
                        .foregroundStyle(Palette.secondary)
                    Text("系统语音播放会持续到锁屏与后台，锁屏显示章节与进度，并支持播放、暂停与跳转。")
                        .font(.system(size: 10))
                        .foregroundStyle(Palette.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Label("音频缓存不存在", systemImage: "minus.circle")
                        .font(.system(size: 12))
                        .foregroundStyle(Palette.secondary)
                    Text("系统语音不产生音频文件；有声书播放的是你导入的本机音频。")
                        .font(.system(size: 10))
                        .foregroundStyle(Palette.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(12)
            .glassSurface(cornerRadius: 18)
        }
    }

    private var boundaryNote: some View {
        Text("系统语音真实发声，各角色切换系统已安装的真实声线，映射保存在本机；对话切分基于引号的启发式规则，不是语义分析。后台播放与锁屏信息随系统语音播放自动生效，没有单独开关。CarPlay 开关控制真实场景是否挂载；车机显示依赖设备已配对且工程开启 CarPlay capability。")
            .font(.system(size: 10))
            .foregroundStyle(Palette.tertiary)
    }
}

// MARK: - Compliance

struct ComplianceSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                AppBackdrop()

                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        infoCard(
                            "内容来源",
                            "App 不提供内容、不预装书源、不抓取未经用户配置的站点。请只导入你有权阅读的内容。"
                        )
                        infoCard(
                            "书源与 JS",
                            "书源默认关闭。启用前提示权限与私网风险；JS 书源仅在 TestFlight / 自签版本提供，违反 App Store 2.5.2。"
                        )
                        infoCard(
                            "隐私",
                            "书籍、脚本与 AI Key 留在本机；演示版不接入第三方分析 SDK。iCloud 仅同步轻量元数据。"
                        )
                        infoCard(
                            "段评",
                            "段评来自书源，只读展示，不提供发表、点赞或举报入口；命中本地词表的内容会隐藏。"
                        )
                        infoCard(
                            "分发",
                            "App 免费，无内购。安装方式为 TestFlight（≤1 万人）或自签，构建有效期约 90 天，需重新签名。"
                        )
                    }
                    .padding(18)
                }
                .scrollIndicators(.hidden)
            }
            .navigationTitle("隐私与内容来源")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") { dismiss() }
                        .fontWeight(.semibold)
                }
            }
        }
    }

    private func infoCard(_ title: String, _ body: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.system(size: 13.5, weight: .semibold, design: .serif))
                .foregroundStyle(Palette.text)
            Text(body)
                .font(.system(size: 11.5))
                .lineSpacing(3)
                .foregroundStyle(Palette.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassSurface(cornerRadius: 20)
    }
}
