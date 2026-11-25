import SwiftUI

struct SourceView: View {
    @Environment(AppStore.self) private var store

    @State private var showAddSource = false
    @State private var showSearch = false

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
                    Button {
                        showAddSource = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("添加书源")
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
        .task {
            #if DEBUG
            let arguments = ProcessInfo.processInfo.arguments
            if arguments.contains("-showSearch") {
                showSearch = true
            } else if arguments.contains("-showAddSource") {
                showAddSource = true
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
                    SourceRow(source: source) { enabled in
                        store.setSourceEnabled(source.id, enabled: enabled)
                    }
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
        Text("演示数据：书源检索与解析尚未接入网络请求。")
            .font(.system(size: 10.5))
            .foregroundStyle(Palette.tertiary)
            .padding(.horizontal, 2)
            .padding(.top, 2)
    }
}

struct SourceRow: View {
    let source: BookSource
    let onToggle: (Bool) -> Void

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
                                        SearchResultRow(book: book)
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
                isSearching = true
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(420))
                    withAnimation(.easeOut(duration: 0.2)) { isSearching = false }
                }
            }
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
                    Text("示例书源")
                        .font(.system(size: 9.5))
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
