import Foundation
import WebKit

/// WebView 页面请求的失败原因。
///
/// 每一种都要能直接念给用户听：书源里写了 `webView:true` 却打不开时，
/// 「页面没加载完」和「被私网闸门拦了」是两件完全不同的事。
public enum WebViewPageError: Error, LocalizedError, Sendable {
    case timeout(Int)
    case noResponse
    case blocked(String)
    case responseTooLarge(Int)
    case scriptFailed(String)
    case unsupported(String)

    public var errorDescription: String? {
        switch self {
        case .timeout(let seconds): "WebView 页面 \(seconds) 秒内没有加载完成"
        case .noResponse: "WebView 没有拿到页面内容"
        case .blocked(let host): "已拦截私网地址：\(host)"
        case .responseTooLarge(let bytes): "WebView 页面超过 \(bytes / 1_048_576) MB，已放弃"
        case .scriptFailed(let message): "WebView 脚本执行失败：\(message)"
        case .unsupported(let detail): detail
        }
    }
}

/// 一次 WebView 页面请求的实际经过，供调试界面如实展示。
///
/// 书源调试页最怕的就是「看起来跑了，其实走的是普通请求」。这里记录的是
/// 执行器**真的做了什么**：是否用了 WebView、是直接打开还是载入预取 HTML、
/// 有没有执行 `webJs`、`sourceRegex` 命中了哪个地址、耗时与字节数。
public struct WebViewTraceEntry: Identifiable, Sendable {
    public enum Mode: String, Sendable {
        case page
        case prefetchedHTML

        public var title: String {
            switch self {
            case .page: "WKWebView 直接打开"
            case .prefetchedHTML: "原生预取 HTML 后载入"
            }
        }
    }

    public var id = UUID()
    public var date = Date()
    public var sourceName: String
    public var url: String
    public var mode: Mode
    public var statusCode: Int
    public var byteCount: Int
    public var elapsedMilliseconds: Int
    public var usedWebJs: Bool
    public var delayMilliseconds: Int
    public var matchedSourceRegex: String?
    public var error: String?
}

/// 阅读 3.0 书源里 `webView:true` 请求的真实执行器。
///
/// 书源的搜索 / 详情 / 目录 / 正文地址可以写成
/// `https://site/search?q={{key}},{"webView":true}`：这类站点靠页面里的
/// JS 渲染出内容，普通 HTTP 请求拿到的只是一副空壳。这里的做法是：
///
/// 1. 用 `WKWebView` 真正打开那个地址（GET），或把原生预取到的 HTML
///    交给 `loadHTMLString`（POST 分支，见 `SourceNetworkPolicy.executeWebView`）；
/// 2. 等到主框架加载完成，再按 `webViewDelayTime` 多等一会儿，让页面脚本渲染完；
/// 3. 书源声明了 `webJs` 就在页面里执行它，返回值即正文；没声明就取
///    `document.documentElement.outerHTML`；
/// 4. 把结果包成 `HTTPResponse` 交回流水线，后面的正文规则、`bodyJs`
///    与解析步骤与普通请求完全一致。
///
/// 沙箱边界（都是真的，不是默认值）：
/// - 每个书源一只 `WKWebView`，用 `nonPersistent()` 数据仓库：
///   cookie 只在内存里、只在本次运行内、且不跨书源串味；
/// - 主框架与每一次导航都过 `PrivateHostGate`；
/// - 子资源（图片 / 脚本 / XHR）无法逐个回调原生，因此用
///   `WKContentRuleList` 拦掉本机与私网段的地址，并在文档开头注入一段
///   看守脚本，把 `fetch` / `XHR` / `WebSocket` 指向私网的调用直接拒绝；
/// - 不支持代理、不支持非 GET（POST 由原生预取后走 HTML 分支）。
@MainActor
public final class WebViewSourcePageExecutor: NSObject, SourceWebViewRequestExecuting {
    public static let shared = WebViewSourcePageExecutor()

    /// 同时保留的页面数。WebKit 的进程很贵，但同时开太多也会拖垮内存。
    private static let maximumPages = 3
    /// 单页正文上限：超过这个体量的 HTML 已经不像正文页了。
    private static let maximumBodyBytes = 4 * 1_024 * 1_024
    /// `webJs` 返回值上限，与 `<webjs>` 规则保持一致。
    private static let maximumScriptResultBytes = 2 * 1_024 * 1_024

