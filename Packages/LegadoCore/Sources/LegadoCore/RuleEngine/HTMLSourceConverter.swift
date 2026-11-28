import Foundation

/// 把「整段 HTML 即书源」的 JSON 转成一组可执行的 Legado 规则。
///
/// 起点中文那份 JSON 只有 `html` / `login` 字段，没有阅读 3.0 的
/// `searchUrl` / `ruleSearch`。HTML 自己暴露 `search/info/chapter/content/login`
/// 五个入口函数，这里用 `<webjs>` 把它们接到统一的搜索 / 目录 / 正文流水线。
public enum HTMLBookSourceConverter {
    public static func convert(
        jsonData: Data,
        name: String? = nil,
        enabled: Bool = true
    ) -> BookSource? {
        let root = try? JSONSerialization.jsonObject(with: jsonData)
        let object: [String: Any]?
        switch root {
        case let dictionary as [String: Any]: object = dictionary
        case let array as [[String: Any]]: object = array.first
        default: object = nil
        }
        guard let object, let html = object["html"] as? String, !html.isEmpty else { return nil }
        let id = (object["bookSourceUrl"] as? String) ?? (object["host"] as? String) ?? ""
        guard !id.isEmpty else { return nil }
        HTMLSourceRegistry.shared.register(html: html, for: id)

        func web(_ body: String) -> String { "<webjs>\(body)</webjs>" }

        var source = BookSource(
            bookSourceUrl: id,
            bookSourceName: (object["bookSourceName"] as? String).flatMap { $0.isEmpty ? nil : $0 }
                ?? (name?.isEmpty == false ? name! : "HTML 书源")
        )
        source.enabled = enabled
        source.enabledExplore = true
        source.loginUrl = object["login"] as? Bool == true ? "html://settings" : nil
        source.searchUrl = "data:text/plain,search"

        var search = SearchRule()
        search.bookList = web("return JSON.parse(await search(String(key), page || 1));")
        search.name = "name"
        search.author = "author"
        search.intro = "intro"
        search.kind = "kind"
        search.coverUrl = "coverUrl"
        search.wordCount = "wordCount"
        search.lastChapter = "latestChapterTitle"
        search.bookUrl = "bookUrl"
        source.ruleSearch = search

        var info = BookInfoRule()
        info.`init` = web("return JSON.parse(await info(baseUrl));")
        info.name = "name"
        info.author = "author"
        info.intro = "intro"
        info.kind = "kind"
        info.coverUrl = "coverUrl"
        info.wordCount = "wordCount"
        info.lastChapter = "latestChapterTitle"
        info.tocUrl = web("""
            const item = typeof result === 'string' ? JSON.parse(result || '{}') : (result || {});
            return 'data:text/plain,' + encodeURIComponent(String(item.tocUrl || ''));
            """)
        source.ruleBookInfo = info

        var toc = TocRule()
        toc.chapterList = web("return JSON.parse(await chapter(String(result), baseUrl));")
        toc.chapterName = "name"
        toc.chapterUrl = web("return 'data:text/plain,' + encodeURIComponent(String(result.chapterId || ''));")
        toc.isVip = web("return result.isVip ? 'true' : '';")
        toc.isVolume = web("return result.isVolume ? 'true' : '';")
        toc.updateTime = "tag"
        source.ruleToc = toc

        var content = ContentRule()
        content.content = web("return await content(String(result), String(result));")
        source.ruleContent = content
        return source
    }
}
