import Foundation
import AVFoundation
import LegadoCore

/// 「本地文件」导入的唯一入口：把一次文件选择的结果，解析成可以直接加入书架的草稿。
///
/// 三件事以前都做错了，这里一并改掉：
/// 1. **不允许静默降级**。读不出来就给原因，绝不悄悄塞一段演示正文 ——
///    用户会在书架里看到一本"导入成功"的假书，翻两页才发现不是自己的文件。
/// 2. **不在主线程干重活**。EPUB 要解开压缩包、音频要复制并读时长、漫画要建页索引，
///    全都放到后台；界面先把转圈画出来，再等结果。
/// 3. **iCloud 占位文件先下载再读**。直接 `Data(contentsOf:)` 对还没下载到本机的
///    文件会报「文件不存在」，而用户看到的文件明明就在那儿。
enum LocalImportReader {

    /// 解析结果。失败必须带一句人话，界面上直接显示。
    enum Outcome: Sendable {
        case draft(ImportDraftBox)
        case failure(String)
    }

    /// `ImportDraft` 里有 UUID，跨线程传要求 Sendable；这里只做一层壳，
    /// 语义上与 `ImportDraft` 等价。
    struct ImportDraftBox: Sendable {
        var title: String
        var author: String
        var kind: BookKind
        var detail: String
        var chapters: [Chapter]
        var audioFileName: String?
        var durationLabel: String?
        var pageCount: Int?
        var comicFileName: String?

        func makeDraft() -> ImportDraft {
            ImportDraft(
                title: title,
                author: author,
                kind: kind,
                detail: detail,
                chapters: chapters,
                audioFileName: audioFileName,
                durationLabel: durationLabel,
                pageCount: pageCount,
                comicFileName: comicFileName
            )
        }
    }

    /// 支持的扩展名。选文件时不再按 UTType 过滤（cbz / cbr 在系统里没有正式声明，
    /// 过滤会把它们整片置灰），改在这里按扩展名判定，不认识就明确拒绝。
    static let audioExtensions: Set<String> = ["mp3", "m4a", "m4b"]
    static let comicExtensions: Set<String> = ["zip", "cbz", "rar", "cbr", "7z"]
    static let supportedExtensions: Set<String> =
        Set(["txt", "epub"]).union(audioExtensions).union(comicExtensions)

    static func read(_ url: URL) async -> Outcome {
        await Task.detached(priority: .userInitiated) {
            do {
                return try readSynchronously(url)
            } catch {
                return .failure(reason(for: error, url: url))
            }
        }.value
    }

    // MARK: - 读取

    private static func readSynchronously(_ url: URL) throws -> Outcome {
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }

        let ext = url.pathExtension.lowercased()
        let name = url.deletingPathExtension().lastPathComponent

        guard supportedExtensions.contains(ext) else {
            return .failure("暂不支持 .\(ext.isEmpty ? "无扩展名" : ext) 文件。可以导入 TXT、EPUB、CBZ / ZIP / RAR / 7z 漫画，以及 mp3 / m4a / m4b 音频。")
        }

        // 统一先把文件落到自己的沙箱里再读：iCloud 云端文件、第三方文件提供方给的
        // 临时 URL 都会在授权结束或面板关闭后失效，边读边失效最难查。
        let local = try copyIntoSandbox(url)

