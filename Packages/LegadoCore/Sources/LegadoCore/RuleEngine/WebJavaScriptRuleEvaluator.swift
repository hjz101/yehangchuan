import Foundation
import WebKit

public enum WebJavaScriptError: Error, LocalizedError, Sendable {
    case timeout
    case invalidMessage
    case documentFailed(String)

    public var errorDescription: String? {
        switch self {
        case .timeout: "WKWebView 脚本执行超时"
        case .invalidMessage: "WKWebView 桥接消息格式无效"
        case .documentFailed(let detail): "WKWebView 沙箱页面准备失败：\(detail)"
        }
    }
}

/// `<webjs>` 规则用的真实 WKWebView 执行器。
///
/// 页面自己发起的 http/https 请求一律挡掉，唯一的网络出口是
/// `window.__legadoFetch`，它由 Swift 代发并复用 PrivateHostGate 闸门。
/// 这样 WebView 的进程隔离是真的，私网策略也没有被绕过。
///
/// 拦截手段不能用 `WKURLSchemeHandler` 注册 http/https —— WebKit 对这两个
/// scheme 会直接抛 `'http' is a URL scheme that WKWebView handles natively`，
/// 而且抛在 `init` 里，等于任何 `<webjs>` 规则一碰就崩。现在换成两层都在
/// 进程内、加载前生效的手段：
/// - `WKContentRuleList` 拦掉所有 http/https 子资源；
/// - 文档开头注入的看守脚本把 `fetch` / `XHR` 改成失败，
///   让脚本只能走桥。
@MainActor
public final class WebJavaScriptRuleEvaluator: NSObject, WKScriptMessageHandler {
    public static let shared = WebJavaScriptRuleEvaluator()

    private var webView: WKWebView!
    private let transport: any HTTPTransport
    private var pending: [String: CheckedContinuation<JSONValue, Error>] = [:]
    private var timeoutTask: Task<Void, Never>?
    /// 空白文档是否已经就绪。`evaluate` 在第一次执行前等它。
    private var documentReady: Task<Void, Error>?
    /// 导航代理必须被强引用，否则回调可能落在已经释放的对象上。
    private var documentSession: BlankDocumentLoader?

    private static let timeoutSeconds: Double = 10

    public init(transport: any HTTPTransport = URLSessionHTTPTransport()) {
        self.transport = transport
        let configuration = WKWebViewConfiguration()
        // 沙箱不该在设备上留下任何痕迹。
        configuration.websiteDataStore = .nonPersistent()
        configuration.userContentController.addUserScript(Self.bridgeScript)
        super.init()
        // WKWebView 会拷贝 configuration，所以 message handler 必须在创建前挂上。
        configuration.userContentController.add(self, name: "legadoBridge")
        webView = WKWebView(
            frame: CGRect(x: 0, y: 0, width: 390, height: 844),
            configuration: configuration
        )
        Self.installBlockingRules(into: webView)
        startBlankDocument()
    }

