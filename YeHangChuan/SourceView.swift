import SwiftUI
import UIKit
import UniformTypeIdentifiers
import LegadoCore

struct SourceView: View {
    @Environment(AppStore.self) private var store

    @State private var showAddSource = false
    @State private var showSearch = false
    @State private var showImportExport = false
    @State private var showLogs = false
    @State private var detailSource: BookSource?
    @State private var enablePrompt: SourceEnablePrompt?

    private var enabledCount: Int {
        store.sources.filter(\.enabled).count
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AppBackdrop()

                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 20) {
                        summaryCard
                        searchEntry
                        sourceSection
                        footerNote
                    }
                    .padding(.horizontal, 18)
                    .padding(.top, 6)
                    .padding(.bottom, 40)
                }
                .scrollIndicators(.hidden)
            }
            .navigationTitle("书源")
            .navigationSubtitle("\(store.sources.count) 个书源 · \(enabledCount) 个已启用")
            .toolbarTitleDisplayMode(.inlineLarge)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button {
                            showAddSource = true
                        } label: {
                            Label("新建书源", systemImage: "plus")
                        }

                        Button {
                            showImportExport = true
                        } label: {
                            Label("导入 / 导出", systemImage: "arrow.up.arrow.down")
                        }

                        Button {
                            showLogs = true
                        } label: {
                            Label("网络日志", systemImage: "list.bullet.rectangle")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .accessibilityLabel("书源操作")
                }
            }
        }
        .sheet(isPresented: $showAddSource) {
            AddSourceSheet()
                .presentationDetents([.large])
                .presentationCornerRadius(38)
                .themedChrome(store)
        }
        .sheet(isPresented: $showSearch) {
            SourceSearchSheet()
                .presentationDetents([.large])
                .presentationCornerRadius(38)
                .themedChrome(store)
        }
        .sheet(isPresented: $showImportExport) {
            SourceImportExportSheet()
                .presentationDetents([.large])
                .presentationCornerRadius(38)
                .themedChrome(store)
        }
        .sheet(isPresented: $showLogs) {
            NetworkLogSheet()
                .presentationDetents([.medium, .large])
                .presentationCornerRadius(38)
                .themedChrome(store)
        }
        .sheet(item: $detailSource) { source in
            SourceDetailSheet(source: source)
                .presentationDetents([.large])
                .presentationCornerRadius(38)
                .themedChrome(store)
        }
        .alert(item: $enablePrompt) { prompt in
            switch prompt {
            case .permission(let source):
                Alert(
                    title: Text("启用书源风险提示"),
                    message: Text("书源由你自行提供。启用后可发起网络请求并解析网页，App 不预装、不推荐任何站点。私网地址默认拒绝。"),
                    primaryButton: .default(Text("继续")) {
                        if Self.isPrivateHost(source.host) {
                            enablePrompt = .privateNetwork(source)
                        } else {
                            store.setSourceEnabled(source.id, enabled: true)
                        }
                    },
                    secondaryButton: .cancel(Text("取消"))
                )
            case .privateNetwork(let source):
                Alert(
                    title: Text("私网地址已拦截"),
                    message: Text("\(source.host) 属于本机或局域网地址，默认拒绝访问。仅在明确知道风险时手动放行。"),
                    primaryButton: .destructive(Text("仍然启用")) {
                        store.setSourceEnabled(source.id, enabled: true)
                    },
                    secondaryButton: .cancel(Text("取消"))
                )
            }
        }
        .task {
            #if DEBUG
            let arguments = ProcessInfo.processInfo.arguments
            if arguments.contains("-showSearch") {
                showSearch = true
            } else if arguments.contains("-showAddSource") {
                showAddSource = true
            } else if arguments.contains("-showSourceImport") {
                showImportExport = true
            } else if arguments.contains("-showSourceDetail"), let source = store.sources.first {
                detailSource = source
            } else if arguments.contains("-openSourceImport") {
                showImportExport = true
            } else if arguments.contains("-openSourceDetail"), let source = store.sources.first {
                detailSource = source
            }
            #endif
        }
    }

    // MARK: Summary

    private var summaryCard: some View {
        HStack(spacing: 16) {
            ZStack {
                RingProgress(
                    value: store.sources.isEmpty ? 0 : Double(enabledCount) / Double(store.sources.count),
                    lineWidth: 7,
                    tint: Palette.jade,
                    label: "\(enabledCount)",
                    caption: "启用"
                )
            }
            .frame(width: 66, height: 66)

            VStack(alignment: .leading, spacing: 5) {
                Text("书源池")
                    .font(.system(size: 16, weight: .semibold, design: .serif))
                    .foregroundStyle(Palette.text)

                // 这里原来写「可检索 N 本」，N 是所有书源 bookCount 的累加。
                // 但 bookCount 只是演示时写死的数字，真实引擎从不知道也不算这个数，
                // 所以改成能如实反映的：书源总数与已启用数。
                Text("共 \(store.sources.count) 个书源，\(enabledCount) 个已启用")
                    .font(.system(size: 11.5))
                    .foregroundStyle(Palette.secondary)

                HStack(spacing: 6) {
                    ForEach(SourceKind.allCases, id: \.self) { kind in
                        let count = store.sources.filter { $0.kind == kind }.count
                        if count > 0 {
                            Text("\(kind.rawValue) \(count)")
                                .font(.system(size: 9.5, weight: .semibold))
                                .foregroundStyle(Palette.tertiary)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 3)
                                .glassCapsule(tint: Palette.glassTint)
                        }
                    }
                }
                .padding(.top, 1)
            }

            Spacer(minLength: 0)
        }
        .padding(16)
        .glassSurface(cornerRadius: 26)
    }

    // MARK: Search entry

    private var searchEntry: some View {
        Button {
            showSearch = true
        } label: {
            HStack(spacing: 13) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Palette.onAccent)
                    .frame(width: 40, height: 40)
                    .background(Palette.accentSolid, in: RoundedRectangle(cornerRadius: 13, style: .continuous))

                VStack(alignment: .leading, spacing: 2) {
                    Text("搜索并加入书架")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Palette.text)

                    Text(enabledCount > 0 ? "在已启用的书源中检索" : "先启用一个书源")
                        .font(.system(size: 11))
                        .foregroundStyle(Palette.secondary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Palette.tertiary.opacity(0.6))
            }
            .padding(14)
            .glassSurface(cornerRadius: 24, tint: Palette.accent.opacity(0.08), interactive: true)
            .contentShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        }
        .buttonStyle(PressableStyle(scale: 0.985))
    }

    // MARK: Sources

    private var sourceSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeading(text: "我的书源", trailing: "\(store.sources.count)")

            VStack(spacing: 8) {
                ForEach(store.sources) { source in
                    SourceRow(
                        source: source,
                        onToggle: { enabled in
                            if enabled {
                                enablePrompt = .permission(source)
                            } else {
                                store.setSourceEnabled(source.id, enabled: false)
                            }
                        },
                        onOpen: {
                            detailSource = source
                        }
                    )
                    .contextMenu {
                        Button(role: .destructive) {
                            store.removeSource(source.id)
                        } label: {
                            Label("删除书源", systemImage: "trash")
                        }
                    }
                }

                if store.sources.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "antenna.radiowaves.left.and.right.slash")
                            .font(.system(size: 22, weight: .light))
                            .foregroundStyle(Palette.tertiary)
                        Text("还没有书源")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(Palette.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 34)
                    .glassSurface(cornerRadius: 22)
                }
            }
        }
    }

    private var footerNote: some View {
        Text("书源默认关闭；启用前会提示权限与私网风险。已启用书源的检索、目录与正文会真实联网，私网地址默认拦截。")
            .font(.system(size: 10.5))
            .foregroundStyle(Palette.tertiary)
            .padding(.horizontal, 2)
            .padding(.top, 2)
    }

    static func isPrivateHost(_ host: String) -> Bool {
        URLHost.isPrivate(host)
    }
}