    private var pages: [String: Page] = [:]

    private override init() { super.init() }

    // MARK: - 页面宿主

    /// 一只 `WKWebView` 加一把串行锁。
    ///
    /// 流水线里同一个书源可能同时有搜索与正文在跑；`WKWebView` 只有一个
    /// 主框架，两次 `load` 会互相打断。所以在页面这一层排队，而不是在
    /// 服务层排队 —— 不同书源仍然可以并行。
    @MainActor
    private final class Page {
        let webView: WKWebView
        let gate = SerialGate()
        var lastUsed = Date()
        init(webView: WKWebView) { self.webView = webView }
    }

    @MainActor
    private final class SerialGate {
        private var busy = false
        private var waiters: [CheckedContinuation<Void, Never>] = []

        func acquire() async {
            if !busy {
                busy = true
                return
            }
            await withCheckedContinuation { waiters.append($0) }
        }

        func release() {
            if waiters.isEmpty { busy = false }
            else { waiters.removeFirst().resume() }
        }
    }

    private func page(for source: BookSource) async -> Page {
        if let existing = pages[source.id] {
            existing.lastUsed = Date()
            return existing
        }
        if pages.count >= Self.maximumPages,
           let oldest = pages.min(by: { $0.value.lastUsed < $1.value.lastUsed }) {
            oldest.value.webView.stopLoading()
            oldest.value.webView.navigationDelegate = nil
            pages.removeValue(forKey: oldest.key)
        }

        let configuration = WKWebViewConfiguration()
        // 不落盘：书源的登录态不该以系统级 cookie 的形式留在设备上。
        configuration.websiteDataStore = .nonPersistent()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        configuration.preferences.isFraudulentWebsiteWarningEnabled = true
        if let list = await Self.privateHostRuleList() {
            configuration.userContentController.add(list)
        }
        configuration.userContentController.addUserScript(Self.networkGuardScript)
        let webView = WKWebView(
            frame: CGRect(x: 0, y: 0, width: 390, height: 900),
            configuration: configuration
        )
        webView.customUserAgent = ApplicationSettingsStore.shared.settings.effectiveUserAgent
        let page = Page(webView: webView)
        pages[source.id] = page
        return page
    }

    // MARK: - 执行

