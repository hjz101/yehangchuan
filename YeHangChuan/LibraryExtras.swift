import SwiftUI
import UniformTypeIdentifiers
import UIKit
import CoreFoundation
import AVFoundation
import LegadoCore

// MARK: - Import

enum ImportMethod: String, CaseIterable, Identifiable {
    case file = "本地文件"
    case link = "链接"
    case clipboard = "剪贴板"

    var id: String { rawValue }
    var symbol: String {
        switch self {
        case .file: "folder"
        case .link: "link"
        case .clipboard: "doc.on.clipboard"
        }
    }
}

struct SmartImportSheet: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var method: ImportMethod = .file
    @State private var showPicker = false
    @State private var draft: ImportDraft?
    @State private var message: String?
    @State private var isParsing = false
    @State private var linkText = "https://books.example/夜航船.txt"

    private var allowedTypes: [UTType] {
        [
            UTType.plainText,
            UTType.zip,
            UTType(filenameExtension: "epub"),
            UTType(filenameExtension: "mp3"),
            UTType(filenameExtension: "m4a"),
            UTType(filenameExtension: "m4b")
        ].compactMap { $0 }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AppBackdrop()

                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        GlassSegmented(
                            items: ImportMethod.allCases,
                            title: { $0.rawValue },
                            selection: $method
                        )

                        sourcePanel

                        if let draft {
                            draftPreview(draft)
                        } else if let message {
                            messagePanel(message)
                        }

                        formatNote
                    }
                    .padding(18)
                }
                .scrollIndicators(.hidden)
            }
            .navigationTitle("智能导入")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("取消") { dismiss() }
                }
            }
        }
        .fileImporter(
            isPresented: $showPicker,
            allowedContentTypes: allowedTypes,
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                if let url = urls.first { importFile(url) }
            case .failure(let error):
                message = "文件选择失败：\(error.localizedDescription)"
            }
        }
    }

    private var sourcePanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            switch method {
            case .file:
                Button {
                    showPicker = true
                } label: {
                    actionTile(
                        symbol: "doc.badge.plus",
                        title: "选择 TXT / EPUB / ZIP / 音频",
                        detail: "TXT 会真实解析编码与章节，其它格式读取元数据后模拟导入"
                    )
                }
                .buttonStyle(PressableStyle(scale: 0.985))
            case .link:
                VStack(alignment: .leading, spacing: 10) {
                    TextField("https 链接", text: $linkText)
                        .font(.system(size: 14))
                        .foregroundStyle(Palette.text)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                        .glassSurface(cornerRadius: 18)

                    Button {
                        importLink()
                    } label: {
                        actionTile(symbol: "arrow.down.doc", title: "读取链接", detail: "主动下载并预览，不会在后台请求")
                    }
                    .buttonStyle(PressableStyle(scale: 0.985))
                }
            case .clipboard:
                Button {
                    importClipboard()
                } label: {
                    actionTile(symbol: "doc.on.clipboard", title: "从剪贴板识别", detail: "读取文字后自动判断书名、作者与章节")
                }
                .buttonStyle(PressableStyle(scale: 0.985))
            }

            if isParsing {
                HStack(spacing: 9) {
                    ProgressView()
                    Text("正在识别编码与章节…")
                        .font(.system(size: 12))
                        .foregroundStyle(Palette.secondary)
                }
                .padding(.horizontal, 4)
            }
        }
        .padding(14)
        .glassSurface(cornerRadius: 24)
    }

    private func actionTile(symbol: String, title: String, detail: String) -> some View {
        HStack(spacing: 13) {
            Image(systemName: symbol)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Palette.onAccent)
                .frame(width: 42, height: 42)
                .background(Palette.accentSolid, in: RoundedRectangle(cornerRadius: 13, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 14.5, weight: .semibold))
                    .foregroundStyle(Palette.text)
                Text(detail)
                    .font(.system(size: 10.5))
                    .foregroundStyle(Palette.secondary)
                    .multilineTextAlignment(.leading)
            }

            Spacer(minLength: 0)

            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(Palette.tertiary.opacity(0.6))
        }
        .contentShape(Rectangle())
    }

    private func draftPreview(_ draft: ImportDraft) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeading(text: "导入预览", trailing: "\(draft.chapters.count) 章")

            HStack(spacing: 14) {
                BookCover(
                    book: Book(
                        id: "preview",
                        title: draft.title,
                        author: draft.author,
                        kind: draft.kind,
                        coverStyle: StableID.coverStyle(for: draft.title),
                        chapterCount: draft.chapters.count,
                        progress: 0,
                        lastPosition: "未开始",
                        pageCount: nil,
                        duration: nil,
                        isFinished: false
                    ),
                    cornerRadius: 9
                )
                .frame(width: 72)

                VStack(alignment: .leading, spacing: 5) {
                    Text(draft.title)
                        .font(.system(size: 19, weight: .semibold, design: .serif))
                        .foregroundStyle(Palette.text)
                        .lineLimit(2)

                    Text("\(draft.author) · \(draft.kind.rawValue)")
                        .font(.system(size: 11.5))
                        .foregroundStyle(Palette.secondary)

                    Text(draft.detail)
                        .font(.system(size: 10.5))
                        .foregroundStyle(Palette.tertiary)
                        .lineLimit(2)
                }

                Spacer(minLength: 0)
            }

            VStack(alignment: .leading, spacing: 7) {
                ForEach(Array(draft.chapters.prefix(4))) { chapter in
                    HStack(spacing: 8) {
                        Text(chapter.title)
                            .font(.system(size: 12.5, weight: .medium))
                            .foregroundStyle(Palette.text)
                            .lineLimit(1)
                        Spacer()
                        Text("\(chapter.paragraphs.reduce(0) { $0 + $1.text.count }) 字")
                            .font(.system(size: 10, design: .rounded))
                            .foregroundStyle(Palette.tertiary)
                            .monospacedDigit()
                    }
                    .padding(.vertical, 3)
                }
            }
            .padding(12)
            .glassSurface(cornerRadius: 18)

            Button {
                store.importBook(draft)
                dismiss()
            } label: {
                Text("加入书架")
                    .readableButtonStyle(tint: Palette.accentSolid)
            }
            .buttonStyle(PressableStyle(scale: 0.97))
        }
        .padding(15)
        .glassSurface(cornerRadius: 24, tint: Palette.accent.opacity(0.06))
    }

    private func messagePanel(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: "info.circle")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Palette.gold)
            Text(text)
                .font(.system(size: 12))
                .foregroundStyle(Palette.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(13)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassSurface(cornerRadius: 18)
    }

    private var formatNote: some View {
        Text("TXT 与 EPUB 为真实解析；漫画压缩包与音频会在读取文件信息后以演示章节进入书架。所有内容只留在这台设备。")
            .font(.system(size: 10.5))
            .foregroundStyle(Palette.tertiary)
            .padding(.horizontal, 2)
    }

    // MARK: Parsing

    private func importFile(_ url: URL) {
        isParsing = true
        message = nil
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }

        let ext = url.pathExtension.lowercased()
        let name = url.deletingPathExtension().lastPathComponent

        if ext == "txt", let data = try? Data(contentsOf: url), let text = Self.decode(data) {
            let parsed = Self.parse(text: text, fallbackTitle: name)
            draft = ImportDraft(
                title: parsed.title,
                author: parsed.author,
                kind: .novel,
                detail: "本机 TXT · \(Self.encodingName(data)) · \(parsed.chapters.count) 章",
                chapters: parsed.chapters
            )
        } else if ext == "epub" {
            // EPUB 的真实解析能力已在 LegadoCore 里：按需从 ZIP 内读章节标题与正文，
            // 不向磁盘解包。导入时把正文一并取出来塞进草稿，阅读页无需改动。
            do {
                let service = LocalBookService.live()
                let report = try service.openFile(at: url)
                var failures = 0
                let chapters = report.chapters.enumerated().map { index, source in
                    let chapterID = "epub-\(index)"
                    let paragraphs: [Paragraph]
                    do {
                        let text = try service.loadContent(book: report.book, chapter: source).content
                        paragraphs = TextSegmenter.paragraphs(from: text, chapterID: chapterID)
                        if paragraphs.isEmpty { failures += 1 }
                    } catch {
                        failures += 1
                        paragraphs = []
                    }
                    // 不能静默塞空正文：那会让阅读页永远停在转圈。
                    // 单章失败放一段明确的说明，让用户知道是解析问题而不是书没内容。
                    let finalParagraphs = paragraphs.isEmpty
                        ? [Paragraph(id: "\(chapterID)-error", text: "本章正文解析失败，可能是 EPUB 内该文件损坏或格式不受支持。")]
                        : paragraphs
                    return Chapter(
                        id: "epub-\(index)-\(source.title.prefix(12))",
                        title: source.title,
                        paragraphs: finalParagraphs
                    )
                }
                guard failures < chapters.count || chapters.isEmpty else {
                    isParsing = false
                    message = "EPUB 正文解析失败：所有章节都读不出内容，请换一个文件。"
                    return
                }
                let note = failures > 0 ? " · \(failures) 章解析失败" : ""
                draft = ImportDraft(
                    title: report.book.name.isEmpty ? name : report.book.name,
                    author: report.book.author.isEmpty ? "本地 EPUB" : report.book.author,
                    kind: .novel,
                    detail: "本机 EPUB · 真实解析 · \(chapters.count) 章\(note)",
                    chapters: chapters
                )
            } catch {
                message = "EPUB 解析失败：\(error.localizedDescription)"
            }
        } else if ["mp3", "m4a", "m4b"].contains(ext) {
            // 文件选择权限是一次性的，真要长期播放必须复制进自己的沙箱。
            var storedName: String?
            var realDuration: String?
            if let base = LibraryStore.shared.directory {
                let folder = base.appendingPathComponent("AudioBooks", isDirectory: true)
                let fileName = "\(UUID().uuidString).\(ext)"
                let target = folder.appendingPathComponent(fileName)
                do {
                    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                    try FileManager.default.copyItem(at: url, to: target)
                    storedName = fileName
                    let seconds = CMTimeGetSeconds(AVAsset(url: target).duration)
                    if seconds.isFinite, seconds > 0 { realDuration = AudioPlayer.label(seconds) }
                } catch {
                    storedName = nil
                }
            }
            let chapters = storedName == nil
                ? Self.demoChapters(title: name, count: 2)
                : [Chapter(
                    id: "\(name)-audio",
                    title: "完整音频",
                    paragraphs: [Paragraph(id: "\(name)-audio-note", text: "本机音频文件，请用播放器收听。")]
                )]
            draft = ImportDraft(
                title: name,
                author: storedName == nil ? "本地音频" : "本机音频文件",
                kind: .audio,
                detail: storedName == nil
                    ? "\(ext.uppercased()) · 未能保存文件，使用演示音轨"
                    : "\(ext.uppercased()) · 真实音频 · \(realDuration ?? "时长待读取")",
                chapters: chapters,
                audioFileName: storedName,
                durationLabel: realDuration
            )
        } else {
            let kind: BookKind = ext == "zip" || ext == "cbz" ? .comic : .novel
            let chapters = Self.demoChapters(title: name, count: kind == .comic ? 6 : 4)
            draft = ImportDraft(
                title: name,
                author: "本地文件",
                kind: kind,
                detail: "\(ext.uppercased()) · 未解析文件内容，使用演示章节",
                chapters: chapters
            )
        }

        isParsing = false
    }

    private func importLink() {
        guard let url = URL(string: linkText.trimmingCharacters(in: .whitespaces)),
              url.scheme?.hasPrefix("http") == true else {
            message = "请输入有效的 http(s) 链接。"
            return
        }
        isParsing = true
        Task { @MainActor in
            let response = await store.backend.call("GET", url.absoluteString, base: 320)
            isParsing = false
            guard response.ok else {
                message = "链接读取失败：模拟网关离线。"
                return
            }
            let name = url.deletingPathExtension().lastPathComponent.removingPercentEncoding ?? "网络书稿"
            let chapters = Self.demoChapters(title: name, count: 5)
            draft = ImportDraft(
                title: name,
                author: url.host() ?? "网络来源",
                kind: .novel,
                detail: "链接下载 · \(response.milliseconds) ms · 演示解析",
                chapters: chapters
            )
        }
    }

    private func importClipboard() {
        guard let text = UIPasteboard.general.string, !text.isEmpty else {
            message = "剪贴板里没有可识别的文字。"
            return
        }
        let parsed = Self.parse(text: text, fallbackTitle: "剪贴板书稿")
        draft = ImportDraft(
            title: parsed.title,
            author: parsed.author,
            kind: .novel,
            detail: "剪贴板 · \(parsed.chapters.count) 章",
            chapters: parsed.chapters
        )
    }

    static func decode(_ data: Data) -> String? {
        if let value = String(data: data, encoding: .utf8) { return value }
        let gb = String.Encoding(
            rawValue: UInt(
                CFStringConvertEncodingToNSStringEncoding(
                    CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue)
                )
            )
        )
        if let value = String(data: data, encoding: gb) { return value }
        if let value = String(data: data, encoding: .utf16) { return value }
        return String(data: data, encoding: .isoLatin1)
    }

    static func encodingName(_ data: Data) -> String {
        String(data: data, encoding: .utf8) != nil ? "UTF-8" : "GB18030 / UTF-16"
    }

    static func parse(text: String, fallbackTitle: String) -> (title: String, author: String, chapters: [Chapter]) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let lines = trimmed.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces) }
        let authorLine = lines.prefix(8).first { $0.contains("作者") }
        let author = authorLine?
            .replacingOccurrences(of: "作者", with: "")
            .trimmingCharacters(in: CharacterSet(charactersIn: "：: 　"))
            .trimmingCharacters(in: .whitespaces)
        let title = lines.first { line in
            !line.isEmpty && line.count <= 30 && !line.contains("作者") && !line.hasPrefix("第")
        } ?? fallbackTitle

        let pattern = #"(?m)^[ \t]*(第[0-9一二三四五六七八九十百千零两]+[章节卷回][^\n]{0,40})$"#
        let regex = try? NSRegularExpression(pattern: pattern)
        let ns = trimmed as NSString
        let matches = regex?.matches(in: trimmed, range: NSRange(location: 0, length: ns.length)) ?? []

        var chapters: [Chapter] = []
        let chapterStarts = matches.map { $0.range }

        func paragraphs(from content: String) -> [Paragraph] {
            let rows = content.components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
            let merged = rows.isEmpty ? [content.trimmingCharacters(in: .whitespacesAndNewlines)] : rows
            return merged
                .flatMap { row -> [String] in
                    guard row.count > 480 else { return [row] }
                    return stride(from: 0, to: row.count, by: 480).map { offset in
                        let start = row.index(row.startIndex, offsetBy: offset)
                        let end = row.index(start, offsetBy: 480, limitedBy: row.endIndex) ?? row.endIndex
                        return String(row[start..<end])
                    }
                }
                .filter { !$0.isEmpty }
                .map { Paragraph(id: UUID().uuidString, text: $0) }
        }

        let prefaceEnd = chapterStarts.first?.location ?? ns.length
        if prefaceEnd > 40 {
            let preface = ns.substring(with: NSRange(location: 0, length: prefaceEnd))
            let body = paragraphs(from: preface).filter { $0.text != title && $0.text != authorLine }
            if !body.isEmpty {
                chapters.append(Chapter(id: UUID().uuidString, title: "序", paragraphs: body))
            }
        }

        for (index, range) in chapterStarts.enumerated() {
            let titleRange = range
            let contentStart = range.location + range.length
            let contentEnd = index + 1 < chapterStarts.count ? chapterStarts[index + 1].location : ns.length
            guard contentEnd >= contentStart else { continue }
            let heading = ns.substring(with: titleRange).trimmingCharacters(in: .whitespaces)
            let content = ns.substring(with: NSRange(location: contentStart, length: contentEnd - contentStart))
            let body = paragraphs(from: content)
            if !body.isEmpty {
                chapters.append(Chapter(id: UUID().uuidString, title: heading, paragraphs: body))
            }
        }

        if chapters.isEmpty {
            let chunkSize = 1_800
            let total = trimmed.count
            let count = max(1, Int(ceil(Double(total) / Double(chunkSize))))
            for index in 0..<count {
                let start = trimmed.index(trimmed.startIndex, offsetBy: index * chunkSize)
                let end = trimmed.index(start, offsetBy: chunkSize, limitedBy: trimmed.endIndex) ?? trimmed.endIndex
                chapters.append(
                    Chapter(
                        id: UUID().uuidString,
                        title: index == 0 ? "正文" : "第 \(index + 1) 节",
                        paragraphs: paragraphs(from: String(trimmed[start..<end]))
                    )
                )
            }
        }

        var cleaned: [Chapter] = []
        var indexByTitle: [String: Int] = [:]
        for chapter in chapters {
            if let index = indexByTitle[chapter.title] {
                cleaned[index].paragraphs.append(contentsOf: chapter.paragraphs)
            } else {
                indexByTitle[chapter.title] = cleaned.count
                cleaned.append(chapter)
            }
        }

        return (title, author?.isEmpty == false ? author! : "佚名", cleaned)
    }

    static func demoChapters(title: String, count: Int) -> [Chapter] {
        (1...max(count, 1)).map { index in
            let source = MockData.genericChapters[(index - 1) % MockData.genericChapters.count]
            return Chapter(
                id: "\(title)-\(index)-\(UUID().uuidString.prefix(4))",
                title: "第 \(index) 章 · \(source.title.components(separatedBy: " · ").last ?? "正文")",
                paragraphs: source.paragraphs.map {
                    Paragraph(id: UUID().uuidString, text: $0.text, comments: $0.comments)
                }
            )
        }
    }
}

