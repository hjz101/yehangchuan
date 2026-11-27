import Foundation
import XCTest
#if os(macOS)
import AppKit
#endif
@testable import LegadoCore

/// 阅读 3.0 书源里 `webView:true` 的请求走 `WebViewSourcePageExecutor`。
/// 这条链路此前没有任何测试，于是「书源要求 WebView」到底能不能读，
/// 只能靠人去界面上手点，点不到就等于没人知道。
///
/// 这里用 `webViewHTML` 分支（原生预取好的 HTML 交给 `loadHTMLString`）
/// 驱动真实的 WKWebView：不发网络请求，但页面、注入脚本、`webJs`
/// 与资源正则都按阅读时同一套逻辑跑。
@MainActor
final class WebViewSourcePageExecutorTests: XCTestCase {
    private var executor: WebViewSourcePageExecutor!
    private var source: BookSource!

    override func setUp() async throws {
        try await super.setUp()
        #if os(macOS)
        _ = NSApplication.shared
        #endif
        PrivateHostGate.resetForTesting()
        executor = WebViewSourcePageExecutor.shared
        source = BookSource(
            bookSourceUrl: "https://webview-test.example.com",
            bookSourceName: "WebView 测试源"
        )
    }

    override func tearDown() async throws {
        PrivateHostGate.resetForTesting()
        executor = nil
        source = nil
        try await super.tearDown()
    }

    private func prepared(
        html: String,
        script: String? = nil,
        sourceRegex: String? = nil,
        delay: Int = 0
    ) -> PreparedRequest {
        PreparedRequest(
            ruleURL: "https://webview-test.example.com/chapter",
            url: URL(string: "https://webview-test.example.com/chapter")!,
            method: .get,
            headers: [:],
            body: nil,
            charset: nil,
            retry: 0,
            useWebView: true,
            webJavaScript: script,
            bodyJavaScript: nil,
            webViewDelayMilliseconds: delay,
            sourceRegex: sourceRegex,
            webViewHTML: html
        )
    }

    private func text(_ response: HTTPResponse) -> String {
        response.decodedText
    }

    /// 没有 `webJs` 时，响应体就是页面 DOM。这条是「WebView 真的把这个
    /// 页面渲染出来了吗」的底线：拿不到 DOM 说明页面根本没加载。
    func testReturnsRenderedDOMWhenSourceHasNoScript() async throws {
        let html = "<!doctype html><html><body><div id=\"c\">正文内容 ABC</div></body></html>"
        let response = try await executor.execute(
            prepared(html: html), source: source, timeout: 10
        )
        XCTAssertEqual(response.statusCode, 200)
        XCTAssertTrue(text(response).contains("正文内容 ABC"), "响应体应当是渲染后的 DOM")
        XCTAssertEqual(response.requestedCharset, "utf-8")
    }

    /// `webJs` 在真实页面里执行，返回值就是正文 —— 这是阅读 3.0 里
    /// 「靠页面脚本渲染出内容的站点」唯一的读法。
    func testWebJsRunsInsideTheLoadedPage() async throws {
        let html = """
        <!doctype html><html><body>
          <div id="c">第一段</div><div id="d">第二段</div>
        </body></html>
        """
        let response = try await executor.execute(
            prepared(html: html, script: "document.getElementById('c').textContent"),
            source: source,
            timeout: 10
        )
        XCTAssertEqual(text(response), "第一段")
    }

    /// 书源把 `webJs` 写成带尾分号的表达式，或写成自带 `return` 的整段函数体，
    /// 两种写法都常见。包进 `return await (…)` 前不摘分号就是语法错误。
    func testWebJsAcceptsTrailingSemicolonAndFunctionBody() async throws {
        let html = "<!doctype html><html><body><p>abcdef</p></body></html>"
        let withSemicolon = try await executor.execute(
            prepared(html: html, script: "  document.querySelector('p').textContent;  "),
            source: source,
            timeout: 10
        )
        XCTAssertEqual(text(withSemicolon), "abcdef")

        let asFunctionBody = try await executor.execute(
            prepared(
                html: html,
                script: "const t = document.querySelector('p').textContent;\nreturn t.toUpperCase();"
            ),
            source: source,
            timeout: 10
        )
        XCTAssertEqual(text(asFunctionBody), "ABCDEF")
    }

    /// `await` 在 `webJs` 里必须能用：真实书源常用「等页面脚本把内容塞进 DOM」
    /// 的写法。`evaluateJavaScript` 收不了 Promise，这条能钉住用的是
    /// `callAsyncJavaScript`。
    func testWebJsCanAwaitInsideThePage() async throws {
        let html = """
        <!doctype html><html><body><div id="c"></div>
        <script>
          setTimeout(function () { document.getElementById('c').textContent = '延迟渲染'; }, 60);
        </script></body></html>
        """
        let script = """
        (async () => {
          await new Promise(r => setTimeout(r, 200));
          return document.getElementById('c').textContent;
        })()
        """
        let response = try await executor.execute(
            prepared(html: html, script: script), source: source, timeout: 10
        )
        XCTAssertEqual(text(response), "延迟渲染")
    }