    public func execute(
        _ prepared: PreparedRequest,
        source: BookSource,
        timeout: TimeInterval
    ) async throws -> HTTPResponse {
        try Task.checkCancellation()
        if let proxy = prepared.proxy, !proxy.isEmpty {
            throw WebViewPageError.unsupported("WebView 请求不支持代理；请在书源里为这个地址改用普通请求")
        }
        guard prepared.method == .get || prepared.webViewHTML != nil else {
            throw WebViewPageError.unsupported("WebView 只支持 GET，或由原生预取 POST 后的页面")
        }
        if let host = prepared.url.host, PrivateHostGate.shouldBlock(host) {
            throw WebViewPageError.blocked(host)
        }

        let page = await page(for: source)
        await page.gate.acquire()
        defer { page.gate.release() }
        page.lastUsed = Date()

        let started = Date()
        do {
            applyIdentity(prepared, to: page.webView)
            try await applyCookies(prepared.headers, for: prepared.url, webView: page.webView)

            let session = PageLoadSession()
            page.webView.navigationDelegate = session
            let outcome = try await session.load(
                page.webView,
                request: prepared.webViewHTML == nil ? prepared.urlRequest(timeout: timeout, handleCookies: false) : nil,
                html: prepared.webViewHTML,
                baseURL: prepared.url,
                timeout: timeout
            )
            try Task.checkCancellation()

            if prepared.webViewDelayMilliseconds > 0 {
                try await Task.sleep(nanoseconds: UInt64(prepared.webViewDelayMilliseconds) * 1_000_000)
            }

            // `sourceRegex`（资源正则）在阅读 3.0 里的语义是：页面加载过程中
            // 有某个子资源地址命中这条正则时，直接把**那个地址**当作响应体，
            // 交给后续正文规则（通常是 JSON 接口，页面只是套壳）。
            // 命中就不再取 DOM —— 与 Legado 的 SnifferWebClient 一致。
            let regexMatch = try await matchingResourceURL(prepared.sourceRegex, webView: page.webView)
            if let matched = regexMatch {
                let body = Data(matched.utf8)
                record(
                    WebViewTraceEntry(
                        sourceName: source.bookSourceName,
                        url: prepared.url.absoluteString,
                        mode: prepared.webViewHTML == nil ? .page : .prefetchedHTML,
                        statusCode: outcome.statusCode,
                        byteCount: body.count,
                        elapsedMilliseconds: Int(Date().timeIntervalSince(started) * 1_000),
                        usedWebJs: prepared.webJavaScript != nil,
                        delayMilliseconds: prepared.webViewDelayMilliseconds,
                        matchedSourceRegex: matched
                    )
                )
                return HTTPResponse(
                    data: body,
                    statusCode: outcome.statusCode,
                    headers: outcome.headers,
                    finalURL: URL(string: matched) ?? prepared.url,
                    requestedCharset: "utf-8"
                )
            }

            let html = try await page.webView.evaluateJavaScript(
                "document.documentElement.outerHTML"
            ) as? String ?? ""

            let text: String
            if let script = prepared.webJavaScript {
                text = try await runWebScript(script, html: html, webView: page.webView)
            } else if html.isEmpty {
                throw WebViewPageError.noResponse
            } else {
                text = html
            }

            let body = Data(text.utf8)
            guard body.count <= Self.maximumBodyBytes else {
                throw WebViewPageError.responseTooLarge(Self.maximumBodyBytes)
            }
            record(
                WebViewTraceEntry(
                    sourceName: source.bookSourceName,
                    url: prepared.url.absoluteString,
                    mode: prepared.webViewHTML == nil ? .page : .prefetchedHTML,
                    statusCode: outcome.statusCode,
                    byteCount: body.count,
                    elapsedMilliseconds: Int(Date().timeIntervalSince(started) * 1_000),
                    usedWebJs: prepared.webJavaScript != nil,
                    delayMilliseconds: prepared.webViewDelayMilliseconds,
                    matchedSourceRegex: nil
                )
            )
            // `evaluateJavaScript` 返回的永远是 UTF-8 字符串，原文档可能是 GBK：
            // 这一步已经由 WebKit 解码过，必须如实标注，否则下游会按 GBK 再解一次。
            return HTTPResponse(
                data: body,
                statusCode: outcome.statusCode,
                headers: outcome.headers,
                finalURL: outcome.finalURL ?? prepared.url,
                requestedCharset: "utf-8"
            )
        } catch {
            record(
                WebViewTraceEntry(
                    sourceName: source.bookSourceName,
                    url: prepared.url.absoluteString,
                    mode: prepared.webViewHTML == nil ? .page : .prefetchedHTML,
                    statusCode: 0,
                    byteCount: 0,
                    elapsedMilliseconds: Int(Date().timeIntervalSince(started) * 1_000),
                    usedWebJs: prepared.webJavaScript != nil,
                    delayMilliseconds: prepared.webViewDelayMilliseconds,
                    matchedSourceRegex: nil,
                    error: error.localizedDescription
                )
            )
            throw error
        }
    }

    // MARK: - 调试轨迹

    /// 最近若干次 WebView 请求的真实经过，最新在前。
    /// 只保留最近 20 条：这是给人看的诊断信息，不是数据。
    public private(set) var recentTraces: [WebViewTraceEntry] = []

    private func record(_ entry: WebViewTraceEntry) {
        recentTraces.insert(entry, at: 0)
        if recentTraces.count > 20 { recentTraces.removeLast(recentTraces.count - 20) }
        DiagnosticLog.shared.record(
            entry.error == nil ? .info : .error,
            category: "WebView",
            message: "\(entry.sourceName) · \(entry.url) · \(entry.mode.title) · HTTP \(entry.statusCode) · \(entry.byteCount) 字节 · \(entry.elapsedMilliseconds) ms"
                + (entry.matchedSourceRegex.map { " · 资源正则命中 \($0)" } ?? "")
                + (entry.error.map { " · 失败：\($0)" } ?? "")
        )
    }