enum SourceEnablePrompt: Identifiable {
    case permission(BookSource)
    case privateNetwork(BookSource)

    var id: String {
        switch self {
        case .permission(let source): "permission-\(source.id)"
        case .privateNetwork(let source): "private-\(source.id)"
        }
    }
}

struct SourceRow: View {
    let source: BookSource
    let onToggle: (Bool) -> Void
    var onOpen: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: source.enabled
                                ? [Palette.jade.opacity(0.9), Palette.jade.opacity(0.55)]
                                : [Palette.faint, Palette.faint],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 42, height: 42)

                Image(systemName: source.kind == .js ? "curlybraces" : "doc.text")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(source.enabled ? .white : Palette.tertiary)
            }

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(source.name)
                        .font(.system(size: 14.5, weight: .medium))
                        .foregroundStyle(Palette.text)
                        .lineLimit(1)

                    Text(source.kind.rawValue)
                        .font(.system(size: 8.5, weight: .bold))
                        .tracking(0.4)
                        .foregroundStyle(Palette.accent)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Palette.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 4, style: .continuous))
                }

                // 原来这里写「N 本」，那个 N 来自演示数据里写死的 bookCount，
                // 与真实书源无关。改成书源自己的分组，是真实字段。
                Text("\(source.host) · \(source.group)")
                    .font(.system(size: 10.5))
                    .foregroundStyle(Palette.tertiary)
                    .lineLimit(1)

                HStack(spacing: 5) {
                    Text(source.login.rawValue)
                        .foregroundStyle(source.login == .expired ? Palette.accent : Palette.tertiary)

                    if let latency = source.latency {
                        Text("· \(latency) ms")
                            .foregroundStyle(Palette.jade)
                    }

                    if source.lastError != nil {
                        Text("· 异常")
                            .foregroundStyle(Palette.accent)
                    }
                }
                .font(.system(size: 9.5, weight: .medium))
            }

            Spacer(minLength: 6)

            Toggle(
                "",
                isOn: Binding(get: { source.enabled }, set: onToggle)
            )
            .labelsHidden()
            .tint(Palette.jade)
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 11)
        .glassSurface(
            cornerRadius: 20,
            tint: source.enabled ? nil : .black.opacity(0.06)
        )
        .contentShape(Rectangle())
        .onTapGesture { onOpen?() }
    }
}

// MARK: - Add Source

