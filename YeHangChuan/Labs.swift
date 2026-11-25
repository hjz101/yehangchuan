import SwiftUI
import UIKit

// MARK: - Export

struct DataExportSheet: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var tab: ExportTab = .json
    @State private var message = ""
    @State private var fileURL: URL?

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

    private var content: String {
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

                        if !message.isEmpty {
                            Text(message)
                                .font(.system(size: 10.5))
                                .foregroundStyle(Palette.tertiary)
                        }

                        Text("演示导出会生成 books.json、notes.md、annotations.md 三个文件预览；分享写入临时目录，不修改书架数据。")
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
    @State private var model = "demo-model"
    @State private var key = ""
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
                    book: store.books.first ?? MockData.books[0],
                    chapterTitle: "AI 摘要试听",
                    text: summary.isEmpty ? "夜航船在水面上缓慢前行，灯影落在书页上。" : summary
                )
                .presentationDetents([.large])
                .presentationCornerRadius(38)
            }
        }
    }

    private var configCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeading(text: "服务配置", trailing: "Key 仅本机")

            GlassSegmented(
                items: ["自定义兼容服务", "本地服务"],
                title: { $0 },
                selection: $provider
            )

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
                    TextField("API Key（占位，不写入 Keychain）", text: $key)
                } else {
                    SecureField("API Key（占位，不写入 Keychain）", text: $key)
                }
            }
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .glassSurface(cornerRadius: 14)
        }
        .padding(14)
        .glassSurface(cornerRadius: 22)
    }

    private var summaryCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeading(text: "AI 摘要", trailing: "本地模拟")

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
                isBusy = true
                Task { @MainActor in
                    let response = await store.backend.testAI(provider: provider, model: model)
                    summary = response.ok
                        ? "《夜航船》以一夜水路串起三个陌生人的片段。主人公在灯下读书，也在读同船人的沉默。抵达不是终点，书与夜航仍在继续。"
                        : "服务不可用：模拟网络离线。"
                    message = response.ok ? "摘要已生成" : "连接失败"
                    isBusy = false
                }
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
                coverIdeas = [
                    AICoverIdea(name: "暮色船坞", colors: (Color(hex: 0x8C4A32), Color(hex: 0x2A1711))),
                    AICoverIdea(name: "雾蓝水面", colors: (Color(hex: 0x4F7890), Color(hex: 0x132430))),
                    AICoverIdea(name: "旧纸靛蓝", colors: (Color(hex: 0x3D5663), Color(hex: 0xE0CEAA)))
                ]
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
            Text("演示边界：不发起真实 AI 请求，不保存真实 Key，不读取正文上传。正式版 Key 需要存入 Keychain，并由用户自付服务费用。")
                .font(.system(size: 10))
                .foregroundStyle(Palette.tertiary)
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

// MARK: - JS sandbox