    /// 在页面已加载的资源地址里找第一个命中 `sourceRegex` 的。
    ///
    /// 地址来源是页面自己报告的 `performance.getEntriesByType('resource')`
    /// 加上看守脚本记录的 `fetch` / `XHR` —— 都是真的加载过的地址，
    /// 不是猜的。匹配用整串匹配（等价于 Kotlin 的 `Regex.matches`）。
    private func matchingResourceURL(_ rawPattern: String?, webView: WKWebView) async throws -> String? {
        guard let pattern = rawPattern?.trimmingCharacters(in: .whitespacesAndNewlines),
              !pattern.isEmpty else { return nil }
        let expression: NSRegularExpression
        do {
            expression = try NSRegularExpression(pattern: pattern)
        } catch {
            throw RuleEngineError.malformedRule(rule: "ruleContent.sourceRegex", detail: "资源正则无效：\(error.localizedDescription)")
        }
        // `evaluateJavaScript` 是把脚本当**脚本**跑，不是当函数体：
        // 顶层的 `return` 是语法错误（"Return statements are only valid inside
        // functions"），整条 WebView 请求会直接失败。带资源正则的书源都会
        // 走到这里，所以必须包一层 IIFE —— 之前这条路径没有测试，一直没被
        // 发现，等于所有声明了 `sourceRegex` 的书源都读不了。
        let script = """
        (function () {
          const seen = new Set(window.__legadoResourceURLs || []);
          try {
            performance.getEntriesByType('resource').forEach(function (e) { seen.add(e.name); });
          } catch (e) {}
          return Array.from(seen);
        })();
        """
        let raw = try await webView.evaluateJavaScript(script) as? [String] ?? []
        return raw.first { candidate in
            let range = NSRange(candidate.startIndex..., in: candidate)
            return expression.firstMatch(in: candidate, range: range)?.range == range
        }
    }

    // MARK: - 请求细节

    private func applyIdentity(_ prepared: PreparedRequest, to webView: WKWebView) {
        let userAgent = prepared.headers.first {
            $0.key.caseInsensitiveCompare("User-Agent") == .orderedSame
        }?.value
        // 书源把 UA 写成 `null` 表示「完全不发 UA」，但 WKWebView 总会带一个。
        // 取最接近的做法：用系统默认值，并如实记一条日志说明这是平台限制。
        if prepared.suppressesUserAgent {
            webView.customUserAgent = nil
            DiagnosticLog.shared.record(
                .warning, category: "WebView",
                message: "书源要求不发 User-Agent，但 WKWebView 无法移除，已改用系统默认 UA"
            )
        } else {
            webView.customUserAgent = userAgent
                ?? ApplicationSettingsStore.shared.settings.effectiveUserAgent
        }
    }

    /// 把书源请求头里的 Cookie 交给 WebView 的 cookie 仓库。
    ///
    /// 页面脚本自己发起的请求不会带 `PreparedRequest.headers`，只认站点的
    /// cookie；不搬过去的话，需要登录的 WebView 书源会一律跳登录页。
    private func applyCookies(
        _ headers: [String: String],
        for url: URL,
        webView: WKWebView
    ) async throws {
        guard let raw = headers.first(where: { $0.key.caseInsensitiveCompare("Cookie") == .orderedSame })?.value,
              !raw.isEmpty,
              let host = url.host else { return }
        let store = webView.configuration.websiteDataStore.httpCookieStore
        for part in raw.split(separator: ";") {
            let pair = part.split(separator: "=", maxSplits: 1).map(String.init)
            guard pair.count == 2 else { continue }
            let properties: [HTTPCookiePropertyKey: Any] = [
                .name: pair[0].trimmingCharacters(in: .whitespaces),
                .value: pair[1].trimmingCharacters(in: .whitespaces),
                .domain: host,
                .path: "/",
                .secure: url.scheme?.lowercased() == "https" ? "TRUE" : "FALSE"
            ]
            guard let cookie = HTTPCookie(properties: properties) else { continue }
            await withCheckedContinuation { continuation in
                store.setCookie(cookie) { continuation.resume() }
            }
            try Task.checkCancellation()
        }
    }

