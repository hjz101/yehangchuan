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
                AppBackground()

                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        header
                        sourceSection
                        searchEntry

                        Text("当前为演示数据，用于观察书源管理与搜索加入书架的交互路径。")
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.secondary.opacity(0.8))
                            .padding(.horizontal, 20)
                    }
                    .padding(.top, 16)
                    .padding(.bottom, 112)
                }
                .scrollIndicators(.hidden)
            }
            .toolbar(.hidden, for: .navigationBar)
        }
        .sheet(isPresented: $showAddSource) {
            AddSourceSheet()
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showSearch) {
            SourceSearchSheet()
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
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

    private var header: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("书源")
                .font(.system(size: 32, weight: .bold, design: .serif))
                .foregroundStyle(Theme.text)

            Text("\(store.sources.count) 个书源 · \(enabledCount) 个已启用")
                .font(.system(size: 13))
                .foregroundStyle(Theme.secondary)
        }
        .padding(.horizontal, 20)
    }

    private var sourceSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                SectionHeading(text: "我的书源")

                Spacer()

                Button {
                    showAddSource = true
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "plus")
                        Text("添加")
                    }
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.accent)
                }
            }
            .padding(.horizontal, 20)

            VStack(spacing: 0) {
                ForEach(Array(store.sources.enumerated()), id: \.element.id) { index, source in
                    SourceRow(source: source) { enabled in
                        store.setSourceEnabled(source.id, enabled: enabled)
                    }

                    if index < store.sources.count - 1 {
                        Divider()
                            .overlay(Theme.hairline)
                            .padding(.leading, 62)
                    }
                }
            }
            .glassSurface(cornerRadius: 18)
            .padding(.horizontal, 20)
        }
    }

    private var searchEntry: some View {
        Button {
            showSearch = true
        } label: {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 7)
                        .fill(Theme.ink)
                        .frame(width: 42, height: 42)

                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Theme.paper)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text("搜索并加入书架")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Theme.text)

                    Text(enabledCount > 0 ? "在已启用书源中搜索" : "先在设置中启用一个书源")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.secondary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.secondary.opacity(0.5))
            }
            .padding(16)
            .glassSurface(cornerRadius: 18, tint: Theme.ink.opacity(0.08), interactive: true)
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 20)
    }
}

struct SourceRow: View {
    let source: BookSource
    let onToggle: (Bool) -> Void

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 7)
                    .fill(source.enabled ? Theme.ink.opacity(0.9) : Color.white.opacity(0.07))
                    .frame(width: 38, height: 38)

                Image(systemName: source.kind == .js ? "curlybraces" : "doc.text")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(source.enabled ? Theme.text : Theme.secondary)
            }

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(source.name)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Theme.text)
                        .lineLimit(1)

                    Text(source.kind.rawValue)
                        .font(.system(size: 8, weight: .bold))
                        .tracking(0.5)
                        .foregroundStyle(Theme.accent)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Theme.accent.opacity(0.1), in: RoundedRectangle(cornerRadius: 3))
                }

                Text("\(source.host) · \(source.bookCount) 本")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 6)

            Toggle(
                "",
                isOn: Binding(
                    get: { source.enabled },
                    set: onToggle
                )
            )
            .labelsHidden()
            .tint(Theme.accent)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }
}

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

    var body: some View {
        NavigationStack {
            ZStack {
                AppBackground()

                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        VStack(alignment: .leading, spacing: 10) {
                            SectionHeading(text: "名称")

                            TextField("书源名称", text: $name)
                                .font(.system(size: 15))
                                .padding(12)
                                .glassSurface(cornerRadius: 14)
                        }

                        VStack(alignment: .leading, spacing: 10) {
                            SectionHeading(text: "类型")

                            Picker("类型", selection: $kind) {
                                Text("JSON").tag(SourceKind.json)
                                Text("JS 脚本").tag(SourceKind.js)
                            }
                            .pickerStyle(.segmented)
                            .onChange(of: kind) { _, newKind in
                                config = template(for: newKind)
                            }
                        }

                        VStack(alignment: .leading, spacing: 10) {
                            SectionHeading(text: "配置")

                            TextEditor(text: $config)
                                .font(.system(size: 12, design: .monospaced))
                                .scrollContentBackground(.hidden)
                                .padding(10)
                                .frame(height: 190)
                                .glassSurface(cornerRadius: 16)
                        }
                    }
                    .padding(20)
                }
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

struct SourceSearchSheet: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var query = ""
    @State private var selectedSourceID: String?

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
                AppBackground()

                VStack(spacing: 14) {
                    searchField

                    if enabledSources.isEmpty {
                        ContentUnavailableView(
                            "没有启用的书源",
                            systemImage: "antenna.radiowaves.left.and.right.slash",
                            description: Text("回到书源页启用一个书源后再搜索")
                        )
                        .frame(maxHeight: .infinity)
                    } else {
                        sourcePicker

                        ScrollView {
                            VStack(spacing: 10) {
                                ForEach(results) { book in
                                    SearchResultRow(book: book)
                                }

                                if results.isEmpty {
                                    Text("没有匹配的结果")
                                        .font(.system(size: 13))
                                        .foregroundStyle(Theme.secondary)
                                        .padding(.top, 40)
                                }
                            }
                            .padding(.horizontal, 20)
                            .padding(.bottom, 24)
                        }
                        .scrollIndicators(.hidden)
                    }
                }
                .padding(.top, 8)
            }
            .navigationTitle("搜索")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") { dismiss() }
                }
            }
            .onAppear {
                selectedSourceID = enabledSources.first?.id
            }
        }
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 13))
                .foregroundStyle(Theme.secondary)

            TextField("输入书名或作者", text: $query)
                .font(.system(size: 14))
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

    private var sourcePicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(enabledSources) { source in
                    Button {
                        selectedSourceID = source.id
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: source.kind == .js ? "curlybraces" : "doc.text")
                            Text(source.name)
                        }
                        .font(.system(size: 11, weight: selectedSourceID == source.id ? .semibold : .regular))
                        .foregroundStyle(Theme.text)
                        .padding(.horizontal, 11)
                        .padding(.vertical, 6)
                        .glassSurface(
                            cornerRadius: 14,
                            tint: selectedSourceID == source.id ? Theme.ink.opacity(0.5) : nil,
                            interactive: true
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 20)
        }
    }
}

struct SearchResultRow: View {
    @Environment(AppStore.self) private var store

    let book: Book

    private var added: Bool { store.isOnShelf(book.id) }

    var body: some View {
        HStack(spacing: 13) {
            BookCover(book: book, compact: true)
                .frame(width: 46)

            VStack(alignment: .leading, spacing: 4) {
                Text(book.title)
                    .font(.system(size: 15, weight: .semibold, design: .serif))
                    .foregroundStyle(Theme.text)

                Text("\(book.author) · \(book.kind.rawValue)")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.secondary)
            }

            Spacer()

            Button {
                store.addToShelf(book)
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: added ? "checkmark" : "plus")
                    Text(added ? "已加入" : "加入书架")
                }
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(added ? Theme.secondary : Theme.text)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .glassSurface(
                    cornerRadius: 14,
                    tint: added ? nil : Theme.ink.opacity(0.5),
                    interactive: !added
                )
            }
            .buttonStyle(.plain)
            .disabled(added)
        }
        .padding(12)
        .glassSurface(cornerRadius: 16)
    }
}