struct JSSandboxSheet: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var host = "https://books.example"
    @State private var strictMode = true
    @State private var allowPrivate = false
    @State private var script = """
    const list = await fetch(`${base}/search?q=${keyword}`)
    const html = await list.text()
    return parseHTML(html).selectAll('.book')
    """
    @State private var logs: [DebugLine] = []
    @State private var isRunning = false
    @State private var message = ""

    var body: some View {
        NavigationStack {
            ZStack {
                AppBackdrop()

                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        permissionCard
                        configCard
                        scriptCard
                        resultCard
                    }
                    .padding(18)
                }
                .scrollIndicators(.hidden)
            }
            .navigationTitle("JS 书源沙箱")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") { dismiss() }
                        .fontWeight(.semibold)
                }
            }
        }
    }

    private var permissionCard: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.shield")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Palette.accent)
                .padding(.top, 1)

            VStack(alignment: .leading, spacing: 4) {
                Text("权限与分发警告")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Palette.text)
                Text("执行远程脚本违反 App Store 2.5.2，因此仅用于 TestFlight / 自签。脚本由你自行提供，App 不预装、不推荐。")
                    .font(.system(size: 10.5))
                    .foregroundStyle(Palette.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(13)
        .glassSurface(cornerRadius: 20, tint: Palette.accent.opacity(0.08))
    }

    private var configCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeading(text: "沙箱边界", trailing: "严格模式")

            TextField("站点地址", text: $host)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .glassSurface(cornerRadius: 14)

            Toggle("严格模式：禁止本地文件 / Keychain / 剪贴板", isOn: $strictMode)
                .font(.system(size: 12))
                .tint(Palette.jade)

            Toggle("允许访问私网地址（不推荐）", isOn: $allowPrivate)
                .font(.system(size: 12))
                .tint(Palette.accent)

            if SourceView.isPrivateHost(host) {
                Text(allowPrivate ? "已显式放行私网地址，请确认你知道风险。" : "检测到私网地址，默认拦截。")
                    .font(.system(size: 10))
                    .foregroundStyle(allowPrivate ? Palette.gold : Palette.accent)
            }
        }
        .padding(14)
        .glassSurface(cornerRadius: 20)
    }

    private var scriptCard: some View {
        VStack(alignment: .leading, spacing: 9) {
            SectionHeading(text: "脚本", trailing: "不执行")

            TextEditor(text: $script)
                .font(.system(size: 10.5, design: .monospaced))
                .foregroundStyle(Palette.secondary)
                .scrollContentBackground(.hidden)
                .padding(10)
                .frame(height: 160)
                .glassSurface(cornerRadius: 18)

            HStack(spacing: 9) {
                Button {
                    run()
                } label: {
                    Label("运行沙箱测试", systemImage: "play.fill")
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(Palette.onAccent)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Palette.accentSolid, in: Capsule())
                }
                .buttonStyle(PressableStyle(scale: 0.97))
                .disabled(isRunning)

                if isRunning { ProgressView() }
            }

            if !message.isEmpty {
                Text(message)
                    .font(.system(size: 10.5))
                    .foregroundStyle(Palette.accent)
            }
        }
    }

    private var resultCard: some View {
        VStack(alignment: .leading, spacing: 9) {
            SectionHeading(text: "沙箱日志", trailing: "\(logs.count) 步")

            if logs.isEmpty {
                Text("尚未运行。演示会模拟 WKWebView 隔离、受限桥接、私网拦截和脚本超时。")
                    .font(.system(size: 11))
                    .foregroundStyle(Palette.tertiary)
                    .padding(13)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .glassSurface(cornerRadius: 18)
            } else {
                VStack(spacing: 0) {
                    ForEach(logs) { line in
                        HStack(spacing: 9) {
                            Image(systemName: line.ok ? "checkmark.circle.fill" : "xmark.shield.fill")
                                .font(.system(size: 11))
                                .foregroundStyle(line.ok ? Palette.jade : Palette.accent)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(line.step)
                                    .font(.system(size: 11.5, weight: .semibold))
                                    .foregroundStyle(Palette.text)
                                Text(line.detail)
                                    .font(.system(size: 10))
                                    .foregroundStyle(Palette.secondary)
                            }
                            Spacer()
                            Text("\(line.milliseconds) ms")
                                .font(.system(size: 9, design: .rounded))
                                .foregroundStyle(Palette.tertiary)
                                .monospacedDigit()
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 9)
                    }
                }
                .glassSurface(cornerRadius: 18)
            }
        }
    }

    private func run() {
        guard !SourceView.isPrivateHost(host) || allowPrivate else {
            message = "已拦截私网地址：\(host)"
            return
        }
        isRunning = true
        message = ""
        Task { @MainActor in
            let response = await store.backend.call("POST", "/v1/js/sandbox/run", base: 360)
            var rows: [DebugLine] = []
            let steps: [(String, String)] = [
                ("创建独立进程", "WKWebView 在独立进程启动"),
                ("注入受限桥接", strictMode ? "仅暴露 fetch 与 DOM 解析" : "严格模式关闭，权限扩大"),
                ("网络与文件拦截", allowPrivate ? "私网访问已放行" : "私网、file://、Keychain 均被拒绝"),
                ("执行搜索规则", response.ok ? "返回 3 条模拟结果" : "请求超时，已中止")
            ]
            for (index, step) in steps.enumerated() {
                rows.append(
                    DebugLine(
                        step: step.0,
                        detail: step.1,
                        ok: response.ok || index < 3,
                        milliseconds: response.milliseconds + index * 18
                    )
                )
            }
            logs = rows
            message = response.ok ? "沙箱测试完成，未执行真实脚本" : "模拟网关离线"
            isRunning = false
        }
    }
}

// MARK: - Online discovery

