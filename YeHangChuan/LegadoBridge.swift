import Foundation
import LegadoCore
import YeHangCore

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
    ///
    /// `chapterCount` 留 0：Legado 的搜索规则根本不返回章节数
    /// （`SearchBook.chapterWordCount` 是字数，而且上游从不填，恒为 -1）。
    /// 原来是拿字数当章节数填进去的，搜索页因此永远显示「0 章」。
    /// 真实章节数在拉完目录后由 `loadNetworkChapters` 写回。
    func appBook(sourceID: String, coverStyle: Int) -> Book {
        Book(
            id: appBookID,
            title: name,
            author: author.isEmpty ? "佚名" : author,
            kind: .novel,
            coverStyle: coverStyle,
            chapterCount: 0,
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
        StableID.hash(text)
    }
}

/// 跨进程稳定的字符串哈希。
///
/// Swift 的 `String.hashValue` 每次启动都会换种子，用它拼出来的 ID
/// 重启后就和上一次对不上。书籍 ID 早就换成了 FNV-1a，章节 ID 与段落 ID
/// 当时漏掉了 —— 而段落 ID 会被写进阅读位置和书签一起持久化，
/// 一旦对不上，重启后就会「记不住读到哪一段」。
enum StableID {
    static func hash(_ text: String) -> UInt64 {
        var hash: UInt64 = 0xCBF2_9CE4_8422_2325
        for byte in text.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01B3
        }
        return hash
    }

    /// 按书名挑一个封面配色。封面是持久化字段，必须跨启动一致，
    /// 所以不能直接用 `hashValue`（每次启动换种子 → 同一本书换色）。
    static func coverStyle(for title: String) -> Int {
        Int(hash(title) % 6)
    }
}

extension BookChapter {
    /// 引擎章节转成 App 章节。此时还没有正文，`paragraphs` 留空，
    /// 真正的正文在打开章节时按需拉取（见 `AppStore.loadNetworkContent`）。
    ///
    /// ID 必须跨启动稳定：章节会被缓存进快照，段落 ID 又是「章节 ID + 序号」，
    /// 用 `hashValue` 的话重启后同一章的段落 ID 全变，阅读位置和书签就失配了。
    func appChapter() -> Chapter {
        Chapter(
            id: "net-\(StableID.hash(bookUrl + "\u{0}" + url))",
            title: title,
            paragraphs: []
        )
    }
}

/// 把正文纯文本按空行切成段落。
///
/// 段落 ID 用内容寻址（章节 ID + 段落文本摘要），不是「章ID + 序号」：
/// 书源偶尔会在正文开头重复一遍章节标题，净化时删掉它，
/// 按序号编号会让后面每一段都错位，用户的书签就会跳到不相干的段落。
/// 内容寻址下，删掉、插入、重排任何一段，其余段落的 ID 都不变。
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

        let ids = ContentID.paragraphIDs(chapterID: chapterID, paragraphs: blocks)
        return zip(ids, blocks).map { Paragraph(id: $0, text: $1) }
    }
}
