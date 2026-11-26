import Foundation
import LegadoCore

/// App 的 `BookSource` 与 LegadoCore 的 `BookSource` 之间的转换。
///
/// 两边的字段并不一一对应：Legado 用 `bookSourceUrl` 表示站点根地址、
/// `searchUrl` / `ruleSearch` 等承载真正的规则，而 App 原先只有一个自由文本
/// 的 `rule`。这里把规则原文（也就是一条完整的 Legado 书源 JSON）解析成
/// LegadoCore 的结构化对象，让规则真正可执行；解析不了时退回 nil，
/// 界面上会明说「规则无法解析」，而不是假装能搜。
enum LegadoBridge {
    /// 把 App 书源翻译成引擎书源。`rule` 里必须是一条 Legado 书源 JSON 对象。
    static func engineSource(from source: BookSource) -> LegadoCore.BookSource? {
        let raw = source.rule.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty, let data = raw.data(using: .utf8) else { return nil }

        // 单条对象和「数组里一条」都认，用户粘贴哪种都行。
        guard let parsed = try? BookSourceImporter().decode(data),
              let decoded = parsed.first else {
            // 退化路径：规则不是完整 Legado JSON 时，至少用界面上的名称与地址
            // 拼一个只带元数据的书源，这样「测试连接」还能测域名可达性。
            return fallbackSource(from: source)
        }

        var result = decoded
        // 名称与地址以界面上编辑的为准，避免用户改了名字却仍显示旧名字。
        if !source.name.isEmpty { result.bookSourceName = source.name }
        result.enabled = source.enabled
        if result.bookSourceUrl.isEmpty, !source.host.isEmpty {
            result.bookSourceUrl = source.host
        }
        return result
    }

    /// 规则不是合法 Legado JSON 时的兜底：只有地址，没有解析规则。
    private static func fallbackSource(from source: BookSource) -> LegadoCore.BookSource? {
        let host = source.host.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !host.isEmpty else { return nil }
        var built = LegadoCore.BookSource(
            bookSourceUrl: host,
            bookSourceName: source.name.isEmpty ? host : source.name
        )
        built.enabled = source.enabled
        return built
    }

    /// 引擎书源能不能真的搜书：必须有搜索地址 + 搜索规则。
    static func isSearchable(_ source: LegadoCore.BookSource) -> Bool {
        source.searchUrl?.isEmpty == false && source.ruleSearch != nil
    }

    /// 引擎书源能不能读正文：必须有目录规则与正文规则。
    static func isReadable(_ source: LegadoCore.BookSource) -> Bool {
        source.ruleToc?.chapterList?.isEmpty == false && source.ruleContent?.content?.isEmpty == false
    }

    /// 按规则内容判断该标成 JSON 还是 JS，而不是听用户在分段控件上点的。
    /// 用户粘一条含 `@js:` 的规则却选了「选择器规则」，界面上会显示错误的信息。
    static func detectedKind(ruleJSON: String) -> SourceKind? {
        guard let data = ruleJSON.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return BookSource.containsJavaScript(object) ? .js : .json
    }

    /// 引擎书源的 id 是 `bookSourceUrl`，界面上书源的 id 是 UUID。
    /// 检索结果回来时只知道引擎 id，要靠地址反查回界面的那条。
    static func appSourceID(engineID: String, in sources: [BookSource]) -> String? {
        let normalized = URLHost.normalize(engineID)
        return sources.first { source in
            if source.host == engineID { return true }
            let host = URLHost.normalize(source.host)
            return !host.isEmpty && host == normalized
        }?.id
    }
}

// MARK: - 引擎结果 → App 模型

extension SearchBook {
    /// 稳定的书架 ID：同一本书来自不同书源时是不同的条目，
    /// 但同一来源重复搜索命中的必须是同一本。用 FNV-1a 而不是 `hashValue`，
    /// 后者每次启动种子都不同，重启后就认不出「已在书架」了。
    var appBookID: String { "net-\(Self.stableHash(origin + "\u{0}" + bookURL))" }

    /// 搜索结果转成书架用的 `Book`。
    func appBook(sourceID: String, coverStyle: Int) -> Book {
        Book(
            id: appBookID,
            title: name,
            author: author.isEmpty ? "佚名" : author,
            kind: .novel,
            coverStyle: coverStyle,
            chapterCount: chapterWordCount > 0 ? chapterWordCount : 0,
            progress: 0,
            lastPosition: "未开始",
            pageCount: nil,
            duration: nil,
            isFinished: false,
            sourceID: sourceID,
            networkBookURL: bookURL,
            networkTocURL: tocURL.isEmpty ? nil : tocURL
        )
    }

    /// 跨进程稳定的 64 位哈希（FNV-1a）。
    static func stableHash(_ text: String) -> UInt64 {
        var hash: UInt64 = 0xCBF2_9CE4_8422_2325
        for byte in text.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01B3
        }
        return hash
    }
}

extension BookChapter {
    /// 引擎章节转成 App 章节。此时还没有正文，`paragraphs` 留空，
    /// 真正的正文在打开章节时按需拉取（见 `AppStore.loadNetworkContent`）。
    func appChapter() -> Chapter {
        Chapter(
            id: "net-\(title.hashValue)-\(index)-\(url.count)",
            title: title,
            paragraphs: []
        )
    }
}

/// 把正文纯文本按空行切成段落，段落 ID 用「章节 ID + 序号」，
/// 与分页锚点、书签定位用的是同一套 ID，改字号后不会漂。
enum TextSegmenter {
    static func paragraphs(from text: String, chapterID: String) -> [Paragraph] {
        let normalized = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")

        let rawLines = normalized.components(separatedBy: "\n")
        var blocks: [String] = []
        var buffer: [String] = []

        func flush() {
            let joined = buffer.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            buffer.removeAll()
            guard !joined.isEmpty else { return }
            blocks.append(joined)
        }

        for line in rawLines {
            if line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                flush()
            } else {
                buffer.append(line.trimmingCharacters(in: .whitespaces))
            }
        }
        flush()

        // 没有空行分隔时退化成按行切，避免整章变成一大段。
        if blocks.count <= 1, rawLines.count > 1 {
            blocks = rawLines
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
        }

        return blocks.enumerated().map { index, text in
            Paragraph(id: "\(chapterID)-p\(index)", text: text)
        }
    }
}
