import Foundation

/// 开箱即用的离线示例书源。
///
/// 书源引擎、规则解析和分页都是真的，但外部站点不可控、也无法在离线环境验证。
/// 这里用 `yhdemo://` 自定义 scheme 把「搜索 → 详情 → 目录 → 正文」四段请求
/// 交给 App 注入的本机内容，让链路在没有网络时也能完整跑通。
/// 它仍是**真书源**：规则由 `BookSourceImporter` 解码，请求走传输层与私网闸门，
/// 和联网书源没有两样；只是内容由 App 提供。
public enum BuiltinDemoSource {
    public static let scheme = "yhdemo"
    public static let baseURL = "\(scheme)://demo.yh.app"

    /// 一条完整的 Legado 3.0 规则。字段与 `SourceView` 里的模板一致，
    /// 所以能在书源页查看、导出、编辑，校验也会通过。
    public static let ruleJSON = """
    {
      "bookSourceName": "夜航船·离线示例源",
      "bookSourceUrl": "\(baseURL)",
      "bookSourceGroup": "内置",
      "bookSourceType": 0,
      "enabled": false,
      "searchUrl": "\(baseURL)/search?q={{key}}",
      "ruleSearch": {
        "bookList": "$.books[*]",
        "name": "$.title",
        "author": "$.author",
        "bookUrl": "$.url",
        "intro": "$.intro"
      },
      "ruleBookInfo": {
        "name": "$.title",
        "author": "$.author",
        "intro": "$.intro",
        "tocUrl": "$.tocUrl"
      },
      "ruleToc": {
        "chapterList": "$.chapters[*]",
        "chapterName": "$.name",
        "chapterUrl": "$.url"
      },
      "ruleContent": {
        "content": "$.content"
      }
    }
    """

    private final class ResponderBox: @unchecked Sendable {
        private let lock = NSLock()
        private var value: (@Sendable (URLRequest) -> Data?)?
        func set(_ newValue: (@Sendable (URLRequest) -> Data?)?) {
            lock.withLock { value = newValue }
        }
        func get() -> (@Sendable (URLRequest) -> Data?)? {
            lock.withLock { value }
        }
    }

    private static let responderBox = ResponderBox()

    /// App 注入内容提供者。传 nil 可清空（测试隔离用）。
    public static func setResponder(_ value: (@Sendable (URLRequest) -> Data?)?) {
        responderBox.set(value)
    }

    /// 所有 `yhdemo` 请求共用同一个入口，注册一次即可。
    public static func register() {
        URLProtocol.registerClass(BuiltinDemoURLProtocol.self)
        URLSessionProtocolRegistry.register(BuiltinDemoURLProtocol.self)
    }

    static func data(for request: URLRequest) -> Data? {
        responderBox.get()?(request)
    }
}

final class BuiltinDemoURLProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool {
        request.url?.scheme?.lowercased() == BuiltinDemoSource.scheme
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let url = request.url else {
            client?.urlProtocolDidFinishLoading(self)
            return
        }
        let data = BuiltinDemoSource.data(for: request)
        let response = HTTPURLResponse(
            url: url,
            statusCode: data == nil ? 404 : 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json; charset=utf-8"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        if let data { client?.urlProtocol(self, didLoad: data) }
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