    /// `sourceRegex`（资源正则）的阅读 3.0 语义：页面加载中某个子资源地址
    /// 命中正则，就把**那个地址**当作响应体交给后续正文规则。
    /// 页面在这里只是套壳，真正的数据在接口里。
    func testSourceRegexReturnsMatchedResourceURL() async throws {
        let html = """
        <!doctype html><html><head><script>
          window.__legadoResourceURLs.push('https://cdn.example.com/api/chapter/42.json');
        </script></head><body>壳页面</body></html>
        """
        let response = try await executor.execute(
            prepared(
                html: html,
                sourceRegex: "^https://cdn\\.example\\.com/api/.*\\.json$"
            ),
            source: source,
            timeout: 10
        )
        XCTAssertEqual(text(response), "https://cdn.example.com/api/chapter/42.json")
        XCTAssertEqual(response.requestedCharset, "utf-8")
        // 命中资源正则时并没有执行任何脚本，调试界面不能说「执行了 webJs」。
        XCTAssertEqual(executor.recentTraces.first?.matchedSourceRegex,
                       "https://cdn.example.com/api/chapter/42.json")
        XCTAssertEqual(executor.recentTraces.first?.usedWebJs, false)
    }

    /// 正则不命中时应当退回 DOM，而不是把「没命中」当失败。
    func testSourceRegexMissFallsBackToDOM() async throws {
        let html = """
        <!doctype html><html><head><script>
          window.__legadoResourceURLs.push('https://cdn.example.com/style.css');
        </script></head><body>正文在 DOM 里</body></html>
        """
        let response = try await executor.execute(
            prepared(html: html, sourceRegex: "^https://cdn\\.example\\.com/api/.*\\.json$"),
            source: source,
            timeout: 10
        )
        XCTAssertTrue(text(response).contains("正文在 DOM 里"))
    }

    /// 页面脚本自己往私网发请求必须失败。放行就等于书源可以借 WebView
    /// 绕过私网闸门 —— 主框架有闸门，子资源只能靠注入的看守脚本。
    func testPageScriptCannotReachPrivateHosts() async throws {
        let html = "<!doctype html><html><body>正文</body></html>"
        let script = """
        (async () => {
          try {
            await fetch('http://192.168.1.1/metadata');
            return 'reachable';
          } catch (e) {
            return 'blocked: ' + e.message;
          }
        })()
        """
        let response = try await executor.execute(
            prepared(html: html, script: script), source: source, timeout: 10
        )
        XCTAssertEqual(text(response), "blocked: blocked private host: http://192.168.1.1/metadata")
    }

    /// 主框架落到私网地址时要在打开页面之前就拒绝，并说清是哪个主机。
    func testPrivateMainFrameIsBlockedBeforeLoading() async throws {
        var request = prepared(html: "<html><body>不该被打开</body></html>")
        request.url = URL(string: "http://127.0.0.1:8080/admin")!
        do {
            _ = try await executor.execute(request, source: source, timeout: 10)
            XCTFail("私网主框架应当被拦截")
        } catch let error as WebViewPageError {
            guard case .blocked(let host) = error else {
                return XCTFail("期望 blocked，实际是 \(error)")
            }
            XCTAssertEqual(host, "127.0.0.1")
        }
    }

    /// 不支持的分支要明说，而不是静默走成普通请求：`webView:true` 却打不开时，
    /// 用户看到的原因必须是「为什么打不开」。
    func testProxyIsReportedAsUnsupported() async throws {
        var request = prepared(html: "<html><body>x</body></html>")
        request.proxy = "http://proxy.local:8080"
        do {
            _ = try await executor.execute(request, source: source, timeout: 10)
            XCTFail("WebView 不支持代理，应当报错")
        } catch let error as WebViewPageError {
            guard case .unsupported = error else {
                return XCTFail("期望 unsupported，实际是 \(error)")
            }
        }
    }

    /// 调试界面只显示「这一次执行」留下的轨迹。作用域用 TaskLocal 传递：
    /// 环形缓存存满后 `count` 不再变化（数个数会算成 0），且阅读时别的
    /// 书源并发产生的请求不能串进来。跑满 20 条也自然冲掉别处留下的数据，
    /// 所以本用例不依赖单例的初始状态。
    func testTraceScopeOnlyReturnsThisExecution() async throws {
        let html = "<!doctype html><html><body><p>轨迹</p></body></html>"
        let scopeA = UUID()
        let scopeB = UUID()

        // 用 A 把环形缓存填满（20 条），同时冲掉别处留下的旧轨迹。
        for _ in 0..<20 {
            _ = try await WebViewTraceScope.$current.withValue(scopeA) {
                try await executor.execute(prepared(html: html), source: source, timeout: 10)
            }
        }
        XCTAssertEqual(executor.recentTraces.count, 20)
        XCTAssertEqual(executor.traces(in: scopeA).count, 20)

        // 无作用域的请求（模拟阅读时别的书源）用独立地址，便于确认它不会串进来。
        var unscoped = prepared(html: html)
        unscoped.url = URL(string: "https://unscoped.example.com/chapter")!
        _ = try await executor.execute(unscoped, source: source, timeout: 10)

        // 缓存已满时，B 仍能精确取到本次这一条。
        _ = try await WebViewTraceScope.$current.withValue(scopeB) {
            try await executor.execute(prepared(html: html), source: source, timeout: 10)
        }
        let bTraces = executor.traces(in: scopeB)
        XCTAssertEqual(bTraces.count, 1, "缓存已满时仍应识别出本次作用域的轨迹")
        XCTAssertEqual(bTraces.first?.sourceName, source.bookSourceName)
        XCTAssertEqual(bTraces.first?.scopeID, scopeB)
        XCTAssertFalse(bTraces.contains { $0.url == unscoped.url.absoluteString },
                       "别的书源的并发请求不该串进本次作用域")
    }
}