struct DiscoverSheet: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var category = "古风"
    @State private var isLoading = false
    @State private var results: [Book] = []
    @State private var subscribed: Set<String> = ["示例书源"]

    private let categories = ["全部", "古风", "奇幻", "都市", "科幻"]

    var body: some View {
        NavigationStack {
            ZStack {
                AppBackdrop()

                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        header
                        categoryRow

                        if isLoading {
                            HStack(spacing: 9) {
                                ProgressView()
                                Text("正在聚合已启用书源…")
                                    .font(.system(size: 11.5))
                                    .foregroundStyle(Palette.tertiary)
                            }
                            .padding(.top, 30)
                        } else {
                            ForEach(results) { book in
                                resultRow(book)
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
            .task { await load() }
            .onChange(of: category) { _, _ in
                Task { await load() }
            }
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
                Text("发现与订阅")
                    .font(.system(size: 16, weight: .semibold, design: .serif))
                    .foregroundStyle(Palette.text)
                Text("仅聚合你已启用的书源；当前为本地模拟数据")
                    .font(.system(size: 10.5))
                    .foregroundStyle(Palette.tertiary)
            }
            Spacer()
        }
        .padding(14)
        .glassSurface(cornerRadius: 22)
    }

    private var categoryRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(categories, id: \.self) { item in
                    Button {
                        category = item
                    } label: {
                        Text(item)
                            .font(.system(size: 12, weight: category == item ? .semibold : .medium))
                            .foregroundStyle(category == item ? Palette.onAccent : Palette.secondary)
                            .padding(.horizontal, 13)
                            .padding(.vertical, 8)
                            .background {
                                if category == item { Capsule().fill(Palette.jade) }
                            }
                            .glassCapsule(tint: category == item ? nil : Palette.glassTint, interactive: true)
                    }
                    .buttonStyle(PressableStyle())
                }
            }
        }
        .scrollClipDisabled()
    }

    private func resultRow(_ book: Book) -> some View {
        HStack(spacing: 12) {
            BookCover(book: book, cornerRadius: 8)
                .frame(width: 54)

            VStack(alignment: .leading, spacing: 3) {
                Text(book.title)
                    .font(.system(size: 15, weight: .semibold, design: .serif))
                    .foregroundStyle(Palette.text)
                    .lineLimit(1)
                Text("\(book.author) · \(book.kind.rawValue) · \(book.chapterCount) \(book.unitLabel)")
                    .font(.system(size: 10.5))
                    .foregroundStyle(Palette.tertiary)
                Text("模拟书源 · 最近更新")
                    .font(.system(size: 9.5))
                    .foregroundStyle(Palette.jade)
            }

            Spacer()

            Button {
                store.addToShelf(book)
            } label: {
                Image(systemName: store.isOnShelf(book.id) ? "checkmark" : "plus")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(store.isOnShelf(book.id) ? Palette.jade : Palette.onAccent)
                    .frame(width: 34, height: 34)
                    .background(
                        store.isOnShelf(book.id) ? Palette.jade.opacity(0.14) : Palette.accentSolid,
                        in: Circle()
                    )
            }
            .buttonStyle(PressableStyle())
            .disabled(store.isOnShelf(book.id))
        }
        .padding(12)
        .glassSurface(cornerRadius: 18)
    }

    private func load() async {
        isLoading = true
        let response = await store.backend.call("GET", "/v1/discover?category=\(category)")
        try? await Task.sleep(for: .milliseconds(220))
        let pool = MockData.searchResults + store.books.filter { $0.kind == .novel }.prefix(2).map { $0 }
        results = response.ok ? Array(pool.prefix(6)) : []
        isLoading = false
    }
}

// MARK: - Voice lab

struct VoiceLabSheet: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var speed = 1.0
    @State private var background = true
    @State private var lockScreen = true
    @State private var carPlay = true
    @State private var cache = true
    @State private var roles: [String: String] = [
        "旁白": "温柔女声",
        "年轻旅人": "清亮少年",
        "卖布老人": "沉稳长者"
    ]

    private let voices = ["温柔女声", "清亮少年", "沉稳长者", "粤语女声"]

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
                if !store.speech.hasChapter {
                    store.speech.load(
                        book: store.books.first ?? MockData.books[0],
                        chapterTitle: "声音实验室",
                        text: "夜航船靠岸的时候，雾还没有散。卖布的老人先下了船，回头朝我点了点头。"
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
                Text(String(format: "%.2g×", speed))
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
            SectionHeading(text: "角色与声音", trailing: "映射演示")

            VStack(spacing: 0) {
                ForEach(Array(roles.keys.sorted()), id: \.self) { role in
                    HStack {
                        Text(role)
                            .font(.system(size: 12.5))
                            .foregroundStyle(Palette.text)
                        Spacer()
                        Menu {
                            ForEach(voices, id: \.self) { voice in
                                Button(voice) { roles[role] = voice }
                            }
                        } label: {
                            HStack(spacing: 5) {
                                Text(roles[role] ?? "")
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

                    if role != roles.keys.sorted().last {
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
            SectionHeading(text: "播放与缓存")

            VStack(alignment: .leading, spacing: 10) {
                Toggle("后台播放", isOn: $background)
                Toggle("锁屏播放信息", isOn: $lockScreen)
                Toggle("CarPlay 模拟", isOn: $carPlay)
                Toggle("音频缓存", isOn: $cache)
            }
            .font(.system(size: 12.5))
            .tint(Palette.accent)
            .padding(12)
            .glassSurface(cornerRadius: 18)
        }
    }

    private var boundaryNote: some View {
        Text("当前使用系统语音真实播放；多角色、后台与 CarPlay 为演示配置。正式版需要音频会话、锁屏控制和合规音源。")
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