    /// 在页面里执行书源的 `webJs`。
    ///
    /// 与 `<webjs>` 规则保持一致：脚本拿到 `result`（这里是页面 HTML），
    /// 用 `return` 交回正文。页面环境里 `document` / `window` 都是真的，
    /// 所以需要从渲染结果里二次提取的写法也能用。
    private func runWebScript(_ script: String, html: String, webView: WKWebView) async throws -> String {
        guard script.utf8.count <= 64 * 1_024 else {
            throw RuleEngineError.resourceLimit(rule: "webJs", detail: "WebView 注入脚本超过 64 KB")
        }
        // 书源的 webJs 写法有两种：单个表达式（`document.body.innerText`），
        // 和自带顶层 `return` 的整段函数体。前者要包一层 `return await (…)`，
        // 后者原样跑；尾部分号在两种写法里都常见，包进括号前必须摘掉，
        // 否则是语法错误。
        var expression = script.trimmingCharacters(in: .whitespacesAndNewlines)
        while expression.hasSuffix(";") {
            expression.removeLast()
            expression = expression.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let attempts = expression.isEmpty
            ? []
            : ["return await (\(expression));"]
        do {
            return try await executeScript(
                attempts.first ?? script,
                html: html,
                webView: webView
            )
        } catch let error as RuleEngineError {
            throw error
        } catch {
            guard expression.range(of: #"\breturn\b"#, options: .regularExpression) != nil else {
                throw WebViewPageError.scriptFailed(error.localizedDescription)
            }
            do {
                return try await executeScript(script, html: html, webView: webView)
            } catch let inner as RuleEngineError {
                throw inner
            } catch {
                throw WebViewPageError.scriptFailed(error.localizedDescription)
            }
        }
    }

    private func executeScript(_ body: String, html: String, webView: WKWebView) async throws -> String {
        let value = try await webView.callAsyncJavaScript(
            "const result = html;\n\(body)",
            arguments: ["html": html],
            in: nil,
            contentWorld: .page
        )
        let text = (value as? String) ?? ""
        guard text.utf8.count <= Self.maximumScriptResultBytes else {
            throw RuleEngineError.resourceLimit(rule: "webJs", detail: "WebView 脚本结果超过 2 MB")
        }
        // 脚本只是观察到没有可交回的东西时，页面本身就是结果。
        return text.isEmpty ? html : text
    }

    // MARK: - 私网子资源拦截

    private static var cachedRuleList: WKContentRuleList?
    private static var ruleListFailed = false

    /// 把「本机 / 私网」的地址挡在子资源加载之前。
    ///
    /// WebKit 不允许为 http / https 注册 `WKURLSchemeHandler`（会直接抛
    /// `'http' is a URL scheme that WKWebView handles natively`），所以子资源
    /// 没有原生回调可用。`WKContentRuleList` 是唯一在进程内、加载前生效的
    /// 拦截手段：匹配到的请求根本不会发出去。
    ///
    /// 规则只写能确定会被编译的前缀形式，编译失败就如实记一条日志然后继续 ——
    /// 宁可少一层防护并说出来，也不要让整个 WebView 请求因为编不出规则而失败。
    private static func privateHostRuleList() async -> WKContentRuleList? {
        if let cachedRuleList { return cachedRuleList }
        if ruleListFailed { return nil }

        let patterns = [
            "^[a-zA-Z][a-zA-Z0-9+.-]*://localhost",
            "^[a-zA-Z][a-zA-Z0-9+.-]*://[^/]*\\.local/",
            "^[a-zA-Z][a-zA-Z0-9+.-]*://[^/]*\\.internal/",
            "^[a-zA-Z][a-zA-Z0-9+.-]*://127\\.",
            "^[a-zA-Z][a-zA-Z0-9+.-]*://0\\.",
            "^[a-zA-Z][a-zA-Z0-9+.-]*://10\\.",
            "^[a-zA-Z][a-zA-Z0-9+.-]*://192\\.168\\.",
            "^[a-zA-Z][a-zA-Z0-9+.-]*://169\\.254\\.",
            "^[a-zA-Z][a-zA-Z0-9+.-]*://172\\.1[6-9]\\.",
            "^[a-zA-Z][a-zA-Z0-9+.-]*://172\\.2[0-9]\\.",
            "^[a-zA-Z][a-zA-Z0-9+.-]*://172\\.3[01]\\.",
            "^https?://\\[::1\\]"
        ]
        let rules = patterns.map { pattern in
            "{\"trigger\":{\"url-filter\":\"\(pattern)\",\"url-filter-is-case-sensitive\":false},\"action\":{\"type\":\"block\"}}"
        }
        let encoded = "[" + rules.joined(separator: ",") + "]"
        do {
            let list = try await WKContentRuleListStore.default().compileContentRuleList(
                forIdentifier: "yhc-private-hosts-v1",
                encodedContentRuleList: encoded
            )
            cachedRuleList = list
            return list
        } catch {
            ruleListFailed = true
            DiagnosticLog.shared.record(
                .warning, category: "WebView",
                message: "私网子资源规则编译失败，本次仅拦截主框架：\(error.localizedDescription)"
            )
            return nil
        }
    }

    /// 文档开头注入的看守。
    ///
    /// 做两件事：
    /// 1. 把页面脚本自己发起的私网请求直接拒绝（fetch / XHR / WebSocket /
    ///    EventSource / sendBeacon）；
    /// 2. 记下 `fetch` 与 `XHR` 请求过的地址。阅读 3.0 的 `sourceRegex`
    ///    是「子资源地址命中正则就以该地址为响应」，而这些接口请求常常是
    ///    由页面脚本发出的，`performance.getEntriesByType('resource')`
    ///    不一定能可靠地覆盖，两个来源合起来才算没漏。
    private static var networkGuardScript: WKUserScript {
        let source = """
        (function () {
          window.__legadoResourceURLs = window.__legadoResourceURLs || [];
          function remember(url) {
            try {
              var absolute = new URL(String(url), location.href).href;
              if (window.__legadoResourceURLs.indexOf(absolute) < 0) {
                window.__legadoResourceURLs.push(absolute);
              }
            } catch (e) {}
          }
          function blockedHost(raw) {
            try {
              var host = String(raw || '').toLowerCase();
              if (!host) return false;
              if (host === 'localhost' || host.endsWith('.localhost')) return true;
              if (host.endsWith('.local') || host.endsWith('.internal')) return true;
              var bare = host.replace(/^\\[|\\]$/g, '');
              if (bare === '::1' || bare === '::') return true;
              var m = bare.match(/^(\\d+)\\.(\\d+)\\.(\\d+)\\.(\\d+)$/);
              if (!m) return false;
              var a = +m[1], b = +m[2];
              if (a === 0 || a === 127 || a === 10) return true;
              if (a === 192 && b === 168) return true;
              if (a === 169 && b === 254) return true;
              if (a === 172 && b >= 16 && b <= 31) return true;
              return false;
            } catch (e) { return false; }
          }
          function hostOf(url) {
            try { return new URL(String(url), location.href).hostname; }
            catch (e) { return ''; }
          }
          var nativeFetch = window.fetch;
          if (nativeFetch) {
            window.fetch = function (input, init) {
              var url = typeof input === 'string' ? input : (input && input.url) || '';
              if (blockedHost(hostOf(url))) {
                return Promise.reject(new Error('blocked private host: ' + url));
              }
              remember(url);
              return nativeFetch.apply(this, arguments);
            };
          }
          var nativeOpen = XMLHttpRequest.prototype.open;
          XMLHttpRequest.prototype.open = function (method, url) {
            if (blockedHost(hostOf(url))) {
              throw new Error('blocked private host: ' + url);
            }
            remember(url);
            return nativeOpen.apply(this, arguments);
          };
          var nativeWS = window.WebSocket;
          if (nativeWS) {
            window.WebSocket = function (url, protocols) {
              if (blockedHost(hostOf(url))) {
                throw new Error('blocked private host: ' + url);
              }
              return new nativeWS(url, protocols);
            };
            window.WebSocket.prototype = nativeWS.prototype;
          }
          var nativeES = window.EventSource;
          if (nativeES) {
            window.EventSource = function (url, config) {
              if (blockedHost(hostOf(url))) {
                throw new Error('blocked private host: ' + url);
              }
              return new nativeES(url, config);
            };
            window.EventSource.prototype = nativeES.prototype;
          }
          var nativeBeacon = navigator.sendBeacon;
          if (nativeBeacon) {
            navigator.sendBeacon = function (url) {
              if (blockedHost(hostOf(url))) return false;
              return nativeBeacon.apply(this, arguments);
            };
          }
        })();
        """
        return WKUserScript(source: source, injectionTime: .atDocumentStart, forMainFrameOnly: false)
    }
}

// MARK: - 一次导航

/// 一次页面加载的等待与结果收集。
///
/// 单独一个对象而不是让执行器实现 `WKNavigationDelegate`：一只页面会被
/// 多次复用，若把代理挂在执行器上，上一次的等待会被下一次的导航回调误唤醒。
/// 每次 `load` 换一个新会话，回调只会喂给这一次。
@MainActor
private final class PageLoadSession: NSObject, WKNavigationDelegate {
    struct Outcome {
        var statusCode: Int
        var headers: [String: String]
        var finalURL: URL?
    }