struct AddSourceSheet: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var name = "我的书源"
    @State private var kind: SourceKind = .json
    @State private var config = """
    {
      "name": "我的书源",
      "search": "https://example.com/search?q={kw}",
      "chapter": "https://example.com/chapter/{id}"
    }
    """

    private let presets: [(String, String, SourceKind)] = [
        ("示例书源", "demo.example.com", .json),
        ("自建脚本源", "script.local", .js),
        ("离线书架", "local.library", .json)
    ]

    var body: some View {
        NavigationStack {
            ZStack {
                AppBackdrop()

                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        nameField
                        kindPicker
                        presetRow
                        configEditor
                    }
                    .padding(18)
                }
                .scrollIndicators(.hidden)
            }
            .navigationTitle("添加书源")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("取消") { dismiss() }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button("添加") {
                        store.addSource(
                            name: name,
                            kind: LegadoBridge.detectedKind(ruleJSON: config) ?? kind,
                            host: hostFromConfig,
                            rule: config
                        )
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }

    private var nameField: some View {
        VStack(alignment: .leading, spacing: 9) {
            SectionHeading(text: "名称")

            TextField("书源名称", text: $name)
                .font(.system(size: 15))
                .foregroundStyle(Palette.text)
                .padding(.horizontal, 14)
                .padding(.vertical, 13)
                .glassSurface(cornerRadius: 18)
        }
    }

    private var kindPicker: some View {
        VStack(alignment: .leading, spacing: 9) {
            SectionHeading(text: "规则类型")

            GlassSegmented(
                items: [SourceKind.json, SourceKind.js],
                title: { $0 == .json ? "选择器规则" : "含 JS 脚本" },
                selection: $kind
            )
            .onChange(of: kind) { _, newKind in
                config = template(for: newKind)
            }

            Text(kind == .js
                 ? "规则里含 @js: 或 jsLib，运行时在 JavaScriptCore 中执行。"
                 : "规则用 CSS 选择器、JSONPath 或正则表达式提取字段。")
                .font(.system(size: 10))
                .foregroundStyle(Palette.tertiary)
        }
    }

    private var presetRow: some View {
        VStack(alignment: .leading, spacing: 9) {
            SectionHeading(text: "快速填充")

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(presets, id: \.0) { preset in
                        Button {
                            name = preset.0
                            kind = preset.2
                            config = template(for: preset.2)
                        } label: {
                            Text(preset.0)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(Palette.text)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .glassCapsule(tint: Palette.glassTint, interactive: true)
                        }
                        .buttonStyle(PressableStyle())
                    }
                }
                .padding(.vertical, 2)
            }
            .scrollClipDisabled()
        }
    }

    private var configEditor: some View {
        VStack(alignment: .leading, spacing: 9) {
            SectionHeading(text: "配置")

            TextEditor(text: $config)
                .font(.system(size: 11.5, design: .monospaced))
                .foregroundStyle(Palette.secondary)
                .scrollContentBackground(.hidden)
                .padding(10)
                .frame(height: 200)
                .glassSurface(cornerRadius: 20)
        }
    }

    /// 从配置 JSON 里读书源地址。
    /// Legado 3.0 的字段是 `bookSourceUrl`；也兼容 `host` 与 `searchUrl`。
    /// 多域名写法（逗号分隔）取第一个，完整的原串仍会随规则一起保存。
    private var hostFromConfig: String {
        guard let data = config.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return ""
        }
        let raw = (object["bookSourceUrl"] ?? object["host"] ?? object["searchUrl"] ?? object["search"]) as? String ?? ""
        return BookSource.splitHosts(raw).first ?? ""
    }

    /// 模板必须是能直接跑的 Legado 3.0 书源，否则添加完仍然搜不到书。
    private func template(for kind: SourceKind) -> String {
        switch kind {
        case .json:
            """
            {
              "bookSourceName": "我的书源",
              "bookSourceUrl": "https://www.example.com",
              "bookSourceGroup": "自建",
              "bookSourceType": 0,
              "enabled": false,
              "searchUrl": "https://www.example.com/search?q={{key}}",
              "ruleSearch": {
                "bookList": "class.result-list@tag.li",
                "name": "tag.h3@text",
                "author": "class.author@text",
                "bookUrl": "tag.a@href",
                "intro": "class.intro@text",
                "lastChapter": "class.last@text"
              },
              "ruleBookInfo": {
                "name": "tag.h1@text",
                "author": "id.info@tag.p.1@text",
                "tocUrl": "id.list@tag.a@href"
              },
              "ruleToc": {
                "chapterList": "id.list@tag.li",
                "chapterName": "tag.a@text",
                "chapterUrl": "tag.a@href"
              },
              "ruleContent": {
                "content": "id.content@html"
              }
            }
            """
        case .js:
            """
            {
              "bookSourceName": "我的脚本源",
              "bookSourceUrl": "https://api.example.com",
              "bookSourceGroup": "自建",
              "bookSourceType": 0,
              "enabled": false,
              "searchUrl": "https://api.example.com/search?q={{key}}&page={{page}}",
              "ruleSearch": {
                "bookList": "$.data[*]",
                "name": "$.title",
                "author": "$.author",
                "bookUrl": "$.url",
                "coverUrl": "$.cover"
              },
              "ruleToc": {
                "chapterList": "$.chapters[*]",
                "chapterName": "$.title",
                "chapterUrl": "$.url"
              },
              "ruleContent": {
                "content": "@js:JSON.parse(result).content"
              }
            }
            """
        }
    }
}

// MARK: - Source Search

