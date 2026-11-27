import XCTest
@testable import LegadoCore

final class BuiltinDemoSourceTests: XCTestCase {
    override func setUp() {
        super.setUp()
        BuiltinDemoSource.setResponder { request in
            let path = request.url?.path ?? ""
            let object: [String: Any]
            if path == "/search" {
                object = ["books": [["title": "灯下草", "author": "顾青",
                                     "url": "\(BuiltinDemoSource.baseURL)/book/dengxiacao",
                                     "intro": "示例"]]]
            } else if path == "/book/dengxiacao" {
                object = ["title": "灯下草", "author": "顾青", "intro": "示例",
                          "tocUrl": "\(BuiltinDemoSource.baseURL)/toc/dengxiacao"]
            } else if path == "/toc/dengxiacao" {
                object = ["chapters": [["name": "第一章",
                                        "url": "\(BuiltinDemoSource.baseURL)/chapter/dengxiacao/0"]]]
            } else if path == "/chapter/dengxiacao/0" {
                object = ["content": "船是傍晚开的。"]
            } else {
                return nil
            }
            return try? JSONSerialization.data(withJSONObject: object)
        }
        BuiltinDemoSource.register()
    }

    override func tearDown() {
        BuiltinDemoSource.setResponder(nil)
        super.tearDown()
    }

    func testRuleIsCompleteAndPassesImport() throws {
        let sources = try BookSourceImporter().decode(BuiltinDemoSource.ruleJSON.data(using: .utf8)!)
        XCTAssertEqual(sources.count, 1)
        let source = sources[0]
        XCTAssertEqual(source.searchUrl?.isEmpty, false)
        XCTAssertNotNil(source.ruleSearch?.bookList)
        XCTAssertNotNil(source.ruleBookInfo?.tocUrl)
        XCTAssertEqual(source.ruleToc?.chapterList?.isEmpty, false)
        XCTAssertEqual(source.ruleContent?.content?.isEmpty, false)
    }

    func testCustomSchemeIsIntercepted() async throws {
        let url = URL(string: "\(BuiltinDemoSource.baseURL)/chapter/dengxiacao/0")!
        let (data, response) = try await URLSession.shared.data(from: url)
        XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200)
        let object = try JSONDecoder().decode([String: String].self, from: data)
        XCTAssertEqual(object["content"], "船是傍晚开的。")
    }

    func testSearchChainParsesRealBooks() async throws {
        let sources = try BookSourceImporter().decode(BuiltinDemoSource.ruleJSON.data(using: .utf8)!)
        var source = sources[0]
        source.enabled = true
        let report = await BookSearchService().search(keyword: "灯", page: 1, sources: [source])
        XCTAssertEqual(report.books.count, 1)
        XCTAssertEqual(report.books.first?.name, "灯下草")
        XCTAssertEqual(report.books.first?.author, "顾青")
    }

    func testTocAndContentChain() async throws {
        let sources = try BookSourceImporter().decode(BuiltinDemoSource.ruleJSON.data(using: .utf8)!)
        let source = sources[0]
        var book = Book(bookUrl: "\(BuiltinDemoSource.baseURL)/book/dengxiacao", name: "灯下草", author: "顾青")
        book.tocUrl = "\(BuiltinDemoSource.baseURL)/toc/dengxiacao"

        let service = NetworkBookService()
        let toc = await service.loadChapters(book: book, source: source)
        XCTAssertEqual(toc.chapters.count, 1)
        XCTAssertEqual(toc.chapters.first?.title, "第一章")
        let content = await service.loadContent(book: book, chapter: toc.chapters[0], source: source)
        XCTAssertEqual(content.content, "船是傍晚开的。")
    }
}