// MARK: - Comic Reader

struct ComicReaderView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    let book: Book

    @State private var page = 0
    @State private var mode: ComicMode = .page
    @State private var showChrome = true
    @State private var cached = false

    enum ComicMode: String, CaseIterable, Identifiable {
        case page = "页漫"
        case strip = "条漫"
        var id: String { rawValue }
    }

    private var pageCount: Int {
        max(book.pageCount ?? book.chapterCount * 8, 8)
    }

    var body: some View {
        ZStack {
            Color(hex: 0x080C12).ignoresSafeArea()

            if mode == .page {
                TabView(selection: $page) {
                    ForEach(0..<pageCount, id: \.self) { index in
                        ComicPageArt(book: book, page: index, total: pageCount)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 74)
                            .tag(index)
                            .onTapGesture { toggleChrome() }
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
            } else {
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(0..<pageCount, id: \.self) { index in
                            ComicPageArt(book: book, page: index, total: pageCount)
                                .padding(.horizontal, 14)
                                .onTapGesture { toggleChrome() }
                        }
                    }
                    .padding(.vertical, 74)
                }
                .scrollIndicators(.hidden)
            }

            VStack {
                if showChrome { topBar }
                Spacer()
                if showChrome { bottomBar }
            }

            EyeCareLayer(settings: store.eyeCare)
        }
        .statusBarHidden(!showChrome)
        .persistentSystemOverlays(.hidden)
        .onAppear {
            page = min(max(Int((book.progress * Double(pageCount - 1)).rounded()), 0), pageCount - 1)
            // 图片缓存是真实文件，重新进入时按磁盘状态显示图标。
            cached = ImageCacheStore.isCached(bookID: book.id)
            syncProgress()
        }
        .onChange(of: page) { _, _ in
            syncProgress()
        }
    }

    private var topBar: some View {
        GlassEffectContainer(spacing: 10) {
            HStack(spacing: 10) {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                        .glassCircle(diameter: 40)
                }
                .buttonStyle(PressableStyle())

                Spacer()

                VStack(spacing: 1) {
                    Text(book.title)
                        .font(.system(size: 13, weight: .semibold, design: .serif))
                        .foregroundStyle(.white)
                    Text("第 \(page + 1) 页 / \(pageCount)")
                        .font(.system(size: 10, design: .rounded))
                        .foregroundStyle(.white.opacity(0.62))
                        .monospacedDigit()
                }
                .padding(.horizontal, 17)
                .padding(.vertical, 8)
                .glassCapsule(tint: .black.opacity(0.28))

                Spacer()

                Button {
                    if cached {
                        ImageCacheStore.remove(bookID: book.id)
                        cached = false
                        store.showToast("已清除 \(book.title) 的图片缓存")
                    } else if let bytes = ImageCacheStore.store(bookID: book.id, title: book.title, pages: pageCount) {
                        cached = true
                        store.showToast("已缓存 \(pageCount) 页图片 · \(ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file))")
                    } else {
                        store.showToast("缓存写入失败，请检查存储空间")
                    }
                } label: {
                    Image(systemName: cached ? "arrow.down.circle.fill" : "arrow.down.circle")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(cached ? Palette.jade : .white)
                        .glassCircle(diameter: 40)
                }
                .buttonStyle(PressableStyle())
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
    }

    private var bottomBar: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                Text("\(page + 1)")
                Slider(
                    value: Binding(
                        get: { Double(page) },
                        set: { page = min(max(Int($0.rounded()), 0), pageCount - 1) }
                    ),
                    in: 0...Double(pageCount - 1)
                )
                .tint(Palette.accent)
                Text("\(pageCount)")
            }
            .font(.system(size: 10, weight: .semibold, design: .rounded))
            .foregroundStyle(.white.opacity(0.7))
            .monospacedDigit()
            .padding(.horizontal, 16)
            .padding(.vertical, 11)
            .glassSurface(cornerRadius: 20, tint: .black.opacity(0.35))

            HStack(spacing: 0) {
                Button {
                    withAnimation { page = max(page - 1, 0) }
                } label: {
                    toolLabel("上一页", "chevron.left")
                }
                .buttonStyle(PressableStyle())
                .disabled(page == 0)
                .opacity(page == 0 ? 0.35 : 1)

                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                        mode = mode == .page ? .strip : .page
                    }
                } label: {
                    toolLabel(mode.rawValue, mode == .page ? "rectangle.portrait" : "rectangle.portrait.and.arrow.right")
                }
                .buttonStyle(PressableStyle())

                Button {
                    store.speech.load(
                        book: book,
                        chapterTitle: "第 \(page + 1) 页",
                        text: "第 \(page + 1) 页画面。\(book.title)的镜头从夜色里推进，人物沿着灯光向前走。"
                    )
                    store.speech.toggle()
                    store.showToast("已开始朗读画面描述")
                } label: {
                    toolLabel("朗读", "speaker.wave.2")
                }
                .buttonStyle(PressableStyle())

                Button {
                    withAnimation { page = min(page + 1, pageCount - 1) }
                } label: {
                    toolLabel("下一页", "chevron.right")
                }
                .buttonStyle(PressableStyle())
                .disabled(page == pageCount - 1)
                .opacity(page == pageCount - 1 ? 0.35 : 1)
            }
            .padding(.vertical, 7)
            .glassSurface(cornerRadius: 26, tint: .black.opacity(0.24))
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 4)
    }

    private func toolLabel(_ title: String, _ symbol: String) -> some View {
        VStack(spacing: 5) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .medium))
            Text(title)
                .font(.system(size: 9.5, weight: .medium))
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
        .contentShape(Rectangle())
    }

    private func toggleChrome() {
        withAnimation(.spring(response: 0.34, dampingFraction: 0.86)) {
            showChrome.toggle()
        }
    }

    private func syncProgress() {
        store.updateProgress(
            bookID: book.id,
            progress: Double(page + 1) / Double(pageCount),
            position: "第 \(page + 1) 页 / \(pageCount)"
        )
    }
}