struct SourceSearchSheet: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var query = ""
    @State private var selectedSourceID: String?
    @State private var isSearching = false
    @State private var hitsBySource: [String: Int] = [:]
    @State private var searchTask: Task<Void, Never>?
    /// 真实检索结果，按书源逐条到达。
    @State private var results: [SourceHit] = []
    /// 每个书源的失败原因，界面上要能看见，而不是静默空结果。
    @State private var sourceErrors: [String: String] = [:]
    @State private var searchedKeyword = ""

    /// 检索结果 + 它来自哪个书源。同一本书可能在多个源都有，
    /// 加书架时需要知道用哪个源，所以不能合并成一个 `Book`。
    struct SourceHit: Identifiable {
        let book: Book
        let sourceID: String
        let sourceName: String
        var id: String { "\(sourceID)#\(book.id)" }
    }

    private var enabledSources: [BookSource] {
        store.sources.filter(\.enabled)
    }

    private var enabledCount: Int { enabledSources.count }

    var body: some View {
        NavigationStack {
            ZStack {
                AppBackdrop()

                VStack(spacing: 0) {
                    searchField
                        .padding(.horizontal, 18)
                        .padding(.top, 6)

                    if enabledSources.isEmpty {
                        ContentUnavailableView(
                            "没有启用的书源",
                            systemImage: "antenna.radiowaves.left.and.right.slash",
                            description: Text("回到书源页启用一个书源后再搜索")
                        )
                        .frame(maxHeight: .infinity)
                    } else {
                        sourcePicker
                            .padding(.top, 12)

                        ScrollView {
                            VStack(spacing: 9) {
                                if !isSearching && !searchedKeyword.isEmpty {
                                    HStack(spacing: 5) {
                                        Image(systemName: "antenna.radiowaves.left.and.right")
                                        Text("并发检索 \(enabledCount) 个书源 · \(results.count) 条结果")
                                    }
                                    .font(.system(size: 9.5, weight: .medium))
                                    .foregroundStyle(Palette.tertiary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.bottom, 2)
                                }

                                if isSearching {
                                    searchingState
                                } else if results.isEmpty {
                                    emptyState
                                } else {
                                    ForEach(results) { hit in
                                        SearchResultRow(book: hit.book, sources: [hit.sourceName])
                                    }
                                }

                                if !sourceErrors.isEmpty {
                                    errorSection
                                }
                            }
                            .padding(.horizontal, 18)
                            .padding(.top, 12)
                            .padding(.bottom, 28)
                        }
                        .scrollIndicators(.hidden)
                    }
                }
            }
            .navigationTitle("搜索")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") { dismiss() }
                        .fontWeight(.semibold)
                }
            }
            .onAppear {
                selectedSourceID = enabledSources.first?.id
            }
            .onChange(of: query) { _, _ in
                runSearch()
            }
            .onDisappear { searchTask?.cancel() }
        }
    }

    /// 真实检索：把已启用书源翻译成引擎书源，交给 LegadoCore 并发抓取。
    /// 规则解析不了的源会单独列出原因，而不是假装没搜到。
    private func runSearch() {
        searchTask?.cancel()
        let keyword = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !keyword.isEmpty, !enabledSources.isEmpty else {
            results = []
            sourceErrors = [:]
            searchedKeyword = ""
            isSearching = false
            return
        }

        isSearching = true
        searchedKeyword = keyword
        results = []
        sourceErrors = [:]

        searchTask = Task { @MainActor in
            // 输入停下来再发请求，避免每敲一个字就打一次网络。
            try? await Task.sleep(for: .milliseconds(420))
            guard !Task.isCancelled else { return }

            var engineSources: [LegadoCore.BookSource] = []
            for source in enabledSources {
                if let engine = LegadoBridge.engineSource(from: source) {
                    engineSources.append(engine)
                } else {
                    sourceErrors[source.name] = "规则无法解析成 Legado 书源"
                }
            }

            guard !engineSources.isEmpty else {
                isSearching = false
                return
            }

            let collected = await store.engine.search(keyword: keyword, sources: engineSources) { outcome in
                let sourceName = engineSources.first { $0.id == outcome.sourceID }?.bookSourceName ?? outcome.sourceID
                if let message = outcome.diagnostics.first(where: { $0.severity == .error })?.message {
                    sourceErrors[sourceName] = message
                }
                for book in outcome.books {
                    // 书源 ID 用界面侧的，加书架时才能找回来。
                    let appSourceID = enabledSources.first { $0.host == outcome.sourceID || $0.id == outcome.sourceID }?.id
                        ?? LegadoBridge.appSourceID(engineID: outcome.sourceID, in: enabledSources)
                        ?? outcome.sourceID
                    withAnimation(.easeOut(duration: 0.18)) {
                        results.append(
                            SourceHit(
                                book: book.appBook(sourceID: appSourceID, coverStyle: StableID.coverStyle(for: book.name)),
                                sourceID: appSourceID,
                                sourceName: sourceName
                            )
                        )
                    }
                }
            }
            hitsBySource = Dictionary(grouping: collected, by: \.sourceID).mapValues(\.count)
            withAnimation(.easeOut(duration: 0.2)) { isSearching = false }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: searchedKeyword.isEmpty ? "magnifyingglass" : "text.magnifyingglass")
                .font(.system(size: 24, weight: .light))
                .foregroundStyle(Palette.tertiary)
            Text(searchedKeyword.isEmpty ? "输入书名或作者开始检索" : "没有匹配的结果")
                .font(.system(size: 13))
                .foregroundStyle(Palette.secondary)
            if !searchedKeyword.isEmpty && sourceErrors.isEmpty {
                Text("检索真实网络请求，速度取决于书源站点")
                    .font(.system(size: 10))
                    .foregroundStyle(Palette.tertiary)
            }
        }
        .padding(.top, 48)
    }

    private var errorSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("以下书源没有返回结果")
                .font(.system(size: 9.5, weight: .medium))
                .foregroundStyle(Palette.tertiary)

            ForEach(Array(sourceErrors.keys.sorted()), id: \.self) { name in
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 9))
                        .foregroundStyle(Palette.accent)
                    Text(name)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(Palette.secondary)
                    Text(sourceErrors[name] ?? "")
                        .font(.system(size: 9.5))
                        .foregroundStyle(Palette.tertiary)
                        .lineLimit(2)
                    Spacer(minLength: 0)
                }
            }
        }
        .padding(11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassSurface(cornerRadius: 14, tint: Palette.accent.opacity(0.06))
    }

    private var searchingState: some View {
        VStack(spacing: 10) {
            ProgressView().themedProgress()
            Text("正在检索书源…")
                .font(.system(size: 12))
                .foregroundStyle(Palette.tertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 50)
    }

    private var searchField: some View {
        HStack(spacing: 9) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Palette.tertiary)

            TextField("输入书名或作者", text: $query)
                .font(.system(size: 14))
                .foregroundStyle(Palette.text)
                .autocorrectionDisabled()

            if !query.isEmpty {
                Button {
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(Palette.tertiary.opacity(0.7))
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .glassSurface(cornerRadius: 20, interactive: true)
    }

    private var sourcePicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(enabledSources) { source in
                    let selected = selectedSourceID == source.id
                    Button {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                            selectedSourceID = source.id
                        }
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: source.kind == .js ? "curlybraces" : "doc.text")
                                .font(.system(size: 10, weight: .semibold))
                            Text(source.name)
                        }
                        .font(.system(size: 11.5, weight: selected ? .semibold : .medium))
                        .foregroundStyle(selected ? Palette.onAccent : Palette.secondary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background {
                            if selected {
                                Capsule().fill(Palette.jade)
                            }
                        }
                        .glassCapsule(tint: selected ? nil : Palette.glassTint, interactive: true)
                        .contentShape(Capsule())
                    }
                    .buttonStyle(PressableStyle())
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 2)
        }
        .scrollClipDisabled()
    }
}

struct SearchResultRow: View {
    @Environment(AppStore.self) private var store

    let book: Book
    var sources: [String] = ["示例书源"]

    private var added: Bool { store.isOnShelf(book.id) }

