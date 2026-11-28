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
    /// 空白文档是否已经就绪。`evaluate` 在第一次执行前等它。
    private var documentReady: Task<Void, Error>?
    /// 导航代理必须被强引用，否则回调可能落在已经释放的对象上。
    private var documentSession: BlankDocumentLoader?
    /// 当前页面装的是哪一份 HTML 书源（"" 表示空白沙箱页）。
    private var loadedSourceID = ""
    /// `flutter_inappwebview.callHandler` 需要知道缓存/Cookie 属于哪条书源。
    private var currentSourceID = ""

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
        try await ensureDocument(for: executionContext.source?.bookSourceUrl ?? "")
        let value = try await run(script: script, result: result.foundationObject)
        let text = value.stringValue
        guard text.utf8.count <= 2 * 1_024 * 1_024 else {
            throw RuleEngineError.resourceLimit(rule: "webjs", detail: "WKWebView 脚本结果超过 2 MB")
        }
        return JavaScriptRuleResult(value: value, variables: executionContext.variables, rssArticle: executionContext.rssArticle)
    }

    /// 在页面里执行一段 `<webjs>`，返回它 `return` 出来的值。
    ///
    /// 必须用 `callAsyncJavaScript`，不能用 `evaluateJavaScript`：
    /// - `evaluateJavaScript` 只认同步结果。脚本返回 Promise（任何 `await`
    ///   都会变成 Promise）时，WebKit 报的是「返回结果的类型不受支持」，
    ///   等于每个真正的 webjs 规则都失败；
    /// - `callAsyncJavaScript` 会支持 `await`、能直接接收参数、也能拿到
    ///   `document`/`window`，正好对上 `<webjs>` 的语义。
    ///
    /// `result` 以参数形式传入，不再拼进脚本文本，省掉一整轮转义。
    /// 把 HTML 书源装进沙箱页，并返回它自己的设置 / 登录页地址。
    public func prepareHTMLSource(_ source: BookSource) async throws -> String {
        try await ensureDocument(for: source.bookSourceUrl)
        let value = try await run(script: "return await getloginurl();", result: JSONValue.null.foundationObject)
        return value.stringValue
    }

    /// 供 App 的登录页直接展示同一只 WebView；页面里的桥接与规则执行共用一份。
    public func hostedView() -> WKWebView {
        webView
    }

    /// 设置页把当前配置写进 `#payloadStore`，这里按书源自己的 `login()` 语义提交。
    public func commitHTMLSourceLogin(_ source: BookSource) async throws {
        try await ensureDocument(for: source.bookSourceUrl)
        _ = try await run(
            script: "return await login(document.getElementById('payloadStore') ? document.getElementById('payloadStore').textContent : '');",
            result: JSONValue.null.foundationObject
        )
    }

    private func run(script: String, result: Any) async throws -> JSONValue {
        // 尾部分号在书源里很常见（`<webjs>document.body.innerText;</webjs>`），
        // 直接塞进 `return await (…)` 会变成语法错误，先摘掉。
        var expression = script.trimmingCharacters(in: .whitespacesAndNewlines)
        while expression.hasSuffix(";") {
            expression.removeLast()
            expression = expression.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if !expression.isEmpty {
            let wrapped = "window.result = result; return await (\(expression));"
            do {
                return try await call(body: wrapped, arguments: ["result": result])
            } catch let error as WebJavaScriptError {
                throw error
            } catch {
                // 只有「自带顶层 return 的整段函数体」才值得再试一次；
                // 其它语法错误原样抛出，别把真正的原因盖掉。
                guard expression.range(of: #"\breturn\b"#, options: .regularExpression) != nil else { throw error }
            }
        }
        return try await call(body: "window.result = result; \(script)", arguments: ["result": result])
    }

    private func call(body: String, arguments: [String: Any]) async throws -> JSONValue {
        // 桥接的 Promise 可能永远不落地（远端不响应），所以这里必须有自己的
        // 上限，不能无限等 `callAsyncJavaScript`。两类结果都交给 `resolve`，
        // 由它对 `pending` 做一次性的取走，先到的那个说了算。
        //
        // 键与计时器都按这次调用单独持有：多个书源会并发跑 `<webjs>`，
        // 共用一个固定键 / 一个计时器会让后一次覆盖前一次，
        // 前一次就永远等不到结果，或者被别人的超时打断。
        let token = UUID().uuidString
        var timer: Task<Void, Never>?
        defer {
            pending.removeValue(forKey: token)
            timer?.cancel()
        }
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<JSONValue, Error>) in
            pending[token] = continuation
            Task { @MainActor [weak self] in
                guard let self else { return }
                do {
                    let value = try await self.webView.callAsyncJavaScript(
                        body, arguments: arguments, in: nil, contentWorld: .page
                    )
                    self.resolve(token, value: value, error: nil)
                } catch {
                    self.resolve(token, value: nil, error: error)
                }
            }
            timer = Task { [weak self] in
                // 被取消时 `Task.sleep` 会立刻抛错。必须在这里退出，
                // 否则会顺着往下走，把「上一次尝试」的超时记到下一次的头上。
                do {
                    try await Task.sleep(nanoseconds: UInt64(Self.timeoutSeconds * 1_000_000_000))
                } catch {
                    return
                }
                self?.resolve(token, value: nil, error: WebJavaScriptError.timeout)
            }
        }
    }

    private func resolve(_ id: String, value: Any?, error: Error?) {
        guard let continuation = pending.removeValue(forKey: id) else { return }
        if let error { continuation.resume(throwing: error) }
        else { continuation.resume(returning: JSONValue.bridge(value)) }
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

    /// 需要整段 HTML 的书源（起点中文这类）在这里换页。
    /// 没有注册 HTML 时回到空白沙箱页；同一条书源不重复加载。
    private func ensureDocument(for sourceID: String) async throws {
        // init 里那次空白页加载是异步启动的；先等它结束，否则它会把下面
        // 换页用的 navigationDelegate 覆盖掉，自定义 HTML 永远等不到 didFinish。
        try await documentReady?.value
        let html = HTMLSourceRegistry.shared.html(for: sourceID)
        let targetID = html == nil ? "" : sourceID
        if loadedSourceID != targetID {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                let loader = BlankDocumentLoader(continuation: continuation)
                documentSession = loader
                webView.navigationDelegate = loader
                webView.loadHTMLString(
                    html ?? "<!doctype html><html><head><meta charset=\"utf-8\"></head><body></body></html>",
                    baseURL: nil
                )
            }
            loadedSourceID = targetID
        } else if targetID.isEmpty {
            try await documentReady?.value
        }
        currentSourceID = sourceID
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
        // 起点中文这类书源整段 HTML 依赖 flutter_inappwebview.callHandler。
        // 这里用同一条原生桥接把它的 15 个 handler 接过来；页面自己的网络
        // 出口仍然是 __legadoFetch，私网闸门不会因为换了页面而失效。
        window.flutter_inappwebview = {
          callHandler: function (name) {
            var args = Array.prototype.slice.call(arguments, 1);
            return new Promise(function (resolve, reject) {
              var id = 'h-' + String(Date.now()) + '-' + Math.random();
              window.__legadoPending[id] = { resolve: resolve, reject: reject };
              window.webkit.messageHandlers.legadoBridge.postMessage(
                { id: id, op: 'htmlHandler', name: String(name), args: args });
            });
          }
        };
        window.dispatchEvent(new Event('flutterInAppWebViewPlatformReady'));
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
        if op == "htmlHandler" {
            await handleHTMLHandler(id: id, body: body)
            return
        }
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

    private func handleHTMLHandler(id: String, body: [String: Any]) async {
        let name = body["name"] as? String ?? ""
        let args = body["args"] as? [Any] ?? []
        let text = { (index: Int) -> String in
            guard args.indices.contains(index) else { return "" }
            return Self.stringifyAny(args[index])
        }
        switch name {
        case "http":
            guard let url = URL(string: text(1)), ["http", "https"].contains(url.scheme?.lowercased() ?? "") else {
                callbackJSON(id, value: .object(["statusCode": .number(0), "data": .string(""), "headers": .object([:])]))
                return
            }
            var request = URLRequest(url: url)
            request.httpMethod = text(0).lowercased() == "post" ? "POST" : "GET"
            if request.httpMethod == "POST" { request.httpBody = Data(text(2).utf8) }
            if let headerText = text(3).data(using: .utf8),
               let headers = try? JSONSerialization.jsonObject(with: headerText) as? [String: Any] {
                for (key, value) in headers { request.setValue(String(describing: value), forHTTPHeaderField: key) }
            }
            do {
                let response = try await transport.data(for: request)
                callbackJSON(id, value: .object([
                    "statusCode": .number(Double(response.statusCode)),
                    "data": .string(response.decodedText),
                    "headers": .object([:])
                ]))
            } catch {
                callbackJSON(id, value: .object([
                    "statusCode": .number(0), "data": .string(error.localizedDescription), "headers": .object([:])
                ]))
            }
        case "cache.get":
            let value = BookSourceRuntimeStore.shared.get(
                sourceID: currentSourceID, key: "html.cache.\(text(0))"
            )
            callback(id, ok: true, value: value)
        case "cache.set":
            BookSourceRuntimeStore.shared.put(
                sourceID: currentSourceID, key: "html.cache.\(text(0))", value: text(1)
            )
            callback(id, ok: true, value: "true")
        case "cookie.get":
            callback(id, ok: true, value: LegadoCookieStore.shared.cookieHeader(for: text(0)))
        case "cookie.getCookie":
            callback(id, ok: true, value: LegadoCookieStore.shared.cookie(for: text(0), key: text(1)))
        case "CookieJar", "refreshExplore", "refreshContent":
            callback(id, ok: true, value: "true")
        case "showToast", "showLongToast":
            NotificationCenter.default.post(name: .legadoToast, object: nil, userInfo: ["message": text(0)])
            callback(id, ok: true, value: "true")
        case "log":
            DiagnosticLog.shared.record(.info, category: "htmljs", message: text(0))
            callback(id, ok: true, value: "true")
        case "base64encode":
            callback(id, ok: true, value: Data(text(0).utf8).base64EncodedString())
        case "startBrowser", "startBrowserDp":
            callback(id, ok: true, value: "")
        default:
            DiagnosticLog.shared.record(.warning, category: "htmljs", message: "未实现的桥接：\(name)")
            callback(id, ok: true, value: "")
        }
    }

    private func callbackJSON(_ id: String, value: JSONValue) {
        guard let data = try? JSONEncoder().encode(value),
              let literal = String(data: data, encoding: .utf8) else {
            callback(id, ok: false, value: "null")
            return
        }
        webView.evaluateJavaScript("window.__legadoResolve(\(Self.jsonLiteral(id)), true, \(literal));")
    }

    private static func stringifyAny(_ value: Any) -> String {
        if let text = value as? String { return text }
        if let number = value as? NSNumber { return number.stringValue }
        if let data = try? JSONEncoder().encode(JSONValue.bridge(value)) {
            return String(decoding: data, as: UTF8.self)
        }
        return String(describing: value)
    }

    private func callback(_ id: String, ok: Bool, value: String) {
        let literal = Self.jsonLiteral(value)
        webView.evaluateJavaScript("window.__legadoResolve(\(Self.jsonLiteral(id)), \(ok), \(literal));")
    }

    /// 把值写成可以拼进脚本的 JS 字面量。
    ///
    /// 这里**不能**用 `JSONSerialization.data(withJSONObject:)`：它对顶层片段
    /// （字符串、数字、null）抛的是 ObjC 异常，`try?` 拦不住，进程直接 abort。
    /// 而 `<webjs>` 的输入几乎总是正文 HTML 这种**字符串**，第一句赋值就会踩中。
    /// 走 `JSONValue` + `JSONEncoder` 就没有这个限制，JSON 又能直接当 JS 字面量用。
    private static func jsonLiteral(_ value: Any) -> String {
        guard let data = try? JSONEncoder().encode(JSONValue.bridge(value)),
              let text = String(data: data, encoding: .utf8) else { return "null" }
        return text
    }
}

/// 只等待那一次空白文档加载，完成即失效。
@MainActor
private final class BlankDocumentLoader: NSObject, WKNavigationDelegate {
    private var continuation: CheckedContinuation<Void, Error>?
    private var settled = false

    init(continuation: CheckedContinuation<Void, Error>? = nil) {
        self.continuation = continuation
    }

    func wait() async throws {
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
        }
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