struct ComicPageArt: View {
    let book: Book
    let page: Int
    let total: Int

    private var colors: (Color, Color) { Palette.cover(book.coverStyle + page) }

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let height = geometry.size.height
            ZStack {
                LinearGradient(colors: [colors.0, colors.1], startPoint: .topLeading, endPoint: .bottomTrailing)

                Circle()
                    .fill(.white.opacity(0.08))
                    .frame(width: width * 0.72)
                    .blur(radius: 30)
                    .offset(x: width * 0.24, y: -height * 0.22)

                VStack(spacing: 10) {
                    HStack(spacing: 10) {
                        panel(height: height * 0.3)
                        panel(height: height * 0.3)
                    }

                    panel(height: height * 0.4)
                        .overlay(alignment: .topLeading) {
                            Text(page % 3 == 0 ? "夜航 · \(book.title)" : "画面 \(page + 1)")
                                .font(.system(size: 12, weight: .semibold, design: .serif))
                                .foregroundStyle(.white.opacity(0.9))
                                .padding(12)
                        }
                }
                .padding(16)

                VStack {
                    Spacer()
                    HStack {
                        Text("\(book.title) · 第 \(page + 1) 页")
                            .font(.system(size: 10, weight: .medium))
                        Spacer()
                        Text("\(page + 1) / \(total)")
                            .monospacedDigit()
                    }
                    .foregroundStyle(.white.opacity(0.6))
                    .padding(.horizontal, 22)
                    .padding(.bottom, 18)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(.white.opacity(0.12), lineWidth: 0.8)
            }
            .shadow(color: .black.opacity(0.5), radius: 18, y: 10)
        }
        .aspectRatio(0.68, contentMode: .fit)
    }

    private func panel(height: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: 4, style: .continuous)
            .fill(.black.opacity(0.18))
            .overlay {
                LinearGradient(
                    colors: [.white.opacity(0.14), .clear, .black.opacity(0.18)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
            }
            .overlay(alignment: .center) {
                Image(systemName: page % 2 == 0 ? "moon.stars" : "water.waves")
                    .font(.system(size: 28, weight: .ultraLight))
                    .foregroundStyle(.white.opacity(0.28))
            }
            .frame(maxWidth: .infinity)
            .frame(height: height)
    }
}

