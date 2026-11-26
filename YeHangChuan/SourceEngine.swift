import Foundation
import LegadoCore

/// 书源引擎的门面：把 LegadoCore 的 Search / Detail / Toc / Content 包成 App 需要的样子。
///
/// 全部是真实网络请求。规则解析、相对地址、Cookie、限速都由 LegadoCore 负责，
/// 这一层只做两件事：中英文协议对齐，以及把「私网地址默认拒绝」落实在传输层。
@MainActor
@Observable
final class SourceEngine {
    /// 最近一次失败的说明，界面上可以直接显示。
    var lastError: String?

    @ObservationIgnored private let transport: any HTTPTransport
    @ObservationIgnored private let search: BookSearchService
    @ObservationIgnored private let books: NetworkBookService
    @ObservationIgnored private let debugger: BookSourceDebugger

    init() {
        // LegadoCore 本身不拦私网地址，而 App 在启用书源时承诺过「私网默认拒绝」。
        // 请求最终都会走这个 transport，所以拦截放在这里才是真的拦得住，
        // 包括书源 JS 里 java.ajax 发起的请求。
        let guarded = HostGuardedTransport(base: URLSessionHTTPTransport())
        transport = guarded
        search = BookSearchService(transport: guarded)
        books = NetworkBookService(transport: guarded)
        debugger = BookSourceDebugger(transport: guarded)
    }

    // MARK: - 搜索

    /// 并发检索多个书源，结果通过回调逐条返回，界面可以边搜边显示。
    func search(
        keyword: String,
        sources: [LegadoCore.BookSource],
        onOutcome: @escaping @MainActor (SourceSearchOutcome) -> Void
    ) async -> [SourceSearchOutcome] {
        var collected: [SourceSearchOutcome] = []
        for await outcome in search.searchOutcomes(keyword: keyword, page: 1, sources: sources) {
            collected.append(outcome)
            await onOutcome(outcome)
        }
        return collected
    }

    // MARK: - 目录与正文

    /// 拉取一本书的目录。搜索结果里的 `SearchBook` 已经带 tocURL，
    /// 所以这里先把它转成引擎 `Book` 再取目录。
    func chapters(
        searchBook: SearchBook,
        source: LegadoCore.BookSource
    ) async -> (book: LegadoCore.Book, chapters: [BookChapter], error: String?) {
        let detail = await books.loadDetail(searchBook: searchBook, source: source)
        var book = detail.book
        // 详情规则没给目录地址时，退回搜索结果里那个。
        if book.tocUrl.isEmpty { book.tocUrl = searchBook.tocURL }

        let report = await books.loadChapters(book: book, source: source)
        if report.chapters.isEmpty {
            lastError = report.diagnostics.first?.message
            return (book, [], report.diagnostics.first?.message ?? "目录为空")
        }
        return (book, report.chapters, nil)
    }

    /// 拉取单章正文，并按空行切成段落。
    /// `engineBook` 是目录阶段的引擎 `Book`，保证相对地址与变量跟目录一致。
    func content(
        engineBook: LegadoCore.Book,
        chapter: BookChapter,
        source: LegadoCore.BookSource
    ) async -> (paragraphs: [Paragraph], error: String?) {
        let report = await books.loadContent(book: engineBook, chapter: chapter, source: source)
        let body = [report.content, report.supplementalContent ?? ""]
            .filter { !$0.isEmpty }
            .joined(separator: "\n\n")
        guard !body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            let message = report.diagnostics.first?.message ?? "正文为空"
            lastError = message
            return ([], message)
        }
        let chapterID = "net-\(chapter.bookUrl.hashValue)-\(chapter.index)"
        return (TextSegmenter.paragraphs(from: body, chapterID: chapterID), nil)
    }

    // MARK: - 调试与连通性

    /// 五步调试：配置 → 搜索 → 详情 → 目录 → 正文，每步都有真实耗时与诊断。
    func debug(source: LegadoCore.BookSource, keyword: String) async -> BookSourceDebugReport {
        await debugger.run(source: source, keyword: keyword)
    }

    /// 「测试连接」：跑一次最小搜索，能搜到书就算通。
    /// 没有搜索规则的书源退化成取一次书源地址，只看域名是否可达。
    func probe(source: LegadoCore.BookSource) async -> (ok: Bool, milliseconds: Int, message: String) {
        let started = ProcessInfo.processInfo.systemUptime

        guard LegadoBridge.isSearchable(source) else {
            let reachable = await canReach(source.bookSourceUrl)
            let ms = Int((ProcessInfo.processInfo.systemUptime - started) * 1000)
            return reachable
                ? (true, ms, "地址可达；但缺少搜索规则，无法检索书目")
                : (false, ms, "地址不可达；且缺少搜索规则")
        }

        let outcome = await search.search(keyword: "长风", page: 1, source: source)
        let ms = Int((ProcessInfo.processInfo.systemUptime - started) * 1000)
        if !outcome.books.isEmpty {
            return (true, ms, "检索正常，命中 \(outcome.books.count) 本")
        }
        if let diagnostic = outcome.diagnostics.first(where: { $0.severity == .error }) {
            return (false, ms, diagnostic.message)
        }
        return (false, ms, "规则可执行但没有命中结果")
    }

    private func canReach(_ rawURL: String) async -> Bool {
        guard let url = URL(string: rawURL), let scheme = url.scheme?.lowercased(),
              ["http", "https"].contains(scheme) else { return false }
        var request = URLRequest(url: url)
        request.httpMethod = "HEAD"
        request.timeoutInterval = 8
        guard let response = try? await transport.data(for: request) else { return false }
        return (200..<500).contains(response.statusCode)
    }
}

// MARK: - 私网拦截

/// 把 App 的私网判定加在传输层，任何经过引擎的请求都会被检查一次。
///
/// 放在这里而不是放在书源启用时，是因为书源的规则里可能写着别的域名，
/// 也可能在 JS 里拼出新地址——只看 `bookSourceUrl` 是拦不住的。
private struct HostGuardedTransport: HTTPTransport {
    let base: any HTTPTransport

    func data(for request: URLRequest) async throws -> HTTPResponse {
        if let host = request.url?.host, URLHost.isPrivate(host) {
            throw SourceEngineError.privateHost(host)
        }
        return try await base.data(for: request)
    }
}

enum SourceEngineError: LocalizedError {
    case privateHost(String)

    var errorDescription: String? {
        switch self {
        case .privateHost(let host):
            "已拦截私网地址：\(host)"
        }
    }
}
