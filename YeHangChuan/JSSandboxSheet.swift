import SwiftUI
import LegadoCore

// MARK: - JS 书源沙箱

/// 「JS 书源沙箱」：把阅读 3.0 书源里靠 WebView 渲染的那条链路，
/// 摊开来一步一步跑给你看。
///
/// 现在它和书源页是一体的：先列出书库里所有可解析的 3.0 书源，选中后既能
/// 打开书源自己的登录 / 设置页面，也能按搜索 / 详情 / 目录 / 正文分步调试。
/// 地址规则取自书源本身，请求走与阅读时同一条传输层和私网闸门。
struct JSSandboxSheet: View {
    @Environment(\.theme) private var theme
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    /// 沙箱目前瞄准的书源。默认取第一个能解析成 Legado 书源、且已启用的。
    @State private var sourceID: String?
    @State private var pane: Pane = .sources
    @State private var stage: Stage = .content
    @State private var keyword = "长风"
    @State private var customRule = ""
    @State private var overrideScript = ""
    @State private var useOverrideScript = false
    @State private var isLoadingSample = false
    @State private var isRunning = false
    @State private var logs: [DebugLine] = []
    @State private var preview = ""
    @State private var message = ""
    @State private var sampleNote = ""
    @State private var traces: [WebViewTraceEntry] = []
    @State private var pageModel: SourceLoginModel?

    enum Pane: String, CaseIterable, Identifiable {
        case sources = "书源"
        case page = "页面"
        case debug = "调试"

        var id: String { rawValue }
    }

    enum Stage: String, CaseIterable, Identifiable {
        case search = "搜索"
        case detail = "详情"
        case toc = "目录"
        case content = "正文"

        var id: String { rawValue }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AppBackdrop()