        switch ext {
        case "txt":
            defer { try? FileManager.default.removeItem(at: local) }
            return try readText(local, name: name)
        case "epub":
            defer { try? FileManager.default.removeItem(at: local) }
            return try readEPUB(local, name: name)
        case let value where audioExtensions.contains(value):
            return try readAndClean(local) { try readAudio(local, name: name, ext: ext) }
        default:
            return try readAndClean(local) { try readComic(local, name: name, ext: ext) }
        }
    }

    /// 音频 / 漫画导入失败时，刚复制进沙箱的副本没有任何草稿引用，留着就是垃圾。
    /// 成功时必须保留：草稿（以及加入书架后的书）要靠这份文件播放 / 翻页。
    private static func readAndClean(_ local: URL, _ body: () throws -> Outcome) throws -> Outcome {
        do {
            let outcome = try body()
            if case .failure = outcome {
                try? FileManager.default.removeItem(at: local)
            }
            return outcome
        } catch {
            try? FileManager.default.removeItem(at: local)
            throw error
        }
    }

    /// 删除草稿引用、但还没有加入书架的沙箱副本（音频 / 漫画）。
    /// TXT / EPUB 解析完就删了临时文件，不会在目录里留下副本。
    static func discardImportCopy(for draft: ImportDraft) {
        guard let base = LibraryStore.shared.directory else { return }
        let manager = FileManager.default
        if let name = draft.audioFileName {
            let url = base.appendingPathComponent(Kind.audio.rawValue, isDirectory: true)
                .appendingPathComponent(name)
            try? manager.removeItem(at: url)
        }
        if let name = draft.comicFileName {
            let url = base.appendingPathComponent(Kind.comics.rawValue, isDirectory: true)
                .appendingPathComponent(name)
            try? manager.removeItem(at: url)
        }
    }

    private static func readText(_ url: URL, name: String) throws -> Outcome {
        let data = try Data(contentsOf: url, options: .mappedIfSafe)
        guard let text = SmartImportSheet.decode(data),
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return .failure("这个 TXT 读不出文字：可能是加密文件，或编码无法识别。")
        }
        let parsed = SmartImportSheet.parse(text: text, fallbackTitle: name)
        guard !parsed.chapters.isEmpty else {
            return .failure("TXT 里没有可显示的正文。")
        }
        return .draft(ImportDraftBox(
            title: parsed.title,
            author: parsed.author,
            kind: .novel,
            detail: "本机 TXT · \(SmartImportSheet.encodingName(data)) · \(parsed.chapters.count) 章",
            chapters: parsed.chapters
        ))
    }

    private static func readEPUB(_ url: URL, name: String) throws -> Outcome {
        let draft = try makeEPUBDraft(from: url, name: name, detailPrefix: "本机 EPUB")
        return .draft(draft)
    }

    /// 从内存里的字节解析 EPUB。链接导入拿到的是 `Data`，没有沙箱文件，
    /// 与本地文件共用同一条解析路径，避免两套解析逻辑慢慢长歪。
    static func readEPUBData(_ data: Data, name: String) throws -> Outcome {
        let temp = FileManager.default.temporaryDirectory
            .appendingPathComponent("yehang-epub-\(UUID().uuidString).epub")
        try data.write(to: temp, options: .atomic)
        defer { try? FileManager.default.removeItem(at: temp) }
        let draft = try makeEPUBDraft(from: temp, name: name, detailPrefix: "链接 EPUB")
        return .draft(draft)
    }

    private static func makeEPUBDraft(from file: URL, name: String, detailPrefix: String) throws -> ImportDraftBox {
        let service = LocalBookService.live()
        let report = try service.openFile(at: file)
        guard !report.chapters.isEmpty else {
            throw ImportError.storage("EPUB 里没有找到章节。")
        }
        // 整包只开一次：以前是每章都重新打开并遍历整个 zip，
        // 200 章的书等于扫了 200 遍压缩包目录。
        let contents = try service.loadContents(book: report.book, chapters: report.chapters)
        var failures = 0
        var chapters: [Chapter] = []
        for (index, source) in report.chapters.enumerated() {
            let chapterID = "epub-\(index)"
            let text = contents.indices.contains(index) ? contents[index].content : ""
            var paragraphs = TextSegmenter.paragraphs(from: text, chapterID: chapterID)
            if paragraphs.isEmpty {
                failures += 1
                // 单章失败放一段明确的说明：阅读页不该停在转圈，也不该假装有正文。
                let detail = contents.indices.contains(index)
                    ? contents[index].diagnostics.first?.message
                    : nil
                paragraphs = [Paragraph(
                    id: "\(chapterID)-error",
                    text: detail ?? "本章正文解析失败，可能是 EPUB 内该文件损坏或格式不受支持。"
                )]
            }
            chapters.append(Chapter(
                id: "\(chapterID)-\(source.title.prefix(12))",
                title: source.title,
                paragraphs: paragraphs
            ))
        }
        guard failures < chapters.count else {
            throw ImportError.storage("EPUB 正文解析失败：所有章节都读不出内容。")
        }
        let note = failures > 0 ? " · \(failures) 章解析失败" : ""
        return ImportDraftBox(
            title: report.book.name.isEmpty ? name : report.book.name,
            author: report.book.author.isEmpty ? "佚名" : report.book.author,
            kind: .novel,
            detail: "\(detailPrefix) · 真实解析 · \(chapters.count) 章\(note)",
            chapters: chapters
        )
    }

    private static func readAudio(_ url: URL, name: String, ext: String) throws -> Outcome {
        let duration = durationLabel(of: url)
        return .draft(ImportDraftBox(
            title: name,
            author: "本机音频文件",
            kind: .audio,
            detail: "\(ext.uppercased()) · 真实音频 · \(duration ?? "时长待读取")",
            chapters: [Chapter(
                id: "\(name)-audio",
                title: "完整音频",
                paragraphs: [Paragraph(id: "\(name)-audio-note", text: "本机音频文件，请用播放器收听。")]
            )],
            audioFileName: url.lastPathComponent,
            durationLabel: duration
        ))
    }

    private static func readComic(_ url: URL, name: String, ext: String) throws -> Outcome {
        let report = try LocalBookService.live().inspectComic(at: url)
        guard report.pageCount > 0 else {
            return .failure("压缩包里没有找到图片页。")
        }
        let chapters = report.chapterTitles.map { title in
            let count = report.pages.filter { $0.chapter == title }.count
            return Chapter(
                id: "comic-\(title.prefix(16))",
                title: title,
                paragraphs: [Paragraph(
                    id: "comic-\(title)-note",
                    text: "\(title) · \(count) 页，请在漫画阅读器中查看。"
                )]
            )
        }
        return .draft(ImportDraftBox(
            title: name,
            author: "本机漫画",
            kind: .comic,
            detail: "\(ext.uppercased()) · 真实解包 · \(report.pageCount) 页 · \(chapters.count) 话",
            chapters: chapters,
            pageCount: report.pageCount,
            comicFileName: url.lastPathComponent
        ))
    }

    // MARK: - 落盘

    private enum Kind: String {
        case books = "ImportedBooks"
        case audio = "AudioBooks"
        case comics = "Comics"
    }

    /// 把外部文件复制进沙箱，返回沙箱里的副本。
    ///
    /// 走 `NSFileCoordinator`：iCloud 与第三方文件提供方的 URL 需要协调读取，
    /// 未下载的云端文件还要先触发下载 —— 否则 `Data(contentsOf:)` 只会得到
    /// 「文件不存在」，而用户眼皮底下明明有那个文件。
    private static func copyIntoSandbox(_ url: URL) throws -> URL {
        guard let base = LibraryStore.shared.directory else {
            throw ImportError.storage("找不到本机的存储目录，无法保存导入的文件。")
        }
        let kind: Kind = {
            switch url.pathExtension.lowercased() {
            case let ext where audioExtensions.contains(ext): return .audio
            case let ext where comicExtensions.contains(ext): return .comics
            default: return .books
            }
        }()
        let folder = base.appendingPathComponent(kind.rawValue, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let target = folder.appendingPathComponent("\(UUID().uuidString).\(url.pathExtension.lowercased())")

        try downloadIfNeeded(url)
        var coordinationError: NSError?
        var copyError: Error?
        NSFileCoordinator().coordinate(readingItemAt: url, options: [.withoutChanges], error: &coordinationError) { readable in
            do { try FileManager.default.copyItem(at: readable, to: target) }
            catch { copyError = error }
        }
        if let copyError {
            try? FileManager.default.removeItem(at: target)
            throw copyError
        }
        if let coordinationError {
            try? FileManager.default.removeItem(at: target)
            throw coordinationError
        }
        guard FileManager.default.fileExists(atPath: target.path) else {
            throw ImportError.storage("文件没能复制到本机，请重新选择。")
        }
        return target
    }

    private static func downloadIfNeeded(_ url: URL) throws {
        let keys: Set<URLResourceKey> = [.isUbiquitousItemKey, .ubiquitousItemDownloadingStatusKey]
        guard let values = try? url.resourceValues(forKeys: keys),
              values.isUbiquitousItem == true else { return }
        if values.ubiquitousItemDownloadingStatus == .current { return }
        try? FileManager.default.startDownloadingUbiquitousItem(at: url)
        // 给它一点时间落地：云端文件通常几秒内完成，超时就交给后面的复制报错。
        for _ in 0..<50 {
            if let status = try? url.resourceValues(forKeys: [.ubiquitousItemDownloadingStatusKey])
                .ubiquitousItemDownloadingStatus, status == .current { return }
            Thread.sleep(forTimeInterval: 0.1)
        }
    }

    // MARK: - 辅助

    private static func durationLabel(of url: URL) -> String? {
        let asset = AVURLAsset(url: url)
        // 同步读 `duration` 在文件就绪前会返回 indefinite，改用异步加载。
        let semaphore = DispatchSemaphore(value: 0)
        var seconds: Double = 0
        Task {
            if let duration = try? await asset.load(.duration) {
                seconds = CMTimeGetSeconds(duration)
            }
            semaphore.signal()
        }
        // 后台线程上等它，不影响界面。
        semaphore.wait()
        guard seconds.isFinite, seconds > 0 else { return nil }
        return formatDuration(seconds)
    }

    /// 与 `AudioPlayer.label` 同一种写法，但那个方法在主 actor 上，
    /// 这里的解析跑在后台线程，所以自带一份。
    private static func formatDuration(_ value: Double) -> String {
        let total = Int(value.rounded())
        return String(format: "%02d:%02d", total / 60, total % 60)
    }

    private static func reason(for error: Error, url: URL) -> String {
        if let error = error as? LocalizedError, let description = error.errorDescription {
            return "\(url.lastPathComponent)：\(description)"
        }
        let nsError = error as NSError
        if nsError.domain == NSCocoaErrorDomain, nsError.code == NSFileReadNoSuchFileError {
            return "\(url.lastPathComponent)：文件读不到。如果它在 iCloud 里，请先下载到本机再导入。"
        }
        return "\(url.lastPathComponent)：\(error.localizedDescription)"
    }

    enum ImportError: LocalizedError {
        case storage(String)
        var errorDescription: String? {
            switch self {
            case .storage(let text): text
            }
        }
    }
}