    var body: some View {
        HStack(spacing: 12) {
            BookCover(book: book, cornerRadius: 8)
                .frame(width: 50)

            VStack(alignment: .leading, spacing: 4) {
                Text(book.title)
                    .font(.system(size: 15, weight: .semibold, design: .serif))
                    .foregroundStyle(Palette.text)
                    .lineLimit(1)

                Text("\(book.author) · \(book.kind.rawValue) · \(book.chapterCountLabel)")
                    .font(.system(size: 10.5))
                    .foregroundStyle(Palette.tertiary)
                    .lineLimit(1)

                HStack(spacing: 4) {
                    Image(systemName: "checkmark.seal")
                        .font(.system(size: 8.5))
                    Text(sources.isEmpty ? "本地书源" : sources.joined(separator: " · "))
                        .font(.system(size: 9.5))
                        .lineLimit(1)
                }
                .foregroundStyle(Palette.jade.opacity(0.85))
            }

            Spacer(minLength: 4)

            Button {
                store.addToShelf(book)
            } label: {
                Image(systemName: added ? "checkmark" : "plus")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(added ? Palette.jade : Palette.onAccent)
                    .frame(width: 32, height: 32)
                    .background(added ? Palette.jade.opacity(0.16) : Palette.accentSolid, in: Circle())
            }
            .buttonStyle(PressableStyle())
            .disabled(added)
            .accessibilityLabel(added ? "已在书架" : "加入书架")
        }
        .padding(11)
        .glassSurface(cornerRadius: 20)
    }
}

// MARK: - Source Detail