    private var continuation: CheckedContinuation<Outcome, Error>?
    private var timer: Task<Void, Never>?
    private var settled = false
    private var statusCode = 0
    private var headers: [String: String] = [:]
    private var finalURL: URL?

    func load(
        _ webView: WKWebView,
        request: URLRequest?,
        html: String?,
        baseURL: URL,
        timeout: TimeInterval
    ) async throws -> Outcome {
        let seconds = max(Int(timeout.rounded()), 1)
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                self.continuation = continuation
                self.timer = Task { [weak self] in
                    try? await Task.sleep(nanoseconds: UInt64(seconds) * 1_000_000_000)
                    guard !Task.isCancelled else { return }
                    self?.settle(.failure(WebViewPageError.timeout(seconds)))
                }
                if let html {
                    webView.loadHTMLString(html, baseURL: baseURL)
                } else if let request {
                    webView.load(request)
                } else {
                    self.settle(.failure(WebViewPageError.unsupported("页面请求缺少地址")))
                }
            }
        } onCancel: {
            Task { @MainActor [weak self] in
                self?.settle(.failure(CancellationError()))
            }
        }
    }

    private func settle(_ result: Result<Outcome, Error>) {
        guard !settled, let continuation else { return }
        settled = true
        self.continuation = nil
        timer?.cancel()
        timer = nil
        switch result {
        case .success(let value): continuation.resume(returning: value)
        case .failure(let error): continuation.resume(throwing: error)
        }
    }

    private var collected: Outcome {
        .init(statusCode: statusCode == 0 ? 200 : statusCode, headers: headers, finalURL: finalURL)
    }

    // MARK: WKNavigationDelegate
    //
    // 决策方法在 SDK 里标了 `WK_SWIFT_ASYNC`，Swift 侧只有 async 版本；
    // 写成 completion-handler 形式不会报错，但也**不会被当成实现**，
    // 结果是私网闸门静默失效。必须用 async 签名。

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction
    ) async -> WKNavigationActionPolicy {
        if let host = navigationAction.request.url?.host, PrivateHostGate.shouldBlock(host) {
            settle(.failure(WebViewPageError.blocked(host)))
            return .cancel
        }
        return .allow
    }

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationResponse: WKNavigationResponse
    ) async -> WKNavigationResponsePolicy {
        if navigationResponse.isForMainFrame, let http = navigationResponse.response as? HTTPURLResponse {
            statusCode = http.statusCode
            headers = http.allHeaderFields.reduce(into: [:]) { result, entry in
                result[String(describing: entry.key)] = String(describing: entry.value)
            }
            finalURL = http.url
        }
        return .allow
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        settle(.success(collected))
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        settle(.failure(error))
    }

    func webView(
        _ webView: WKWebView,
        didFailProvisionalNavigation navigation: WKNavigation!,
        withError error: Error
    ) {
        settle(.failure(error))
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        settle(.failure(WebViewPageError.noResponse))
    }
}