// MARK: - Bookmarks

struct BookmarkListSheet: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    let book: Book
    let onSelect: (Bookmark) -> Void

    @State private var editing: Bookmark?

    private var items: [Bookmark] { store.bookmarks(for: book.id) }

    var body: some View {
        NavigationStack {
            ZStack {
                AppBackdrop()

                ScrollView {
                    VStack(spacing: 9) {
                        if items.isEmpty {
                            ContentUnavailableView(
                                "还没有书签",
                                systemImage: "bookmark",
                                description: Text("阅读时点底部的书签按钮即可保存当前位置")
                            )
                            .padding(.top, 40)
                        } else {
                            ForEach(items) { bookmark in
                                Button {
                                    onSelect(bookmark)
                                    dismiss()
                                } label: {
                                    HStack(spacing: 12) {
                                        Image(systemName: "bookmark.fill")
                                            .font(.system(size: 13))
                                            .foregroundStyle(Palette.accent)
                                            .frame(width: 30, height: 30)
                                            .background(Palette.accent.opacity(0.12), in: Circle())

                                        VStack(alignment: .leading, spacing: 3) {
                                            Text(bookmark.chapterTitle)
                                                .font(.system(size: 13.5, weight: .medium))
                                                .foregroundStyle(Palette.text)
                                                .lineLimit(1)

                                            Text("\(bookmark.percentLabel) · \(bookmark.createdAt.formatted(date: .abbreviated, time: .shortened))")
                                                .font(.system(size: 10))
                                                .foregroundStyle(Palette.tertiary)

                                            if !bookmark.note.isEmpty {
                                                Text(bookmark.note)
                                                    .font(.system(size: 10.5, design: .serif))
                                                    .foregroundStyle(Palette.secondary)
                                                    .lineLimit(2)
                                            }
                                        }

                                        Spacer()

                                        Image(systemName: "chevron.right")
                                            .font(.system(size: 11, weight: .bold))
                                            .foregroundStyle(Palette.tertiary.opacity(0.5))
                                    }
                                    .padding(12)
                                    .glassSurface(cornerRadius: 18)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(PressableStyle(scale: 0.985))
                                .contextMenu {
                                    Button {
                                        editing = bookmark
                                    } label: {
                                        Label("编辑备注", systemImage: "square.and.pencil")
                                    }

                                    Button(role: .destructive) {
                                        store.removeBookmark(bookmark.id)
                                    } label: {
                                        Label("删除书签", systemImage: "trash")
                                    }
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 18)
                    .padding(.bottom, 28)
                }
                .scrollIndicators(.hidden)
            }
            .navigationTitle("书签")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") { dismiss() }
                        .fontWeight(.semibold)
                }
            }
        }
        .sheet(item: $editing) { bookmark in
            BookmarkNoteSheet(bookmark: bookmark)
                .presentationDetents([.height(300)])
                .presentationCornerRadius(30)
        }
    }
}

struct BookmarkNoteSheet: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    let bookmark: Bookmark
    @State private var note = ""

    var body: some View {
        NavigationStack {
            ZStack {
                AppBackdrop()

                VStack(alignment: .leading, spacing: 12) {
                    Text(bookmark.chapterTitle)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Palette.secondary)

                    TextEditor(text: $note)
                        .font(.system(size: 14, design: .serif))
                        .foregroundStyle(Palette.text)
                        .scrollContentBackground(.hidden)
                        .padding(10)
                        .frame(maxHeight: .infinity)
                        .glassSurface(cornerRadius: 18)

                    Button {
                        store.updateBookmarkNote(bookmark.id, note: note)
                        dismiss()
                    } label: {
                        Text("保存备注")
                            .readableButtonStyle(tint: Palette.accentSolid)
                    }
                    .buttonStyle(PressableStyle(scale: 0.97))
                }
                .padding(18)
            }
            .navigationTitle("书签备注")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("取消") { dismiss() }
                }
            }
            .onAppear { note = bookmark.note }
        }
    }
}