struct SourceDetailSheet: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    private var hasLoginScript: Bool {
        LegadoBridge.engineSource(from: source).map { store.engine.hasLoginScript(source: $0) } ?? false
    }

    @State private var source: BookSource
    @State private var probe: SourceProbe?
    @State private var debugLines: [DebugLine] = []
    @State private var report: [SourceProbe] = []
    @State private var isBusy = false
    @State private var ruleMessage = ""
    @State private var enableWarning = ""
    /// 取消过就不再回写，避免「点了取消却仍然被保存」。
    /// 手势下滑关闭没有按钮可点，仍按「保存」处理。
    @State private var cancelled = false

    init(source: BookSource) {
        _source = State(initialValue: source)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AppBackdrop()

                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        header
                        actionRow

                        if let probe {
                            probeCard(probe)
                        }

                        rulesSection
                        loginSection
                        debugSection

                        if !report.isEmpty {
                            batchSection
                        }
                    }
                    .padding(18)
                }
                .scrollIndicators(.hidden)
            }
            .navigationTitle("书源详情")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("取消") {
                        cancelled = true
                        dismiss()
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("保存") {
                        store.updateSource(source)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
            // 下滑关闭时没有「保存」按钮，按保存处理；点了取消则不回写。
            .onDisappear {
                guard !cancelled else { return }
                store.updateSource(source)
            }
        }
    }

    private var header: some View {
        HStack(spacing: 14) {
            Image(systemName: source.kind == .js ? "curlybraces" : "doc.text")
                .font(.system(size: 21, weight: .semibold))
                .foregroundStyle(Palette.jade)
                .frame(width: 52, height: 52)
                .background(Palette.jade.opacity(0.12), in: RoundedRectangle(cornerRadius: 16, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                Text(source.name)
                    .font(.system(size: 19, weight: .semibold, design: .serif))
                    .foregroundStyle(Palette.text)

                Text("\(source.host) · \(source.kind.rawValue) · \(source.group)")
                    .font(.system(size: 10.5))
                    .foregroundStyle(Palette.tertiary)
                    .lineLimit(1)

                Text(source.login.rawValue)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(source.login == .expired ? Palette.accent : Palette.jade)
            }

            Spacer()

            Toggle("", isOn: Binding(
                get: { source.enabled },
                set: { enabled in
                    if enabled && SourceView.isPrivateHost(source.host) {
                        source.enabled = false
                        enableWarning = "私网地址默认拒绝，请在列表页显式放行"
                    } else {
                        source.enabled = enabled
                        enableWarning = enabled ? "已启用，请确认你信任该来源" : ""
                    }
                }
            ))
                .labelsHidden()
                .tint(Palette.jade)
        }
        .padding(14)
        .glassSurface(cornerRadius: 24)
        .overlay(alignment: .bottomLeading) {
            if !enableWarning.isEmpty {
                Text(enableWarning)
                    .font(.system(size: 9.5))
                    .foregroundStyle(Palette.accent)
                    .padding(.horizontal, 15)
                    .offset(y: 12)
            }
        }
    }

    private var actionRow: some View {
        HStack(spacing: 9) {
            actionCard("测试连接", symbol: "bolt.horizontal", tint: Palette.jade) {
                isBusy = true
                Task { @MainActor in
                    guard let engineSource = LegadoBridge.engineSource(from: source) else {
                        probe = SourceProbe(
                            id: source.id,
                            name: source.name,
                            ok: false,
                            milliseconds: 0,
                            message: "规则无法解析成 Legado 书源"
                        )
                        isBusy = false
                        return
                    }
                    let result = await store.engine.probe(source: engineSource)
                    probe = SourceProbe(
                        id: source.id,
                        name: source.name,
                        ok: result.ok,
                        milliseconds: result.milliseconds,
                        message: result.message
                    )
                    source.latency = result.milliseconds
                    source.lastError = result.ok ? nil : result.message
                    store.updateSource(source)
                    isBusy = false
                }
            }

            actionCard("批量测试", symbol: "checklist", tint: Palette.gold) {
                isBusy = true
                Task { @MainActor in
                    // 并发探测，但每个源内部只发一次最小请求。
                    var collected: [SourceProbe] = []
                    await withTaskGroup(of: SourceProbe.self) { group in
                        for item in store.sources {
                            group.addTask { @MainActor in
                                guard let engineSource = LegadoBridge.engineSource(from: item) else {
                                    return SourceProbe(
                                        id: item.id, name: item.name, ok: false,
                                        milliseconds: 0, message: "规则无法解析"
                                    )
                                }
                                let result = await store.engine.probe(source: engineSource)
                                return SourceProbe(
                                    id: item.id, name: item.name, ok: result.ok,
                                    milliseconds: result.milliseconds, message: result.message
                                )
                            }
                        }
                        for await probe in group { collected.append(probe) }
                    }
                    report = collected.sorted { $0.milliseconds < $1.milliseconds }
                    isBusy = false
                }
            }

            actionCard("运行调试", symbol: "ladybug", tint: Palette.accent) {
                isBusy = true
                Task { @MainActor in
                    guard let engineSource = LegadoBridge.engineSource(from: source) else {
                        debugLines = [
                            DebugLine(step: "配置", detail: "规则无法解析成 Legado 书源", ok: false, milliseconds: 0)
                        ]
                        isBusy = false
                        return
                    }
                    let result = await store.engine.debug(source: engineSource, keyword: "长风")
                    // 引擎的五步调试直接映射成界面上的日志行。
                    debugLines = result.steps.map { step in
                        DebugLine(
                            step: step.stage.title,
                            detail: step.summary,
                            ok: step.status == .passed || step.status == .warning,
                            milliseconds: step.elapsedMilliseconds
                        )
                    }
                    isBusy = false
                }
            }
        }
    }

    private func actionCard(_ title: String, symbol: String, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: symbol)
                    .font(.system(size: 16, weight: .semibold))
                Text(title)
                    .font(.system(size: 10.5, weight: .medium))
            }
            .foregroundStyle(tint)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 13)
            .glassSurface(cornerRadius: 18, tint: tint.opacity(0.08), interactive: true)
        }
        .buttonStyle(PressableStyle())
        .disabled(isBusy)
    }

    private func probeCard(_ probe: SourceProbe) -> some View {
        HStack(spacing: 10) {
            Image(systemName: probe.ok ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .font(.system(size: 16))
                .foregroundStyle(probe.ok ? Palette.jade : Palette.accent)

            VStack(alignment: .leading, spacing: 2) {
                Text(probe.ok ? "连接正常 · \(probe.milliseconds) ms" : "连接异常 · \(probe.milliseconds) ms")
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(Palette.text)
                Text(probe.message)
                    .font(.system(size: 10.5))
                    .foregroundStyle(Palette.secondary)
            }

            Spacer()

            if isBusy { ProgressView().themedProgress() }
        }
        .padding(13)
        .glassSurface(cornerRadius: 18)
    }

    private var rulesSection: some View {
        VStack(alignment: .leading, spacing: 9) {
            SectionHeading(text: "解析规则", trailing: source.kind.rawValue)

            TextEditor(text: $source.rule)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(Palette.secondary)
                .scrollContentBackground(.hidden)
                .padding(10)
                .frame(height: 150)
                .glassSurface(cornerRadius: 18)

            HStack {
                Button {
                    validateRules()
                } label: {
                    Label("校验 JSON", systemImage: "checkmark.seal")
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(Palette.jade)
                        .padding(.horizontal, 11)
                        .padding(.vertical, 8)
                        .glassCapsule(tint: Palette.jade.opacity(0.1), interactive: true)
                }
                .buttonStyle(PressableStyle())

                if !ruleMessage.isEmpty {
                    Text(ruleMessage)
                        .font(.system(size: 10))
                        .foregroundStyle(ruleMessage.contains("有效") ? Palette.jade : Palette.accent)
                }
            }
        }
    }

    private var loginSection: some View {
        VStack(alignment: .leading, spacing: 9) {
            SectionHeading(text: "书源登录", trailing: source.login.rawValue)

            VStack(alignment: .leading, spacing: 8) {
                Text(hasLoginScript
                     ? "这条书源声明了登录脚本，但 App 不会代你执行站点登录、也不保存站点密码。需要登录态的源，请在书源规则里用 Cookie / header 自行配置。"
                     : "这条书源没有登录脚本。搜索、目录与正文按规则匿名请求；需要账号的源请在书源规则里配置 Cookie 或 header。")
                    .font(.system(size: 10.5))
                    .foregroundStyle(Palette.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Text("App 从不伪造登录成功，也不会把账号密码写进书源。")
                    .font(.system(size: 10))
                    .foregroundStyle(Palette.tertiary)
            }
            .padding(13)
            .glassSurface(cornerRadius: 20)
        }
    }

    private var debugSection: some View {
        VStack(alignment: .leading, spacing: 9) {
            SectionHeading(text: "分步调试", trailing: "搜索 → 详情 → 目录 → 正文")

            VStack(spacing: 0) {
                if debugLines.isEmpty {
                    Text("尚未运行。调试会依次请求搜索、详情、目录和正文。")
                        .font(.system(size: 11))
                        .foregroundStyle(Palette.tertiary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(13)
                } else {
                    ForEach(debugLines) { line in
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: line.ok ? "checkmark.circle.fill" : "xmark.circle.fill")
                                .font(.system(size: 12))
                                .foregroundStyle(line.ok ? Palette.jade : Palette.accent)
                                .padding(.top, 1)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(line.step)
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(Palette.text)
                                Text(line.detail)
                                    .font(.system(size: 10.5))
                                    .foregroundStyle(Palette.secondary)
                            }

                            Spacer()

                            Text("\(line.milliseconds) ms")
                                .font(.system(size: 9.5, design: .rounded))
                                .foregroundStyle(Palette.tertiary)
                                .monospacedDigit()
                        }
                        .padding(.horizontal, 13)
                        .padding(.vertical, 10)

                        if line.id != debugLines.last?.id {
                            Rectangle()
                                .fill(Palette.hairline)
                                .frame(height: 0.6)
                                .padding(.leading, 35)
                        }
                    }
                }
            }
            .glassSurface(cornerRadius: 20)
        }
    }

    private var batchSection: some View {
        VStack(alignment: .leading, spacing: 9) {
            SectionHeading(
                text: "批量测试报告",
                trailing: "\(report.filter(\.ok).count) / \(report.count) 可用"
            )

            VStack(spacing: 0) {
                ForEach(report) { row in
                    HStack {
                        Circle()
                            .fill(row.ok ? Palette.jade : Palette.accent)
                            .frame(width: 6, height: 6)
                        Text(row.name)
                            .font(.system(size: 12))
                            .foregroundStyle(Palette.text)
                        Spacer()
                        Text(row.ok ? "\(row.milliseconds) ms" : "失败")
                            .font(.system(size: 10, design: .rounded))
                            .foregroundStyle(row.ok ? Palette.jade : Palette.accent)
                            .monospacedDigit()
                    }
                    .padding(.horizontal, 13)
                    .padding(.vertical, 9)
                }
            }
            .glassSurface(cornerRadius: 18)
        }
    }

    private func validateRules() {
        guard !source.rule.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            ruleMessage = "规则为空"
            return
        }
        guard let data = source.rule.data(using: .utf8),
              (try? JSONSerialization.jsonObject(with: data)) != nil else {
            ruleMessage = "JSON 无效，上一篇有效规则会保留"
            return
        }
        ruleMessage = "JSON 结构有效"
    }
}

