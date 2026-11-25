import SwiftUI
import UniformTypeIdentifiers

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
                    VStack(alignment: .leading, spacing: 20) {
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
        }
        .sheet(isPresented: $showSearch) {
            SourceSearchSheet()
                .presentationDetents([.large])
                .presentationCornerRadius(38)
        }
        .sheet(isPresented: $showImportExport) {
            SourceImportExportSheet()
                .presentationDetents([.large])
                .presentationCornerRadius(38)
        }
        .sheet(isPresented: $showLogs) {
            NetworkLogSheet()
                .presentationDetents([.medium, .large])
                .presentationCornerRadius(38)
        }
        .sheet(item: $detailSource) { source in
            SourceDetailSheet(source: source)
                .presentationDetents([.large])
                .presentationCornerRadius(38)
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

                Text("共 \(store.sources.count) 个书源，可检索 \(store.sources.filter(\.enabled).reduce(0) { $0 + $1.bookCount }) 本")
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
        Text("书源默认关闭；启用前会提示权限与私网风险。检索与解析使用本地模拟服务。")
            .font(.system(size: 10.5))
            .foregroundStyle(Palette.tertiary)
            .padding(.horizontal, 2)
            .padding(.top, 2)
    }

    static func isPrivateHost(_ host: String) -> Bool {
        let value = host.lowercased()
        return value.hasPrefix("127.")
            || value.hasPrefix("10.")
            || value.hasPrefix("192.168.")
            || value == "localhost"
            || value == "0.0.0.0"
            || value.hasSuffix(".local")
            || value.range(of: #"^172\.(1[6-9]|2[0-9]|3[0-1])\."#, options: .regularExpression) != nil
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

                Text("\(source.host) · \(source.bookCount) 本")
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
                        store.addSource(name: name, kind: kind)
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
            SectionHeading(text: "类型")

            GlassSegmented(
                items: [SourceKind.json, SourceKind.js],
                title: { $0 == .json ? "JSON 配置" : "JS 脚本" },
                selection: $kind
            )
            .onChange(of: kind) { _, newKind in
                config = template(for: newKind)
            }
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

    private func template(for kind: SourceKind) -> String {
        switch kind {
        case .json:
            """
            {
              "name": "我的书源",
              "search": "https://example.com/search?q={kw}",
              "chapter": "https://example.com/chapter/{id}"
            }
            """
        case .js:
            """
            function search(keyword) {
              return fetch(`/search?q=${keyword}`)
                .then(r => r.json())
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

    private var enabledSources: [BookSource] {
        store.sources.filter(\.enabled)
    }

    private var results: [Book] {
        guard !query.isEmpty else { return MockData.searchResults }
        return MockData.searchResults.filter {
            $0.title.localizedCaseInsensitiveContains(query)
                || $0.author.localizedCaseInsensitiveContains(query)
        }
    }

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
                                if !isSearching && !enabledSources.isEmpty {
                                    HStack(spacing: 5) {
                                        Image(systemName: "antenna.radiowaves.left.and.right")
                                        Text("\(enabledSources.count) 个书源并发")
                                        if hitsBySource.values.reduce(0, +) > results.count {
                                            Text("· \(hitsBySource.values.reduce(0, +) - results.count) 条重复已合并")
                                        }
                                    }
                                    .font(.system(size: 9.5, weight: .medium))
                                    .foregroundStyle(Palette.tertiary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.bottom, 2)
                                }

                                if isSearching {
                                    searchingState
                                } else if results.isEmpty {
                                    VStack(spacing: 8) {
                                        Image(systemName: "magnifyingglass")
                                            .font(.system(size: 24, weight: .light))
                                            .foregroundStyle(Palette.tertiary)
                                        Text("没有匹配的结果")
                                            .font(.system(size: 13))
                                            .foregroundStyle(Palette.secondary)
                                    }
                                    .padding(.top, 48)
                                } else {
                                    ForEach(results) { book in
                                        SearchResultRow(
                                            book: book,
                                            sources: Array(enabledSources.prefix(2).map(\.name))
                                        )
                                    }
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

    private func runSearch() {
        searchTask?.cancel()
        guard !enabledSources.isEmpty else { return }
        isSearching = true
        let keyword = query
        searchTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(260))
            guard !Task.isCancelled else { return }
            var hits: [String: Int] = [:]
            for source in enabledSources {
                let response = await store.backend.call(
                    "GET",
                    "/source/\(source.id)/search?kw=\(keyword.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")"
                )
                if response.ok { hits[source.id] = 3 + (source.bookCount % 3) }
            }
            guard !Task.isCancelled else { return }
            hitsBySource = hits
            withAnimation(.easeOut(duration: 0.2)) { isSearching = false }
        }
    }

    private var searchingState: some View {
        VStack(spacing: 10) {
            ProgressView()
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

                Text("\(book.author) · \(book.kind.rawValue) · \(book.chapterCount) \(book.unitLabel)")
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

    @State private var source: BookSource
    @State private var probe: SourceProbe?
    @State private var debugLines: [DebugLine] = []
    @State private var report: [SourceProbe] = []
    @State private var account = "demo-reader"
    @State private var password = "demo-pass"
    @State private var isBusy = false
    @State private var ruleMessage = ""
    @State private var loginMessage = ""
    @State private var enableWarning = ""

    init(source: BookSource) {
        _source = State(initialValue: source)
        _account = State(initialValue: source.username.isEmpty ? "demo-reader" : source.username)
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
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("保存") {
                        store.updateSource(source)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
            .onDisappear { store.updateSource(source) }
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

                Text("\(source.host) · \(source.kind.rawValue) · \(source.bookCount) 本")
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
                    let result = await store.backend.probe(source)
                    probe = result
                    source.latency = result.milliseconds
                    source.lastError = result.ok ? nil : result.message
                    store.updateSource(source)
                    isBusy = false
                }
            }

            actionCard("批量测试", symbol: "checklist", tint: Palette.gold) {
                isBusy = true
                Task { @MainActor in
                    report = await store.backend.batchProbe(store.sources)
                    isBusy = false
                }
            }

            actionCard("运行调试", symbol: "ladybug", tint: Palette.accent) {
                isBusy = true
                Task { @MainActor in
                    debugLines = await store.backend.debug(source, query: "长风")
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

            if isBusy { ProgressView() }
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

            VStack(spacing: 10) {
                TextField("账号", text: $account)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .padding(.horizontal, 13)
                    .padding(.vertical, 11)
                    .glassSurface(cornerRadius: 15)

                SecureField("密码", text: $password)
                    .padding(.horizontal, 13)
                    .padding(.vertical, 11)
                    .glassSurface(cornerRadius: 15)

                HStack(spacing: 9) {
                    Button {
                        isBusy = true
                        Task { @MainActor in
                            let ok = await store.backend.loginSource(source, account: account, password: password)
                            source.login = ok ? .signedIn : .expired
                            source.username = account
                            loginMessage = ok ? "登录成功，Cookie 已保存到本次会话" : "登录失败，请检查账号或网络"
                            store.updateSource(source)
                            isBusy = false
                        }
                    } label: {
                        Text(source.login == .signedIn ? "重新登录" : "登录书源")
                            .readableButtonStyle(tint: Palette.jade)
                    }
                    .buttonStyle(PressableStyle(scale: 0.97))

                    if source.login == .signedIn {
                        Button {
                            source.login = .signedOut
                            source.username = ""
                            loginMessage = "已清除演示 Cookie"
                            store.updateSource(source)
                        } label: {
                            Text("清除")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(Palette.accent)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 13)
                                .glassCapsule(tint: Palette.accent.opacity(0.08), interactive: true)
                        }
                        .buttonStyle(PressableStyle())
                    }
                }

                if !loginMessage.isEmpty {
                    Text(loginMessage)
                        .font(.system(size: 10.5))
                        .foregroundStyle(Palette.tertiary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
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

                        Text("只读取书源名称、地址与类型，不执行任何 JavaScript。导入的规则仅保存在本机演示数据中。")
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

        let existing = Set(store.sources.map { $0.host.lowercased() })
        var added: [BookSource] = []
        var duplicates = 0
        var invalid = 0
        var blockedPrivate = 0

        for row in rows {
            let name = (row["name"] ?? row["bookSourceName"]) as? String ?? ""
            let host = (row["host"] ?? row["bookSourceUrl"]) as? String ?? ""
            guard !name.isEmpty, !host.isEmpty else {
                invalid += 1
                continue
            }
            let normalizedHost = host
                .replacingOccurrences(of: "https://", with: "")
                .replacingOccurrences(of: "http://", with: "")
                .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            guard !existing.contains(normalizedHost.lowercased()) else {
                duplicates += 1
                continue
            }
            guard !SourceView.isPrivateHost(normalizedHost) else {
                blockedPrivate += 1
                continue
            }
            let kindText = (row["kind"] as? String ?? "json").lowercased()
            added.append(
                BookSource(
                    id: UUID().uuidString,
                    name: name,
                    host: normalizedHost,
                    kind: kindText == "js" ? .js : .json,
                    enabled: false,
                    bookCount: 0,
                    rule: text
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
        let rows = store.sources.map { source -> [String: Any] in
            [
                "name": source.name,
                "host": source.host,
                "kind": source.kind == .js ? "js" : "json",
                "enabled": source.enabled
            ]
        }
        guard let data = try? JSONSerialization.data(
            withJSONObject: rows,
            options: [.prettyPrinted, .sortedKeys]
        ), let text = String(data: data, encoding: .utf8) else { return }
        json = text
        message = "已生成导出预览，不会写入文件"
    }
}

// MARK: - Network logs

struct NetworkLogSheet: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                AppBackdrop()

                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        Toggle(isOn: Binding(
                            get: { store.backend.isOnline },
                            set: { store.backend.isOnline = $0 }
                        )) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("模拟网络在线")
                                    .font(.system(size: 13.5, weight: .medium))
                                    .foregroundStyle(Palette.text)
                                Text("关闭后，搜索、同步与调试会返回 503")
                                    .font(.system(size: 10.5))
                                    .foregroundStyle(Palette.tertiary)
                            }
                        }
                        .tint(Palette.jade)
                        .padding(13)
                        .glassSurface(cornerRadius: 18)

                        HStack {
                            SectionHeading(text: "最近请求", trailing: "\(store.backend.requestCount) 次")
                            if !store.backend.logs.isEmpty {
                                Button("清空") {
                                    store.backend.logs.removeAll()
                                }
                                .font(.system(size: 10.5, weight: .medium))
                                .foregroundStyle(Palette.accent)
                            }
                        }

                        if store.backend.logs.isEmpty {
                            ContentUnavailableView(
                                "还没有请求",
                                systemImage: "network",
                                description: Text("搜索、书源测试或同步后会出现记录")
                            )
                            .padding(.top, 30)
                        } else {
                            VStack(spacing: 0) {
                                ForEach(store.backend.logs.prefix(20)) { log in
                                    HStack(spacing: 8) {
                                        Text(log.method)
                                            .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                                            .foregroundStyle(log.status == 200 ? Palette.jade : Palette.accent)
                                            .frame(width: 32, alignment: .leading)

                                        Text(log.path)
                                            .font(.system(size: 10, design: .monospaced))
                                            .foregroundStyle(Palette.secondary)
                                            .lineLimit(1)

                                        Spacer()

                                        Text("\(log.status)")
                                            .font(.system(size: 9.5, weight: .semibold, design: .rounded))
                                            .foregroundStyle(log.status == 200 ? Palette.jade : Palette.accent)
                                        Text("\(log.milliseconds) ms")
                                            .font(.system(size: 9, design: .rounded))
                                            .foregroundStyle(Palette.tertiary)
                                            .monospacedDigit()
                                    }
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 9)

                                    if log.id != store.backend.logs.prefix(20).last?.id {
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
        }
    }
}
