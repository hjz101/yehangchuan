import Foundation
import LegadoCore

/// 给 `BuiltinDemoSource` 提供本机内容，让示例书源在没有网络时也能走完
/// 搜索 → 详情 → 目录 → 正文。内容取自 App 自带的演示数据，不发真实请求。
/// 仅 Debug 构建编译；分发包不含离线示例内容与 `yhdemo://` 协议。
#if DEBUG

enum BuiltinDemoContent {
    static func install() {
        BuiltinDemoSource.register()
        BuiltinDemoSource.setResponder { request in
            guard let url = request.url,
                  url.scheme?.lowercased() == BuiltinDemoSource.scheme else { return nil }
            return response(for: url)
        }
    }

    private static func response(for url: URL) -> Data? {
        let parts = url.path.split(separator: "/").map(String.init)
        guard let endpoint = parts.first else { return nil }
        let object: Any
        switch endpoint {
        case "search":
            let keyword = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?.first(where: { $0.name == "q" })?.value ?? ""
            let matches = MockData.searchResults.filter { book in
                keyword.isEmpty || book.title.localizedCaseInsensitiveContains(keyword)
                    || book.author.localizedCaseInsensitiveContains(keyword)
            }
            object = ["books": matches.map { book in
                [
                    "title": book.title,
                    "author": book.author,
                    "intro": "夜航船内置的离线示例书目，用于验证书源链路。",
                    "url": "\(BuiltinDemoSource.baseURL)/book/\(book.id)"
                ] as [String: Any]
            }]
        case "book":
            guard let id = parts.dropFirst().first,
                  let book = MockData.searchResults.first(where: { $0.id == id }) else { return nil }
            object = [
                "title": book.title,
                "author": book.author,
                "intro": "夜航船内置的离线示例书目，用于验证书源链路。",
                "tocUrl": "\(BuiltinDemoSource.baseURL)/toc/\(book.id)"
            ]
        case "toc":
            guard let id = parts.dropFirst().first,
                  let book = MockData.searchResults.first(where: { $0.id == id }) else { return nil }
            object = ["chapters": MockData.chapters(for: book).enumerated().map { index, chapter in
                [
                    "name": chapter.title,
                    "url": "\(BuiltinDemoSource.baseURL)/chapter/\(book.id)/\(index)"
                ] as [String: Any]
            }]
        case "chapter":
            guard let id = parts.dropFirst().first,
                  let rawIndex = parts.dropFirst(2).first, let index = Int(rawIndex),
                  let book = MockData.searchResults.first(where: { $0.id == id }) else { return nil }
            let chapters = MockData.chapters(for: book)
            guard chapters.indices.contains(index) else { return nil }
            let content = chapters[index].paragraphs.map(\.text).joined(separator: "\n\n")
            object = ["content": content]
        default:
            return nil
        }
        return try? JSONSerialization.data(withJSONObject: object, options: [.fragmentsAllowed])
    }
}

#endif
