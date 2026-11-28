import Foundation
import WebKit

/// `java.webView(url, baseURL, js)` 的同步桥。
///
/// 书源的正文规则在 JavaScriptCore 的同步线程里执行，而站点自身的反爬脚本
/// 必须在 WKWebView 的 DOM 里跑。这里把 HTML 预取好交给一只一次性 WebView，
/// 把异步执行包装成同步结果；调用方必须是规则工作线程，不能是主线程。
enum WebViewSyncBridge {
    static func evaluate(html: String, script: String, timeout: TimeInterval = 10) throws -> String {
        guard !Thread.isMainThread else {
            throw RuleEngineError.invalidInput(
                rule: "java.webView",
                expected: "不能在主线程同步执行 WebView 规则"
            )
        }
        let semaphore = DispatchSemaphore(value: 0)
        let lock = NSLock()
        nonisolated(unsafe) var result: Result<String, Error>?
        DispatchQueue.main.async {
            Task {
                let outcome: Result<String, Error>
                do {
                    let value = try await SynchronousWebViewRunner.shared.run(
                        html: html, script: script, timeout: timeout
                    )
                    outcome = .success(value)
                } catch {
                    outcome = .failure(error)
                }
                lock.withLock { result = outcome }
                semaphore.signal()
            }
        }
        guard semaphore.wait(timeout: .now() + timeout + 2) == .success else {
            throw WebJavaScriptError.timeout
        }
        return try lock.withLock { try result?.get() ?? "" }
    }
}

/// 一次性、非持久化的 WKWebView；只执行调用方给的 HTML 与脚本，不发网络请求。
@MainActor
final class SynchronousWebViewRunner: NSObject {
    static let shared = SynchronousWebViewRunner()

    private let webView: WKWebView
    private var loadDelegate: HTMLDocumentLoader?

    private override init() {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 390, height: 844), configuration: configuration)
        super.init()
    }

    func run(html: String, script: String, timeout: TimeInterval) async throws -> String {
        let loader = HTMLDocumentLoader(timeout: timeout)
        loadDelegate = loader
        webView.navigationDelegate = loader
        webView.loadHTMLString(html, baseURL: nil)
        try await loader.waitForLoad()
        let value = try await webView.callAsyncJavaScript(
            "return String(await (\(script)) || '');",
            arguments: [:],
            in: nil,
            contentWorld: .page
        )
        return JSONValue.bridge(value).stringValue
    }
}

@MainActor
private final class HTMLDocumentLoader: NSObject, WKNavigationDelegate {
    private let timeout: TimeInterval
    private var continuation: CheckedContinuation<Void, Error>?
    private var settled = false

    init(timeout: TimeInterval) {
        self.timeout = timeout
    }

    func waitForLoad() async throws {
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            DispatchQueue.main.asyncAfter(deadline: .now() + timeout) { [weak self] in
                self?.settle(.failure(WebJavaScriptError.timeout))
            }
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        settle(.success(()))
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        settle(.failure(error))
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        settle(.failure(error))
    }

    private func settle(_ result: Result<Void, Error>) {
        guard !settled, let continuation else { return }
        settled = true
        self.continuation = nil
        continuation.resume(with: result)
    }
}