// MARK: - Source import / export

struct SourceImportExportSheet: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var json = """
    [
      {
        "name": "夜读书库",
        "host": "night.example.com",
        "kind": "json",
        "enabled": false
      },
      {
        "name": "旧纸脚本源",
        "host": "script.example.com",
        "kind": "js",
        "enabled": false
      }
    ]
    """
    @State private var message = ""
    @State private var showPicker = false

    var body: some View {
        NavigationStack {
            ZStack {
                AppBackdrop()

                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack(spacing: 8) {
                            Button {
                                showPicker = true
                            } label: {
                                Label("选择 JSON", systemImage: "doc.badge.plus")
                                    .font(.system(size: 11.5, weight: .semibold))
                                    .foregroundStyle(Palette.jade)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                                    .glassCapsule(tint: Palette.jade.opacity(0.1), interactive: true)
                            }
                            .buttonStyle(PressableStyle())

                            Button {
                                exportJSON()
                            } label: {
                                Label("导出当前", systemImage: "square.and.arrow.up")
                                    .font(.system(size: 11.5, weight: .semibold))
                                    .foregroundStyle(Palette.text)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                                    .glassCapsule(tint: Palette.glassTint, interactive: true)
                            }
                            .buttonStyle(PressableStyle())
                        }

                        TextEditor(text: $json)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(Palette.secondary)
                            .scrollContentBackground(.hidden)
                            .padding(10)
                            .frame(height: 320)
                            .glassSurface(cornerRadius: 20)

                        if !message.isEmpty {
                            Text(message)
                                .font(.system(size: 11))
                                .foregroundStyle(message.contains("已导入") || message.contains("已生成") ? Palette.jade : Palette.accent)
                        }

                        Button {
                            importJSON(json)
                        } label: {
                            Text("校验并导入")
                                .readableButtonStyle(tint: Palette.accentSolid)
                        }
                        .buttonStyle(PressableStyle(scale: 0.97))

                        // 引擎已经能执行规则里的 JS，这句不能再写「不执行」。
                        Text("按 Legado 3.0 书源格式解析，保留全部规则字段。启用后检索与正文会真实联网；规则里的 JS 在 JavaScriptCore 中执行，私网地址一律拦截。")
                            .font(.system(size: 10.5))
                            .foregroundStyle(Palette.tertiary)
                    }
                    .padding(18)
                }
                .scrollIndicators(.hidden)
            }
            .navigationTitle("书源导入 / 导出")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") { dismiss() }
                        .fontWeight(.semibold)
                }
            }
        }
        .fileImporter(
            isPresented: $showPicker,
            allowedContentTypes: [.json],
            allowsMultipleSelection: false
        ) { result in
            guard case .success(let urls) = result, let url = urls.first else { return }
            let access = url.startAccessingSecurityScopedResource()
            defer { if access { url.stopAccessingSecurityScopedResource() } }
            if let data = try? Data(contentsOf: url), let text = String(data: data, encoding: .utf8) {
                json = text
                importJSON(text)
            } else {
                message = "文件读取失败，请选择 UTF-8 JSON。"
            }
        }
    }

    private func importJSON(_ text: String) {
        guard let data = text.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) else {
            message = "JSON 解析失败"
            return
        }

        let rows: [[String: Any]]
        if let array = object as? [[String: Any]] {
            rows = array
        } else if let single = object as? [String: Any] {
            rows = [single]
        } else {
            message = "请使用书源对象或数组格式"
            return
        }

        // 已存在的书源地址 + 本次已加入的地址，一起参与去重。
        // 原来只跟已有书源比，同一个文件里写两遍会重复导入两份。
        var seenURLs = Set(store.sources.map { $0.ruleSourceURL ?? $0.host })
        var added: [BookSource] = []
        var duplicates = 0
        var invalid = 0
        var blockedPrivate = 0

        for row in rows {
            // Legado 3.0 的字段名（bookSourceName / bookSourceUrl）优先，
            // 也兼容 App 自己的简写（name / host）。
            let name = (row["bookSourceName"] ?? row["name"]) as? String ?? ""
            let rawURL = (row["bookSourceUrl"] ?? row["host"] ?? row["searchUrl"] ?? row["search"]) as? String ?? ""
            guard !name.trimmingCharacters(in: .whitespaces).isEmpty,
                  !rawURL.trimmingCharacters(in: .whitespaces).isEmpty else {
                invalid += 1
                continue
            }

            // 书源地址可能是逗号分隔的多域名：`https://a.com,https://b.com`。
            // 拿整串去 normalize 会得到 `a.com,https` 这种垃圾串，
            // 所以先拆开，再逐个判定与去重。
            let hosts = BookSource.splitHosts(rawURL)
            guard !hosts.isEmpty else {
                invalid += 1
                continue
            }

            let identity = rawURL.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !seenURLs.contains(identity) else {
                duplicates += 1
                continue
            }
            // 只要有一个域名指向私网就整条拒绝：书源可以在规则里拼地址，
            // 放行一半等于没拦。
            guard !hosts.contains(where: { URLHost.isPrivate($0) }) else {
                blockedPrivate += 1
                continue
            }
            seenURLs.insert(identity)

            // 规则原文按行重新序列化，保留全部 Legado 字段。
            let ownRule: String = {
                guard let ruleData = try? JSONSerialization.data(
                    withJSONObject: row,
                    options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
                ) else { return "" }
                return String(data: ruleData, encoding: .utf8) ?? ""
            }()

            // 类型跟着 Legado 的 bookSourceType 走：0 小说 / 1 音频 / 2 图片 / 3 文件。
            // 原来只看 App 自造的 "kind" 字段，Legado 书源没有这个键，
            // 结果全部落成 JSON，界面上完全看不出是不是 JS 源。
            let hasJS = BookSource.containsJavaScript(row)
            let kind: SourceKind = hasJS ? .js : .json

            added.append(
                BookSource(
                    id: UUID().uuidString,
                    name: name,
                    host: hosts[0],
                    kind: kind,
                    enabled: false,
                    bookCount: 0,
                    group: (row["bookSourceGroup"] as? String)?.components(separatedBy: ",").first ?? "小说",
                    rule: ownRule
                )
            )
        }

        store.addSources(added)
        message = "已导入 \(added.count) 个书源（默认关闭）"
            + (duplicates > 0 ? " · \(duplicates) 个重复已跳过" : "")
            + (invalid > 0 ? " · \(invalid) 个无效" : "")
            + (blockedPrivate > 0 ? " · \(blockedPrivate) 个私网地址已拦截" : "")
    }

    private func exportJSON() {
        // 导出成 Legado 3.0 的字段名，导入回阅读类 App 时能直接认。
        // 规则本身已经是完整书源 JSON，能解析就原样输出，解析不了才退回元数据。
        let rows = store.sources.map { source -> [String: Any] in
            if let raw = source.rule.data(using: .utf8),
               let object = try? JSONSerialization.jsonObject(with: raw) as? [String: Any] {
                var copy = object
                copy["bookSourceName"] = source.name
                copy["enabled"] = source.enabled
                return copy
            }
            return [
                "bookSourceName": source.name,
                "bookSourceUrl": source.host,
                "bookSourceGroup": source.group,
                "bookSourceType": 0,
                "enabled": source.enabled
            ]
        }
        guard let data = try? JSONSerialization.data(
            withJSONObject: rows,
            options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        ), let text = String(data: data, encoding: .utf8) else { return }
        json = text
        message = "已生成导出预览，不会写入文件"
    }
}

