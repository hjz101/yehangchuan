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
    @ObservationIgnored private let explorer: BookExploreService
    @ObservationIgnored private let switcher: BookSourceSwitchService

    init() {
        // 把 App 的私网判定注入 LegadoCore 的唯一闸门。JS 桥里的 java.ajax、
        // 同步 loader 自建的 URLSession、以及重定向的每一跳都走这道闸，
        // 不再只靠下面这层 transport 包装（那层只覆盖从 App 直接发起的请求）。
        PrivateHostGate.configure { host in
            URLHost.isPrivate(host) && !PrivateHostAllowList.shared.contains(host)
        }
        let guarded = HostGuardedTransport(base: URLSessionHTTPTransport())
        transport = guarded
        search = BookSearchService(transport: guarded)
        books = NetworkBookService(transport: guarded)
        debugger = BookSourceDebugger(transport: guarded)
        explorer = BookExploreService(transport: guarded)
        // 换源服务自己会去别的书源搜同名书、拉详情、取目录、验正文，
        // 每一步都必须走同一个带私网拦截的 transport，否则换源能绕开拦截。
        switcher = BookSourceSwitchService(
            searcher: BookSearchService(transport: guarded),
            detailLoader: NetworkBookService(transport: guarded),
            chapterLoader: NetworkBookService(transport: guarded),
            contentLoader: NetworkBookService(transport: guarded)
        )
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
        // 段落 ID 会被写进阅读位置与书签并持久化，所以章节 ID 必须跨启动稳定。
        // 这里用书源地址 + 章节地址的 FNV-1a，而不是每次启动都换种子的 hashValue。
        let chapterID = "net-\(StableID.hash(chapter.bookUrl + "\u{0}" + chapter.url))"
        return (TextSegmenter.paragraphs(from: body, chapterID: chapterID), nil)
    }

    // MARK: - 发现

    /// 书源声明的发现分类。没有 `exploreUrl` 的书源返回空列表 —— 那是书源本身
    /// 不支持发现，不是失败，界面上要区分这两种情况。
    func exploreKinds(source: LegadoCore.BookSource) async -> (kinds: [ExploreKind], error: String?) {
        let report = await explorer.kinds(for: source)
        if report.kinds.isEmpty {
            let message = report.diagnostics.first?.message
            lastError = message
            return ([], message)
        }
        return (report.kinds, nil)
    }

    /// 按分类抓一页发现书目。
    func explore(
        source: LegadoCore.BookSource,
        kind: ExploreKind,
        page: Int = 1
    ) async -> SourceSearchOutcome {
        await explorer.explore(source: source, kind: kind, page: page)
    }

    // MARK: - 段评

    /// 拉本章评论。书源没有评论规则时返回空数组 + 明确原因，
    /// 不抛错也不假装「没有评论」。
    func chapterComments(
        engineBook: LegadoCore.Book,
        chapter: BookChapter,
        source: LegadoCore.BookSource
    ) async -> (comments: [ChapterComment], error: String?) {
        guard let rules = source.ruleReview, rules.supportsChapterComments else {
            return ([], "此书源没有配置段评规则")
        }
        do {
            let comments = try await books.loadChapterComments(
                book: engineBook, chapter: chapter, source: source
            )
            return (comments, nil)
        } catch {
            lastError = error.localizedDescription
            return ([], error.localizedDescription)
        }
    }

    // MARK: - 换源

    /// 在其它已启用书源里找同一本书。只返回书名规范化后一致、
    /// 并且已经过正文验证的候选，而不是「名字有点像」就列出来。
    func switchCandidates(
        book: TitleAuthor,
        sources: [LegadoCore.BookSource],
        onUpdate: @escaping @MainActor ([SwitchCandidate]) -> Void
    ) async -> [SwitchCandidate] {
        let engineBook = book.engineBook()
        // candidateUpdates 是 actor 方法，虽然它同步返回一个 AsyncStream，
        // 取这个流本身仍然要 await。
        let updates = await switcher.candidateUpdates(for: engineBook, sources: sources)
        var result: [SwitchCandidate] = []
        for await update in updates {
            result = update.map { candidate in
                SwitchCandidate(
                    searchBook: candidate.book,
                    score: candidate.score,
                    sourceURL: candidate.book.origin,
                    sourceName: candidate.book.originName
                )
            }
            await onUpdate(result)
        }
        return result
    }

    /// 验证候选源真的能读：拉详情、取目录、按旧位置匹配章节、再读一章正文。
    /// 任何一步失败都返回 nil，界面上就不会出现「切过去打不开」的选项。
    func prepareSwitch(
        book: TitleAuthor,
        candidate: SwitchCandidate,
        source: LegadoCore.BookSource
    ) async -> (report: SwitchReport, error: String?) {
        let engineBook = book.engineBook()

        guard let report = await switcher.prepareSwitch(
            current: engineBook, candidate: candidate.searchBook, source: source
        ) else {
            // 上游只给 nil，不给原因。这里补一句人话，别让界面显示空白。
            return (.empty, "候选书源无法读取：详情、目录或正文任一环节失败")
        }
        return (
            SwitchReport(
                chapters: report.chapters,
                matchedTitle: report.book.durChapterTitle,
                matchedIndex: report.book.durChapterIndex,
                exactChapterMatch: report.exactChapterMatch,
                content: report.verifiedContent?.content
            ),
            nil
        )
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

/// 用户显式放行的私网地址。
///
/// 传输层跑在任意线程上，不能用 `@MainActor` 的状态，所以单独做一个
/// 加锁的小容器；界面改一处，所有在途请求立刻按新值判定。
final class PrivateHostAllowList: @unchecked Sendable {
    static let shared = PrivateHostAllowList()

    private let lock = NSLock()
    private var hosts: Set<String> = []

    func update(_ values: Set<String>) {
        lock.withLock { hosts = values }
    }

    func contains(_ host: String) -> Bool {
        let normalized = URLHost.normalize(host)
        return lock.withLock { hosts.contains(normalized) }
    }
}

/// 把 App 的私网判定加在传输层，任何经过引擎的请求都会被检查一次。
///
/// 放在这里而不是放在书源启用时，是因为书源的规则里可能写着别的域名，
/// 也可能在 JS 里拼出新地址——只看 `bookSourceUrl` 是拦不住的。
private struct HostGuardedTransport: HTTPTransport {
    let base: any HTTPTransport

    func data(for request: URLRequest) async throws -> HTTPResponse {
        if let host = request.url?.host,
           URLHost.isPrivate(host),
           !PrivateHostAllowList.shared.contains(host) {
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

// MARK: - 跨书源识别的入参

/// 换源需要知道「当前这本书是谁、读到哪儿」。
///
/// 为什么不直接用 App 的 `Book`：`BookSourceSwitchService` 只认引擎的
/// `LegadoCore.Book`，而且它的字段名（`durChapterIndex` / `durChapterTitle`）
/// 与 App 的（`progress` / `lastPosition`）对不上。这一层做一次翻译，
/// 让换源逻辑待在引擎里，不把引擎类型泄漏到界面和快照里。
struct TitleAuthor {
    var title: String
    var author: String
    /// 当前书的引擎地址；本地书与演示书为 nil。
    var bookURL: String?
    var tocURL: String?
    var origin: String?
    var chapterIndex: Int = 0
    var chapterTitle: String?
    var offset: Int = 0
    var chapterCount: Int = 0

    /// 翻译成引擎的 `Book`。
    /// `Book` 是 struct，所有字段都得在构造时就给值，
    /// 所以这里用一次性构造而不是逐个赋值。
    func engineBook() -> LegadoCore.Book {
        var book = LegadoCore.Book(
            bookUrl: bookURL ?? "",
            name: title,
            author: author,
            origin: origin ?? ""
        )
        book.tocUrl = tocURL ?? ""
        book.durChapterIndex = chapterIndex
        book.durChapterTitle = chapterTitle
        book.durChapterPos = offset
        book.totalChapterNum = chapterCount
        return book
    }
}

/// 换源候选：一个能读的备选书源。
struct SwitchCandidate: Identifiable, Equatable {
    var searchBook: SearchBook
    var score: Int
    var sourceURL: String
    var sourceName: String

    /// 用书籍地址做身份：同一个源里搜到两次的一定是同一本。
    var id: String { searchBook.bookURL }
}

/// 换源验证结果。
struct SwitchReport {
    var chapters: [BookChapter]
    var matchedTitle: String?
    var matchedIndex: Int
    var exactChapterMatch: Bool
    /// 从候选源实际读到的正文，用来证明「切过去真的能看」。
    var content: String?

    static let empty = SwitchReport(
        chapters: [], matchedTitle: nil, matchedIndex: 0,
        exactChapterMatch: false, content: nil
    )
}
