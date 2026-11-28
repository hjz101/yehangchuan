import Foundation
import XCTest
#if os(macOS)
import AppKit
#endif
@testable import LegadoCore

/// 四份真实书源样本的导入、桥接与规则转换回归。
final class BookSourceAdaptationTests: XCTestCase {
    private let names = [
        "起点中文",
        "魔趣小说",
        "书海阁_阅读3.0书源",
        "大灰狼聚合5.11.14(vip完全版)"
    ]

    private func fixture(_ name: String) throws -> Data {
        let url = try XCTUnwrap(
            Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures/BookSources"),
            "缺少书源样本 \(name)"
        )
        return try Data(contentsOf: url)
    }

    func testAllProvidedSourcesImport() throws {
        for name in names {
            let result = try BookSourceImporter().inspect(try fixture(name))
            XCTAssertEqual(result.sources.count, 1, "\(name) 应解析出一条书源")
            XCTAssertTrue(result.rejected.isEmpty, "\(name) 被拒绝：\(result.rejected.flatMap(\.issues).map(\.message))")
            XCTAssertFalse(result.sources[0].bookSourceName.isEmpty)
        }
    }

    func testLegadoSourcesCarryRulesAndLogin() throws {
        let mowan = try BookSourceImporter().inspect(try fixture("魔趣小说")).sources[0]
        XCTAssertNotNil(mowan.searchUrl)
        XCTAssertNotNil(mowan.ruleToc?.chapterList)
        XCTAssertNotNil(mowan.ruleContent?.content)
        XCTAssertEqual(mowan.loginUrl, "https://www.mowan.lol/user/me?app=yuedu&version=26.9.22")

        let wolf = try BookSourceImporter().inspect(try fixture("大灰狼聚合5.11.14(vip完全版)")).sources[0]
        XCTAssertNotNil(wolf.loginUi)
        XCTAssertNotNil(wolf.jsLib)

        let washai = try BookSourceImporter().inspect(try fixture("书海阁_阅读3.0书源")).sources[0]
        XCTAssertTrue((washai.ruleContent?.content ?? "").contains("java.webView"))
    }

    func testHTMLSourceConvertsIntoExecutableRules() throws {
        let data = try fixture("起点中文")
        let source = try XCTUnwrap(HTMLBookSourceConverter.convert(jsonData: data, name: "起点中文"))
        XCTAssertEqual(source.bookSourceUrl, "https://www.qidian.com")
        XCTAssertEqual(source.loginUrl, "html://settings")
        XCTAssertTrue(HTMLSourceRegistry.shared.contains(source.id))
        XCTAssertTrue((source.ruleSearch?.bookList ?? "").hasPrefix("<webjs>"))
        XCTAssertTrue((source.ruleBookInfo?.`init` ?? "").contains("await info(baseUrl)"))
        XCTAssertTrue((source.ruleToc?.chapterUrl ?? "").contains("encodeURIComponent"))
        XCTAssertTrue((source.ruleContent?.content ?? "").contains("await content("))
    }

    func testJavaScriptAliasesDoNotThrow() async throws {
        let source = BookSource(bookSourceUrl: "https://example.com", bookSourceName: "测试")
        let evaluator = JavaScriptRuleEvaluator()
        let output = try await evaluator.evaluateAsync(
            script: """
            java.longToast('hi');
            source.setVariable(JSON.stringify({ x: 'y' }));
            JSON.stringify({ id: java.deviceID(), variable: source.getVariable('x'), login: source.getLoginInfo() });
            """,
            result: .null,
            executionContext: .init(source: source)
        )
        let text = output.value.stringValue
        XCTAssertFalse(text.isEmpty)
        let object = try XCTUnwrap(try JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any])
        XCTAssertEqual(object["variable"] as? String, "y")
        XCTAssertNotNil(object["id"] as? String)
        XCTAssertNotNil(object["login"] as? String)
    }
}

@MainActor
final class HTMLSourceBridgeTests: XCTestCase {
    private final class StubTransport: HTTPTransport, @unchecked Sendable {
        func data(for request: URLRequest) async throws -> HTTPResponse {
            HTTPResponse(data: Data("ok".utf8), statusCode: 200, headers: [:], finalURL: request.url!)
        }
    }

    override func setUp() async throws {
        try await super.setUp()
        #if os(macOS)
        _ = NSApplication.shared
        #endif
    }

    func testEvaluatorSmoke() async throws {
        let evaluator = WebJavaScriptRuleEvaluator(transport: StubTransport())
        let output = try await evaluator.evaluate(script: "1 + 1", result: .null, executionContext: .init())
        XCTAssertEqual(output.value, .number(2))
    }

    func testHTMLSourceSettingsBridgeRoundTrip() async throws {
        let html = """
        <!doctype html><html><body><script>
        async function getloginurl() {
          await window.flutter_inappwebview.callHandler('cache.set', 'token', 'abc');
          return await window.flutter_inappwebview.callHandler('cache.get', 'token');
        }
        async function login(info) { window.__saved = info; }
        </script></body></html>
        """
        let source = BookSource(bookSourceUrl: "https://html.test", bookSourceName: "HTML")
        HTMLSourceRegistry.shared.register(html: html, for: source.id)
        let evaluator = WebJavaScriptRuleEvaluator(transport: StubTransport())
        let url = try await evaluator.prepareHTMLSource(source)
        XCTAssertEqual(url, "abc")
        try await evaluator.commitHTMLSourceLogin(source)
    }
}