                VStack(spacing: 0) {
                    Picker("沙箱分区", selection: $pane) {
                        ForEach(Pane.allCases) { value in
                            Text(value.rawValue).tag(value)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal, 18)
                    .padding(.top, 8)
                    .padding(.bottom, 10)

                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 16) {
                            switch pane {
                            case .sources:
                                boundaryCard
                                sourceListCard
                            case .page:
                                pageCard
                            case .debug:
                                boundaryCard
                                addressCard
                                scriptCard
                                resultCard
                            }
                        }
                        .padding(18)
                    }
                    .scrollIndicators(.hidden)
                }
            }
            .navigationTitle("JS 书源沙箱")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") { dismiss() }
                        .fontWeight(.semibold)
                }
            }
            .task {
                selectDefaultSource()
                await loadSampleIfNeeded()
            }
            .task(id: "\(selection?.app.id ?? "")-\(pane.rawValue)") {
                guard pane == .page, let selected = selection else {
                    pageModel = nil
                    return
                }
                let model = SourceLoginModel(
                    source: selected.app,
                    engineSource: selected.engine
                ) { state in
                    message = "页面会话已保存：\(state.rawValue)"
                }
                pageModel = model
                await model.prepare()
            }
        }
    }

    // MARK: 书源

    private var candidateSources: [(app: BookSource, engine: LegadoCore.BookSource)] {
        store.sources.compactMap { app in
            guard let engine = LegadoBridge.engineSource(from: app) else { return nil }
            return (app, engine)
        }
    }

    private var selection: (app: BookSource, engine: LegadoCore.BookSource)? {
        if let sourceID, let match = candidateSources.first(where: { $0.app.id == sourceID }) {
            return match
        }
        return candidateSources.first
    }

    private func selectDefaultSource() {
        guard sourceID == nil else { return }
        sourceID = candidateSources.first(where: { $0.app.enabled })?.app.id
            ?? candidateSources.first?.app.id
    }

    private func select(_ entry: (app: BookSource, engine: LegadoCore.BookSource)) {
        sourceID = entry.app.id
        customRule = ""
        pageModel = nil
        message = ""
        Task { await loadSampleIfNeeded() }
    }

    private func effectiveRule(_ engine: LegadoCore.BookSource) -> String {
        let custom = customRule.trimmingCharacters(in: .whitespacesAndNewlines)
        if !custom.isEmpty { return custom }
        switch stage {
        case .search: return engine.searchUrl ?? ""
        case .detail: return sampleBook.isEmpty ? engine.bookSourceUrl : sampleBook
        case .toc: return sampleTOC.isEmpty ? sampleBook : sampleTOC
        case .content: return sampleChapter.isEmpty ? sampleBook : sampleChapter
        }
    }

    // 沙箱里能填的「样本地址」，来自 `sampleAddresses`。
    @State private var sampleSearch = ""
    @State private var sampleBook = ""
    @State private var sampleTOC = ""
    @State private var sampleChapter = ""

    private func applySample(_ sample: (search: String?, book: String?, toc: String?, chapter: String?, note: String)) {
        sampleSearch = sample.search ?? ""
        sampleBook = sample.book ?? ""
        sampleTOC = sample.toc ?? ""
        sampleChapter = sample.chapter ?? ""
        sampleNote = sample.note
    }

    private func loadSampleIfNeeded() async {
        guard let source = selection?.engine, !isLoadingSample else { return }
        isLoadingSample = true
        let sample = await store.engine.sampleAddresses(source: source, keyword: keyword)
        applySample(sample)
        isLoadingSample = false
    }

    // MARK: 卡片

    private var boundaryCard: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.shield")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(theme.accent)
                .padding(.top, 1)

            VStack(alignment: .leading, spacing: 4) {
                Text("这里跑的是真书源")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(theme.text)
                Text("地址规则取自你选中的 3.0 书源，请求走与阅读时同一条传输层和私网闸门；书源要求 WebView 的地址由真实的 WKWebView 打开，不要求的走原生请求。")
                    .font(.system(size: 10.5))
                    .foregroundStyle(theme.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(13)
        .glassSurface(cornerRadius: 20, tint: theme.accent.opacity(0.08))
    }

    private var sourceListCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeading(text: "书库里的 3.0 书源", trailing: "\(candidateSources.count) 个可解析")

            if candidateSources.isEmpty {
                Text("书库里还没有能解析成 Legado 3.0 规则的书源。回到「书源」页导入一条书源 JSON，或从书源详情里打开登录页。")
                    .font(.system(size: 11))
                    .foregroundStyle(theme.tertiary)
                    .padding(13)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .glassSurface(cornerRadius: 18)
            } else {
                VStack(spacing: 8) {
                    ForEach(candidateSources, id: \.app.id) { entry in
                        let isSelected = selection?.app.id == entry.app.id
                        Button {
                            select(entry)
                        } label: {
                            HStack(alignment: .top, spacing: 10) {
                                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundStyle(isSelected ? theme.jade : theme.tertiary)
                                    .padding(.top, 2)

                                VStack(alignment: .leading, spacing: 3) {
                                    HStack(spacing: 6) {
                                        Text(entry.app.name)
                                            .font(.system(size: 12.5, weight: .semibold))
                                            .foregroundStyle(theme.text)
                                            .lineLimit(1)
                                        if entry.app.enabled {
                                            Text("已启用")
                                                .font(.system(size: 8.5, weight: .semibold))
                                                .foregroundStyle(theme.jade)
                                                .padding(.horizontal, 5)
                                                .padding(.vertical, 2)
                                                .glassCapsule(tint: theme.jade.opacity(0.12))
                                        }
                                    }
                                    Text(entry.engine.bookSourceName)
                                        .font(.system(size: 10))
                                        .foregroundStyle(theme.secondary)
                                        .lineLimit(1)
                                    Text(entry.engine.bookSourceUrl)
                                        .font(.system(size: 9.5, design: .monospaced))
                                        .foregroundStyle(theme.tertiary)
                                        .lineLimit(1)
                                }

                                Spacer(minLength: 0)

                                Image(systemName: "chevron.right")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(theme.tertiary.opacity(0.6))
                                    .padding(.top, 3)
                            }
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .glassSurface(
                                cornerRadius: 18,
                                tint: isSelected ? theme.jade.opacity(0.12) : nil,
                                interactive: true
                            )
                        }
                        .buttonStyle(PressableStyle(scale: 0.99))
                    }
                }

                if selection != nil {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("样本：\(sampleNote.isEmpty ? "正在从书源取真实地址…" : sampleNote)")
                            .font(.system(size: 10))
                            .foregroundStyle(theme.tertiary)
                        Text("搜索 \(sampleSearch.isEmpty ? "—" : sampleSearch)")
                            .font(.system(size: 9.5, design: .monospaced))
                            .foregroundStyle(theme.secondary)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .padding(14)
        .glassSurface(cornerRadius: 20)
    }

    private var pageCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeading(
                text: "书源页面",
                trailing: selection?.app.name ?? "未选择"
            )

            if selection == nil {
                Text("先在「书源」页签选中一条可解析的书源。")
                    .font(.system(size: 11))
                    .foregroundStyle(theme.tertiary)
                    .padding(13)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .glassSurface(cornerRadius: 18)
            } else if let pageModel {
                SourceLoginContent(model: pageModel, embedded: true)

                Button {
                    pageModel.finish()
                } label: {
                    Label("保存会话到本机", systemImage: "key.viewfinder")
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(theme.onAccent)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 11)
                        .background(theme.accentSolid, in: Capsule())
                }
                .buttonStyle(PressableStyle(scale: 0.98))

                if !message.isEmpty {
                    Text(message)
                        .font(.system(size: 10.5))
                        .foregroundStyle(theme.accent)
                }
            } else {
                ProgressView("正在生成书源页面…")
            }
        }
        .padding(14)
        .glassSurface(cornerRadius: 20)
    }

    private var addressCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeading(text: "地址规则", trailing: isLoadingSample ? "正在取样本" : "取自书源")

            Picker("阶段", selection: $stage) {
                ForEach(Stage.allCases) { value in
                    Text(value.rawValue).tag(value)
                }
            }
            .pickerStyle(.segmented)

            if let engine = selection?.engine {
                Text(effectiveRule(engine).isEmpty ? "这个书源没有配置该阶段的地址规则" : effectiveRule(engine))
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(effectiveRule(engine).isEmpty ? theme.tertiary : theme.secondary)
                    .lineLimit(4)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(11)
                    .glassSurface(cornerRadius: 16)
            }

            TextField("覆盖地址规则（留空则用书源的）", text: $customRule, axis: .vertical)
                .font(.system(size: 10.5, design: .monospaced))
                .lineLimit(1...3)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .glassSurface(cornerRadius: 14)

            if stage == .search {
                TextField("关键词", text: $keyword)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .glassSurface(cornerRadius: 14)
            }
        }
        .padding(14)
        .glassSurface(cornerRadius: 20)
    }

    private var scriptCard: some View {
        VStack(alignment: .leading, spacing: 9) {
            SectionHeading(text: "脚本", trailing: "按书源 webJs 语义执行")

            Toggle("用下面的脚本替换书源的 webJs", isOn: $useOverrideScript)
                .font(.system(size: 12))
                .tint(theme.jade)

            if useOverrideScript {
                TextEditor(text: $overrideScript)
                    .font(.system(size: 10.5, design: .monospaced))
                    .foregroundStyle(theme.secondary)
                    .scrollContentBackground(.hidden)
                    .padding(10)
                    .frame(height: 130)
                    .glassSurface(cornerRadius: 18)

                Text("脚本在真实页面里执行，`return` 的结果就是这一步的响应体。页面里 document / window 都可用；需要页面脚本自己发请求时，私网地址会被拦。")
                    .font(.system(size: 9.5))
                    .foregroundStyle(theme.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 9) {
                Button {
                    run()
                } label: {
                    Label("运行这一步", systemImage: "play.fill")
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(theme.onAccent)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(theme.accentSolid, in: Capsule())
                }
                .buttonStyle(PressableStyle(scale: 0.97))
                .disabled(isRunning || selection == nil)

                if isRunning { ProgressView().themedProgress() }
            }

            if !message.isEmpty {
                Text(message)
                    .font(.system(size: 10.5))
                    .foregroundStyle(theme.accent)
            }
        }
        .padding(14)
        .glassSurface(cornerRadius: 20)
    }

    private var resultCard: some View {
        VStack(alignment: .leading, spacing: 9) {
            SectionHeading(text: "执行日志", trailing: "\(logs.count) 步")

            if logs.isEmpty {
                Text("尚未运行。运行时会按上面这条地址规则真的发一次请求；书源写了 webView / webJs / 资源正则，都会在这一步如实生效。")
                    .font(.system(size: 11))
                    .foregroundStyle(theme.tertiary)
                    .padding(13)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .glassSurface(cornerRadius: 18)
            } else {
                VStack(spacing: 0) {
                    ForEach(logs) { line in
                        HStack(spacing: 9) {
                            Image(systemName: line.ok ? "checkmark.circle.fill" : "xmark.shield.fill")
                                .font(.system(size: 11))
                                .foregroundStyle(line.ok ? theme.jade : theme.accent)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(line.step)
                                    .font(.system(size: 11.5, weight: .semibold))
                                    .foregroundStyle(theme.text)
                                Text(line.detail)
                                    .font(.system(size: 10))
                                    .foregroundStyle(theme.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            Spacer(minLength: 6)
                            Text("\(line.milliseconds) ms")
                                .font(.system(size: 9, design: .rounded))
                                .foregroundStyle(theme.tertiary)
                                .monospacedDigit()
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 9)
                    }
                }
                .glassSurface(cornerRadius: 18)
            }

            if !preview.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    SectionHeading(text: "响应预览", trailing: "\(preview.count) 字")
                    Text(preview)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(theme.secondary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(13)
                .glassSurface(cornerRadius: 18)
            }

            if !traces.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    SectionHeading(text: "WebView 实际经过", trailing: "\(traces.count) 条")
                    ForEach(traces) { trace in
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(trace.mode.title) · HTTP \(trace.statusCode)\(trace.error == nil ? "" : " · 失败")")
                                .font(.system(size: 10.5, weight: .semibold))
                                .foregroundStyle(trace.error == nil ? theme.text : theme.accent)
                            Text(trace.url)
                                .font(.system(size: 9.5, design: .monospaced))
                                .foregroundStyle(theme.tertiary)
                                .lineLimit(1)
                            Text(describe(trace))
                                .font(.system(size: 9.5))
                                .foregroundStyle(theme.secondary)
                        }
                        .padding(.vertical, 4)
                    }
                }
                .padding(13)
                .glassSurface(cornerRadius: 18)
            }
        }
    }

    private func describe(_ trace: WebViewTraceEntry) -> String {
        var parts = ["\(trace.byteCount) 字节", "\(trace.elapsedMilliseconds) ms"]
        if trace.usedWebJs { parts.append("执行了 webJs") }
        if trace.delayMilliseconds > 0 { parts.append("额外等待 \(trace.delayMilliseconds) ms") }
        if let matched = trace.matchedSourceRegex { parts.append("资源正则命中 \(matched)") }
        if let error = trace.error { parts.append(error) }
        return parts.joined(separator: " · ")
    }

    // MARK: 运行

    private func run() {
        guard let selection else { return }
        let rule = effectiveRule(selection.engine)
        guard !rule.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            message = "这个书源没有配置该阶段的地址规则，先在上面填一条"
            return
        }
        isRunning = true
        message = ""
        logs = []
        preview = ""
        let script = useOverrideScript ? overrideScript : nil
        let keyword = keyword
        Task { @MainActor in
            // 轨迹由 sandbox 按执行作用域筛好返回：只含这一次留下的，
            // 不会把上一次、阅读时别的书源的请求显示成「这一步经过」。
            defer { isRunning = false }
            let result = await store.engine.sandbox(
                source: selection.engine,
                urlRule: rule,
                keyword: keyword,
                overrideScript: script
            )
            traces = result.traces
            logs = result.lines
            preview = result.preview
            message = result.lines.contains { !$0.ok } ? "这一步没有跑通，原因见下" : "这一步真实执行完成"
        }
    }
}
