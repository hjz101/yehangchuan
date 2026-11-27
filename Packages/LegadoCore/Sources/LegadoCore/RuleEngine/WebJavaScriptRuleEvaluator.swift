import Foundation
import WebKit

public enum WebJavaScriptError: Error, LocalizedError, Sendable {
    case timeout
    case invalidMessage

    public var errorDescription: String? {
        switch self {
        case .timeout: "WKWebView 脚本执行超时"
        case .invalidMessage: "WKWebView 桥接消息格式无效"
        }
    }
}

/// `<webjs>` 规则用的真实 WKWebView 执行器。
///
/// 页面里的 fetch/XHR 被 WKURLSchemeHandler 一律挡掉，唯一的网络出口是
/// `window.__legadoFetch`，它由 Swift 代发并复用 PrivateHostGate 闸门。
/// 这样 WebView 的进程隔离是真的，私网策略也没有被绕过。
@MainActor
public final class WebJavaScriptRuleEvaluator: NSObject, WKScriptMessageHandler {
    public static let shared = WebJavaScriptRuleEvaluator()

    private var webView: WKWebView!
    private let transport: any HTTPTransport
    private let blockedScheme = BlockedSchemeHandler()
    private var pending: [String: CheckedContinuation<JSONValue, Error>] = [:]
    private var timeoutTask: Task<Void, Never>?

    private static let timeoutSeconds: Double = 10

    public init(transport: any HTTPTransport = URLSessionHTTPTransport()) {
        self.transport = transport
        let configuration = WKWebViewConfiguration()
        configuration.userContentController.addUserScript(Self.bridgeScript)
        configuration.setURLSchemeHandler(blockedScheme, forURLScheme: "http")
        configuration.setURLSchemeHandler(blockedScheme, forURLScheme: "https")
        super.init()
        // WKWebView 会拷贝 configuration，所以 message handler 必须在创建前挂上。
        configuration.userContentController.add(self, name: "legadoBridge")
        webView = WKWebView(frame: .zero, configuration: configuration)
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
        """
        return WKUserScript(source: source, injectionTime: .atDocumentStart, forMainFrameOnly: true)
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
            callback(id, ok: false, value: WebJavaScriptError.invalidMessage.localizedDescription ?? "invalid message")
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

/// WKWebView 自己发起的 http/https 请求一律拒绝；只有原生桥能代发。
private final class BlockedSchemeHandler: NSObject, WKURLSchemeHandler {
    func webView(_ webView: WKWebView, start urlSchemeTask: WKURLSchemeTask) {
        guard let url = urlSchemeTask.request.url else { return }
        let response = HTTPURLResponse(
            url: url, statusCode: 403, httpVersion: nil,
            headerFields: ["Content-Type": "text/plain"]
        ) ?? URLResponse(url: url, mimeType: "text/plain", expectedContentLength: 0, textEncodingName: nil)
        urlSchemeTask.didReceive(response)
        urlSchemeTask.didReceive(Data("blocked by private host gate".utf8))
        urlSchemeTask.didFinish()
    }

    func webView(_ webView: WKWebView, stop urlSchemeTask: WKURLSchemeTask) {}
}
