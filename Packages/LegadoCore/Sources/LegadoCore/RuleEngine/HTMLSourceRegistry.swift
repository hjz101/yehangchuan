import Foundation

/// 起点中文这类「整本书源就是一段 HTML + JS」的来源注册表。
///
/// 它不是阅读 3.0 的 JSON 书源，`BookSourceImporter` 会把未知字段留在
/// `additionalFields` 里。导入时把 HTML 按 `bookSourceUrl` 注册进来，
/// `<webjs>` 执行器据此把这段 HTML 装进自己的 WKWebView，
/// 再用书源暴露的 `search/info/chapter/content/login` 入口函数取数据。
public final class HTMLSourceRegistry: @unchecked Sendable {
    public static let shared = HTMLSourceRegistry()

    private let lock = NSLock()
    private var documents: [String: String] = [:]

    private init() {}

    public func register(html: String, for sourceID: String) {
        lock.lock()
        documents[sourceID] = html
        lock.unlock()
    }

    public func html(for sourceID: String) -> String? {
        lock.lock()
        defer { lock.unlock() }
        return documents[sourceID]
    }

    public func contains(_ sourceID: String) -> Bool {
        html(for: sourceID) != nil
    }
}