// MARK: - Spoken reading

struct ListenSheet: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    let book: Book
    let chapterTitle: String
    let text: String

    private var speech: SpeechPlayer { store.speech }

    var body: some View {
        ZStack {
            AppBackdrop()

            VStack(spacing: 0) {
                header
                Spacer(minLength: 20)
                cover
                Spacer(minLength: 18)
                titleBlock
                wave
                scrubber
                transport
                speedPicker
                Spacer(minLength: 10)
            }
            .padding(.horizontal, 26)
            .padding(.bottom, 22)

            EyeCareLayer(settings: store.eyeCare)
        }
        .onAppear {
            if speech.title != book.title || speech.chapterTitle != chapterTitle {
                speech.load(book: book, chapterTitle: chapterTitle, text: text)
            }
        }
        .onDisappear {
            if speech.isPlaying { speech.pause() }
        }
    }

    private var header: some View {
        HStack {
            Button {
                dismiss()
            } label: {
                Image(systemName: "chevron.down")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Palette.text)
                    .glassCircle(diameter: 38)
            }
            .buttonStyle(PressableStyle())

            Spacer()

            VStack(spacing: 2) {
                Text("系统朗读")
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(1.6)
                    .foregroundStyle(Palette.tertiary)
                Text("真实语音 · 无需音频文件")
                    .font(.system(size: 10.5))
                    .foregroundStyle(Palette.secondary)
            }

            Spacer()

            Button {
                speech.stop()
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Palette.text)
                    .glassCircle(diameter: 38)
            }
            .buttonStyle(PressableStyle())
        }
        .padding(.top, 8)
    }

    private var cover: some View {
        BookCover(book: book, cornerRadius: 26, prominent: true)
            .frame(maxWidth: 180)
            .shadow(color: Palette.accent.opacity(0.18), radius: 26, y: 14)
    }

    private var titleBlock: some View {
        VStack(spacing: 5) {
            Text(chapterTitle)
                .font(.system(size: 23, weight: .semibold, design: .serif))
                .foregroundStyle(Palette.text)
                .lineLimit(1)

            Text("\(book.title) · \(book.author)")
                .font(.system(size: 11.5))
                .foregroundStyle(Palette.secondary)
        }
    }

    private var wave: some View {
        TimelineView(.animation(minimumInterval: 0.16, paused: !speech.isPlaying)) { context in
            let phase = context.date.timeIntervalSinceReferenceDate
            HStack(spacing: 3) {
                ForEach(0..<44, id: \.self) { index in
                    let value = speech.isPlaying
                        ? 0.35 + abs(sin(phase * 2.4 + Double(index) * 0.42)) * 0.65
                        : 0.18
                    Capsule()
                        .fill(index < Int(speech.progress * 44) ? Palette.accent : Palette.faint)
                        .frame(width: 3, height: 8 + CGFloat(value) * 30)
                }
            }
            .frame(height: 40)
        }
        .padding(.top, 16)
    }

    private var scrubber: some View {
        VStack(spacing: 6) {
            Slider(
                value: Binding(
                    get: { speech.progress },
                    set: { speech.seek(to: $0) }
                ),
                in: 0...1
            )
            .tint(Palette.accent)

            HStack {
                Text(speech.elapsedLabel)
                Spacer()
                Text(speech.remainingLabel)
            }
            .font(.system(size: 10.5, weight: .medium, design: .rounded))
            .foregroundStyle(Palette.tertiary)
            .monospacedDigit()
        }
        .padding(.top, 14)
    }

    private var transport: some View {
        HStack(spacing: 32) {
            Button { speech.skip(-80) } label: {
                Image(systemName: "gobackward.15")
                    .font(.system(size: 23, weight: .medium))
                    .foregroundStyle(Palette.text)
            }
            .buttonStyle(PressableStyle())

            Button { speech.toggle() } label: {
                Image(systemName: speech.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 26, weight: .bold))
                    .foregroundStyle(Palette.onAccent)
                    .frame(width: 72, height: 72)
                    .background(Palette.accentSolid, in: Circle())
                    .shadow(color: Palette.accentSolid.opacity(0.35), radius: 16, y: 8)
            }
            .buttonStyle(PressableStyle(scale: 0.92))

            Button { speech.skip(120) } label: {
                Image(systemName: "goforward.30")
                    .font(.system(size: 23, weight: .medium))
                    .foregroundStyle(Palette.text)
            }
            .buttonStyle(PressableStyle())
        }
        .padding(.top, 18)
    }

    private var speedPicker: some View {
        GlassSegmented(
            items: [1.0, 1.25, 1.5, 2.0],
            title: { SpeedLabel.text($0) },
            selection: Binding(
                get: { speech.speed },
                set: { speech.setSpeed($0) }
            )
        )
        .frame(width: 210)
        .padding(.top, 20)
    }
}

