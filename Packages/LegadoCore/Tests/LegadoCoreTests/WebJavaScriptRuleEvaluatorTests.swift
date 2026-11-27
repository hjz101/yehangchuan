import Foundation
import XCTest
#if os(macOS)
import AppKit
#endif
@testable import LegadoCore

/// `<webjs>` 规则曾经在 `init` 里给 http/https 注册 `WKURLSchemeHandler`，
/// WebKit 直接抛异常，于是任何带 `<webjs>` 的书源一跑就崩。
///
/// 这些测试跑真实的 WKWebView：钉住三件事 —— 脚本能执行、能拿到 `result`、
/// 页面自己的网络出口是关的（唯一通道是桥），而不只是「没崩」。
@MainActor
final class WebJavaScriptRuleEvaluatorTests: XCTestCase {
    /// 记录桥接请求，验证 `window.__legadoFetch` 真的走到 Swift 侧。
    private final class StubTransport: HTTPTransport, @unchecked Sendable {
        private(set) var requests: [URLRequest] = []
        var body = "桥接响应"
        var status = 200

        func data(for request: URLRequest) async throws -> HTTPResponse {
            requests.append(request)
            return HTTPResponse(
                data: Data(body.utf8),
                statusCode: status,
                headers: ["content-type": "text/plain; charset=utf-8"],
                finalURL: request.url ?? URL(string: "https://example.com")!
            )
        }
    }

    private var transport: StubTransport!
    private var evaluator: WebJavaScriptRuleEvaluator!

    override func setUp() async throws {
        try await super.setUp()
        #if os(macOS)
        // WebKit 需要 AppKit 先完成初始化；裸 `swift test` 进程里没有应用对象，
        // 直接建 WKWebView 会在 CoreFoundation 里崩掉（freed pointer）。
        _ = NSApplication.shared
        #endif
        PrivateHostGate.resetForTesting()
        transport = StubTransport()
        evaluator = WebJavaScriptRuleEvaluator(transport: transport)
    }

    override func tearDown() async throws {
        evaluator = nil
        transport = nil
        PrivateHostGate.resetForTesting()
        try await super.tearDown()
    }

    func testEvaluatesSimpleExpression() async throws {
        let output = try await evaluator.evaluate(
            script: "1 + 1", result: .string(""), executionContext: RuleExecutionContext()
        )
        XCTAssertEqual(output.value, .number(2))
    }

    func testExposesInputAsResultAndWindowResult() async throws {
        let output = try await evaluator.evaluate(
            script: "result.toUpperCase()",
            result: .string("hello"),
            executionContext: .init()
        )
        XCTAssertEqual(output.value, .string("HELLO"))
    }

    func testScriptCanReadDOMOfSandboxDocument() async throws {
        // 这条同时验证「空白文档确实加载了」：没加载时下面的用户脚本不会注入，
        // document 也取不到，脚本要么报错要么拿到空串。
        let output = try await evaluator.evaluate(
            script: "String(document.readyState)",
            result: .string(""),
            executionContext: .init()
        )
        XCTAssertEqual(output.value, .string("complete"))
    }

    func testPageOwnNetworkIsBlocked() async throws {
        // 页面自己的 fetch 必须失败。放行就等于 `<webjs>` 可以绕过私网闸门。
        do {
            _ = try await evaluator.evaluate(
                script: "await fetch('https://example.com/ping'); 'reachable'",
                result: .string(""),
                executionContext: .init()
            )
            XCTFail("页面自己的 fetch 应当被沙箱挡掉")
        } catch {
            XCTAssertTrue(transport.requests.isEmpty, "被挡掉的请求不该到达传输层")
        }
    }

    func testBridgeFetchGoesThroughTransport() async throws {
        let output = try await evaluator.evaluate(
            script: "await window.__legadoFetch('https://example.com/api');",
            result: .string(""),
            executionContext: .init()
        )
        XCTAssertEqual(transport.requests.count, 1)
        XCTAssertEqual(transport.requests.first?.url?.absoluteString, "https://example.com/api")
        XCTAssertEqual(output.value, .string(transport.body))
    }

    /// 书源里的 `<webjs>` 常写成带尾分号的表达式，直接塞进 `return await (…)`
    /// 会变成语法错误 —— 实测真实书源踩过这条。
    func testExpressionWithTrailingSemicolon() async throws {
        let output = try await evaluator.evaluate(
            script: "  result.toUpperCase();  ",
            result: .string("abc"),
            executionContext: .init()
        )
        XCTAssertEqual(output.value, .string("ABC"))
    }

    /// 另一种写法是整段函数体自带 `return`。
    func testFunctionBodyWithOwnReturn() async throws {
        let output = try await evaluator.evaluate(
            script: "if (result.length > 2) { return result.slice(0, 2); }\nreturn result;",
            result: .string("abcdef"),
            executionContext: .init()
        )
        XCTAssertEqual(output.value, .string("ab"))
    }

    /// `<webjs>` 必须能拿到形参 `result`（正文 HTML 通常很长）。
    func testLargeInputString() async throws {
        let html = String(repeating: "正文", count: 60_000)
        let output = try await evaluator.evaluate(
            script: "result.length",
            result: .string(html),
            executionContext: .init()
        )
        XCTAssertEqual(output.value, .number(Double(html.count)))
    }

    /// 同一本 WebView 会被多个书源并发使用。曾经用固定键等结果，
    /// 后一次会覆盖前一次，前一次就永远挂在那里。
    func testConcurrentEvaluationsKeepTheirOwnResults() async throws {
        let evaluator = self.evaluator!
        async let first = evaluator.evaluate(
            script: "await new Promise(r => setTimeout(r, 120)); return 'first';",
            result: .string(""),
            executionContext: .init()
        )
        async let second = evaluator.evaluate(
            script: "return 'second';",
            result: .string(""),
            executionContext: .init()
        )
        let (a, b) = try await (first, second)
        XCTAssertEqual(a.value, .string("first"))
        XCTAssertEqual(b.value, .string("second"))
    }
}