// MARK: - Network logs

/// 网络日志：显示 LegadoCore 真正发出的请求。
///
/// 这个页面原来读的是 `MockBackend.logs` —— 那是演示后端自己记的假记录。
/// 搜索、目录、正文改成真实引擎之后，真实请求根本不进那张表，
/// 页面就成了「看起来有日志、其实一条真的都没有」。
struct NetworkLogSheet: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    private var diagnostics: NetworkDiagnostics { store.diagnostics }

    var body: some View {
        NavigationStack {
            ZStack {
                AppBackdrop()

                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        recordingCard

                        HStack {
                            SectionHeading(text: "最近请求", trailing: "\(diagnostics.entries.count) 条")
                            if !diagnostics.entries.isEmpty {
                                Button("清空") {
                                    diagnostics.clear()
                                }
                                .font(.system(size: 10.5, weight: .medium))
                                .foregroundStyle(Palette.accent)
                            }
                        }

                        if diagnostics.entries.isEmpty {
                            ContentUnavailableView(
                                diagnostics.isRecording ? "还没有请求" : "未开启记录",
                                systemImage: "network",
                                description: Text(
                                    diagnostics.isRecording
                                        ? "搜索、目录、正文、发现、段评或换源之后会出现记录"
                                        : "打开上面的「记录请求」，再做一次检索或翻页"
                                )
                            )
                            .padding(.top, 30)
                        } else {
                            VStack(spacing: 0) {
                                let shown = Array(diagnostics.entries.prefix(40))
                                ForEach(shown) { entry in
                                    entryRow(entry, isLast: entry.id == shown.last?.id)
                                }
                            }
                            .glassSurface(cornerRadius: 18)
                        }

                        if !diagnostics.entries.isEmpty {
                            Button {
                                UIPasteboard.general.string = diagnostics.exportText
                                store.showToast("已复制 \(diagnostics.entries.count) 条日志")
                            } label: {
                                Text("复制全部日志")
                                    .font(.system(size: 11.5, weight: .semibold))
                                    .foregroundStyle(Palette.jade)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 11)
                                    .glassSurface(cornerRadius: 16, tint: Palette.jade.opacity(0.08), interactive: true)
                            }
                            .buttonStyle(PressableStyle())
                        }
                    }
                    .padding(18)
                }
                .scrollIndicators(.hidden)
            }
            .navigationTitle("网络日志")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") { dismiss() }
                        .fontWeight(.semibold)
                }
            }
            .task {
                while !Task.isCancelled {
                    diagnostics.refresh()
                    do {
                        try await Task.sleep(for: .seconds(1))
                    } catch {
                        break
                    }
                }
            }
        }
    }

    private var recordingCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Toggle(isOn: Binding(
                get: { diagnostics.isRecording },
                set: { diagnostics.setRecording($0) }
            )) {
                Text("记录请求")
                    .font(.system(size: 13.5, weight: .medium))
                    .foregroundStyle(Palette.text)
            }
            .tint(Palette.jade)

            // 记录会把请求地址写进磁盘，说清楚而不是默认打开。
            Text("开启后，引擎发出的每条请求地址与状态会写到本机 Application Support/Legado/Logs；关闭时不记录。")
                .font(.system(size: 10.5))
                .foregroundStyle(Palette.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(13)
        .glassSurface(cornerRadius: 18)
    }

    private func entryRow(_ entry: DiagnosticLogEntry, isLast: Bool) -> some View {
        let tint: Color = switch entry.level {
        case .error: Palette.accent
        case .warning: Palette.gold
        case .info: Palette.jade
        }

        return VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 8) {
                Text(entry.category)
                    .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                    .foregroundStyle(tint)
                    .frame(width: 34, alignment: .leading)

                Text(entry.message)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(Palette.secondary)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Text(entry.date.formatted(date: .omitted, time: .standard))
                    .font(.system(size: 8.5, design: .rounded))
                    .foregroundStyle(Palette.tertiary)
                    .monospacedDigit()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)

            if !isLast {
                Rectangle()
                    .fill(Palette.hairline)
                    .frame(height: 0.6)
                    .padding(.leading, 12)
            }
        }
    }
}