// MARK: - Source switch

struct SourceSwitchSheet: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    let book: Book
    /// 返回是否切换成功。成功才关面板，失败把原因留在这一行。
    let onSwitch: (BookSource) async -> Bool

    @State private var probes: [String: SourceProbe] = [:]
    /// 换源是真去搜同名书再验证，要花几秒。正在换的那条书源要显示进度，
    /// 并且期间禁止重复点，避免并发提交两份章节。
    @State private var switchingID: String?
    /// 验证失败的原因，直接显示在对应书源那一行下面。
    @State private var failures: [String: String] = [:]

    private var sources: [BookSource] { store.sources.filter(\.enabled) }

    var body: some View {
        NavigationStack {
            ZStack {
                AppBackdrop()

                ScrollView {
                    VStack(spacing: 9) {
                        ForEach(sources) { source in
                            let probe = probes[source.id]
                            let switching = switchingID == source.id
                            VStack(alignment: .leading, spacing: 6) {
                                HStack(spacing: 12) {
                                    Image(systemName: source.kind == .js ? "curlybraces" : "doc.text")
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundStyle(Palette.jade)
                                        .frame(width: 34, height: 34)
                                        .background(Palette.jade.opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(source.name)
                                            .font(.system(size: 14, weight: .medium))
                                            .foregroundStyle(Palette.text)
                                        Text(statusText(source: source, probe: probe, switching: switching))
                                            .font(.system(size: 10))
                                            .foregroundStyle(statusTint(source: source, probe: probe))
                                            .lineLimit(2)
                                    }

                                    Spacer()

                                    if switching {
                                        ProgressView()
                                    } else {
                                        Button {
                                            startSwitch(source)
                                        } label: {
                                            Text(book.sourceID == source.id ? "当前" : "切换")
                                                .font(.system(size: 11.5, weight: .semibold))
                                                .foregroundStyle(book.sourceID == source.id ? Palette.secondary : Palette.onAccent)
                                                .padding(.horizontal, 12)
                                                .padding(.vertical, 7)
                                                .background {
                                                    if book.sourceID != source.id {
                                                        Capsule().fill(Palette.accentSolid)
                                                    } else {
                                                        Capsule().fill(Palette.faint)
                                                    }
                                                }
                                        }
                                        .buttonStyle(PressableStyle())
                                        .disabled(book.sourceID == source.id || switchingID != nil)
                                    }
                                }
                            }
                            .padding(12)
                            .glassSurface(cornerRadius: 18)
                        }

                        Text("切换会在这个书源里检索同名书，并验证详情、目录与正文都读得到才提交。验证期间阅读位置会按章节标题迁移。")
                            .font(.system(size: 10.5))
                            .foregroundStyle(Palette.tertiary)
                            .padding(.top, 10)
                    }
                    .padding(.horizontal, 18)
                    .padding(.bottom, 28)
                }
                .scrollIndicators(.hidden)
            }
            .navigationTitle("切换书源")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("取消") { dismiss() }
                }
            }
            .task {
                // 换源前先真实探一次，不把「能不能用」留到切换之后才发现。
                for source in sources {
                    guard let engineSource = LegadoBridge.engineSource(from: source) else {
                        probes[source.id] = SourceProbe(
                            id: source.id, name: source.name, ok: false,
                            milliseconds: 0, message: "规则无法解析"
                        )
                        continue
                    }
                    let result = await store.engine.probe(source: engineSource)
                    probes[source.id] = SourceProbe(
                        id: source.id, name: source.name, ok: result.ok,
                        milliseconds: result.milliseconds, message: result.message
                    )
                }
            }
        }
    }

    /// 探测状态、正在切换、上次验证失败，三种信息合并成一行。
    private func statusText(source: BookSource, probe: SourceProbe?, switching: Bool) -> String {
        if switching { return "正在检索同名书并验证正文…" }
        if let failure = failures[source.id] { return failure }
        return probe.map { "\($0.milliseconds) ms · \($0.message)" } ?? "正在检测…"
    }

    private func statusTint(source: BookSource, probe: SourceProbe?) -> Color {
        if failures[source.id] != nil { return Palette.accent }
        return probe?.ok == false ? Palette.accent : Palette.tertiary
    }

    /// 点击切换：交给上层真正换源，失败就把原因留在这一行。
    private func startSwitch(_ source: BookSource) {
        switchingID = source.id
        failures[source.id] = nil
        Task { @MainActor in
            let ok = await onSwitch(source)
            switchingID = nil
            guard !ok else {
                // 成功就直接收起面板，不必让用户再点一次「完成」。
                dismiss()
                return
            }
            // 上层只弹了 toast，这里补一句更具体的原因。
            failures[source.id] = store.toast ?? "切换失败"
        }
    }
}

// MARK: - Shared button label

extension View {
    func readableButtonStyle(tint: Color) -> some View {
        self
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(Palette.onAccent)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(tint, in: Capsule())
    }
}