    public func evaluate(
        script: String,
        result: JSONValue,
        executionContext: RuleExecutionContext
    ) async throws -> JavaScriptRuleResult {
        try executionContext.checkCancellation()
        guard script.utf8.count <= 64 * 1_024 else {
            throw RuleEngineError.resourceLimit(rule: "webjs", detail: "WKWebView 脚本超过 64 KB")
        }
        try await documentReady?.value
        let inputJSON = Self.jsonLiteral(result.foundationObject)
        try await webView.evaluateJavaScript("window.__legadoInput = \(inputJSON); window.result = window.__legadoInput;")
        let program = "(async function(){ const result = window.__legadoInput; return await (\(script)); })()"
        let value = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<JSONValue, Error>) in
            pending["main"] = continuation
            webView.evaluateJavaScript(program) { [weak self] value, error in
                guard let self else { return }
                self.resolve("main", value: value, error: error)
            }
            timeoutTask = Task { [weak self] in
                try? await Task.sleep(nanoseconds: UInt64(Self.timeoutSeconds * 1_000_000_000))
                self?.resolve("main", value: nil, error: WebJavaScriptError.timeout)
            }
        }
        let bridged = value
        let text = bridged.stringValue
        guard text.utf8.count <= 2 * 1_024 * 1_024 else {
            throw RuleEngineError.resourceLimit(rule: "webjs", detail: "WKWebView 脚本结果超过 2 MB")
        }
        return JavaScriptRuleResult(value: bridged, variables: executionContext.variables, rssArticle: executionContext.rssArticle)
    }

    // MARK: - 沙箱页面

    /// 显式载入一张空白页。
    ///
    /// 不载入任何文档时，WebView 里的初始空文档**不保证**会执行
    /// `atDocumentStart` 的注入脚本；脚本里的 `window.__legadoFetch` 就可能
    /// 根本不存在，规则执行时报的是「不是函数」这种莫名其妙的话。
    private func startBlankDocument() {
        documentReady = Task { [weak self] in
            guard let self else { return }
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                let loader = BlankDocumentLoader(continuation: continuation)
                self.documentSession = loader
                self.webView.navigationDelegate = loader
                self.webView.loadHTMLString(
                    "<!doctype html><html><head><meta charset=\"utf-8\"></head><body></body></html>",
                    baseURL: nil
                )
            }
        }
    }

    /// 把 http/https 子资源全部拦掉。规则编译失败时如实记一条日志，
    /// 不静默降级 —— 没有这一层，页面脚本就能直接用 `fetch` 出去。
    private static func installBlockingRules(into webView: WKWebView) {
        let encoded = """
        [{"trigger":{"url-filter":"^https?://"},"action":{"type":"block"}}]
        """
        WKContentRuleListStore.default().compileContentRuleList(
            forIdentifier: "yhc-webjs-block-network-v1",
            encodedContentRuleList: encoded
        ) { list, error in
            Task { @MainActor in
                if let list {
                    webView.configuration.userContentController.add(list)
                } else {
                    DiagnosticLog.shared.record(
                        .warning, category: "webjs",
                        message: "子资源封锁规则编译失败：\(error?.localizedDescription ?? "未知原因")"
                    )
                }
            }
        }
    }

    // MARK: - Bridge

    private static var bridgeScript: WKUserScript {
        let source = """
        window.__legadoPending = {};
        window.__legadoFetch = function(url, options) {
          return new Promise(function(resolve, reject) {
            var id = String(Date.now()) + '-' + Math.random();
            window.__legadoPending[id] = { resolve: resolve, reject: reject };
            window.webkit.messageHandlers.legadoBridge.postMessage(
              { id: id, op: 'fetch', url: url, options: options || {} });
          });
        };
        window.__legadoResolve = function(id, ok, value) {
          var entry = window.__legadoPending[id];
          if (!entry) return;
          delete window.__legadoPending[id];
          ok ? entry.resolve(value) : entry.reject(new Error(value));
        };
        // 先把页面自己的网络出口换掉，`WKContentRuleList` 只是兜底：
        // 前者让失败立刻可见，后者连请求都发不出去。
        (function () {
          window.fetch = function (input) {
            var url = typeof input === 'string' ? input : (input && input.url) || '';
            return Promise.reject(new Error('network disabled in webjs sandbox: ' + url));
          };
          var nativeOpen = XMLHttpRequest.prototype.open;
          XMLHttpRequest.prototype.open = function (method, url) {
            var self = this;
            var address = String(url);
            var loaded = function () {
              Object.defineProperty(self, 'status', { get: function () { return 0; }, configurable: true });
              Object.defineProperty(self, 'responseText', { get: function () { return ''; }, configurable: true });
              Object.defineProperty(self, 'response', { get: function () { return ''; }, configurable: true });
            };
            loaded();
            self.addEventListener('error', loaded);
            self.addEventListener('load', loaded);
            return nativeOpen.apply(this, [method, 'about:blank']);
          };
          var nativeSend = XMLHttpRequest.prototype.send;
          XMLHttpRequest.prototype.send = function () {
            var xhr = this;
            setTimeout(function () {
              try { xhr.dispatchEvent(new Event('error')); } catch (e) {}
            }, 0);
          };
          window.WebSocket = function (url) {
            throw new Error('network disabled in webjs sandbox: ' + url);
          };
          window.EventSource = function (url) {
            throw new Error('network disabled in webjs sandbox: ' + url);
          };
        })();
        """
        return WKUserScript(source: source, injectionTime: .atDocumentStart, forMainFrameOnly: false)
    }

    nonisolated public func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        Task { @MainActor [weak self] in
            await self?.handle(message)
        }
    }

    private func handle(_ message: WKScriptMessage) async {
        guard let body = message.body as? [String: Any],
              let id = body["id"] as? String,
              let op = body["op"] as? String else { return }
        guard op == "fetch", let urlString = body["url"] as? String, let url = URL(string: urlString) else {
            callback(id, ok: false, value: WebJavaScriptError.invalidMessage.errorDescription ?? "无效消息")
            return
        }
        do {
            var request = URLRequest(url: url)
            if let options = body["options"] as? [String: Any], let method = options["method"] as? String {
                request.httpMethod = method
            }
            // URLSessionHTTPTransport 内部逐跳调用 PrivateHostGate.check。
            let response = try await transport.data(for: request)
            callback(id, ok: true, value: response.decodedText)
        } catch {
            callback(id, ok: false, value: error.localizedDescription)
        }
    }

    private func callback(_ id: String, ok: Bool, value: String) {
        let literal = Self.jsonLiteral(value)
        webView.evaluateJavaScript("window.__legadoResolve(\(Self.jsonLiteral(id)), \(ok), \(literal));")
    }

    private func resolve(_ id: String, value: Any?, error: Error?) {
        guard let continuation = pending.removeValue(forKey: id) else { return }
        timeoutTask?.cancel()
        timeoutTask = nil
        if let error { continuation.resume(throwing: error) }
        else { continuation.resume(returning: JSONValue.bridge(value)) }
    }

    private static func jsonLiteral(_ value: Any) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: value),
              let text = String(data: data, encoding: .utf8) else { return "null" }
        return text
    }
}

/// 只等待那一次空白文档加载，完成即失效。
@MainActor
private final class BlankDocumentLoader: NSObject, WKNavigationDelegate {
    private var continuation: CheckedContinuation<Void, Error>?
    private var settled = false

    init(continuation: CheckedContinuation<Void, Error>) {
        self.continuation = continuation
    }

    private func settle(_ result: Result<Void, Error>) {
        guard !settled, let continuation else { return }
        settled = true
        self.continuation = nil
        continuation.resume(with: result)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        settle(.success(()))
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        settle(.failure(WebJavaScriptError.documentFailed(error.localizedDescription)))
    }

    func webView(
        _ webView: WKWebView,
        didFailProvisionalNavigation navigation: WKNavigation!,
        withError error: Error
    ) {
        settle(.failure(WebJavaScriptError.documentFailed(error.localizedDescription)))
    }
}
