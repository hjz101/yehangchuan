import Foundation
import XCTest
@testable import LegadoCore

final class NetworkBookServiceVolumeTests: XCTestCase {
    private final class CountingTransport: HTTPTransport, @unchecked Sendable {
        private let lock = NSLock()
        private var stored: [URL] = []

        var requestURLs: [URL] { lock.withLock { stored } }

        func data(for request: URLRequest) async throws -> HTTPResponse {
            lock.withLock { stored.append(request.url!) }
            return HTTPResponse(
                data: Data("<html><body><p>目录页</p></body></html>".utf8),
                statusCode: 200,
                headers: ["Content-Type": "text/html; charset=utf-8"],
                finalURL: request.url!
            )
        }
    }

    func testVolumeChapterReturnsEmptyWithoutNetworkRequest() async {
        let transport = CountingTransport()
        let service = NetworkBookService(transport: transport)
        var source = BookSource(bookSourceUrl: "https://example.com", bookSourceName: "测试")
        var rules = ContentRule()
        rules.content = "body@text"
        source.ruleContent = rules
        let book = Book(bookUrl: "https://example.com/book/1", name: "书")
        var chapter = BookChapter(url: "#volume-0", title: "第一卷", bookUrl: book.bookUrl, index: 0)
        chapter.isVolume = true
        chapter.tag = "2024-01-01"
        chapter.baseUrl = book.bookUrl

        let report = await service.loadContent(book: book, chapter: chapter, source: source)

        XCTAssertEqual(report.content, "")
        XCTAssertTrue(transport.requestURLs.isEmpty)
    }
}
