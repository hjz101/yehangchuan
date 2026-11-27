import Foundation

/// OpenAI 兼容的 /chat/completions 客户端。配置由用户自带，不内置任何 Key。
public struct AIConfiguration: Sendable {
    /// 兼容服务的根地址，例如 https://api.example.com/v1
    public var baseURL: URL
    public var apiKey: String
    public var model: String

    public init(baseURL: URL, apiKey: String, model: String) {
        self.baseURL = baseURL
        self.apiKey = apiKey
        self.model = model
    }
}

public enum AIServiceError: Error, LocalizedError, Sendable {
    case invalidEndpoint
    case badResponse(Int)
    case missingContent

    public var errorDescription: String? {
        switch self {
        case .invalidEndpoint: "AI 服务地址无效，请填写包含 http(s) 的完整地址"
        case .badResponse(let code): "AI 服务返回错误（HTTP \(code)）"
        case .missingContent: "AI 服务没有返回可读取的文本内容"
        }
    }
}

/// 真实发出 HTTP 请求，不走 MockBackend。私网地址由 HTTPTransport 里的
/// PrivateHostGate 统一拦截，本地服务需用户显式放行。
public struct AIService: Sendable {
    private let transport: any HTTPTransport

    public init(transport: any HTTPTransport = URLSessionHTTPTransport()) {
        self.transport = transport
    }

    public func chat(_ prompt: String, configuration: AIConfiguration) async throws -> String {
        guard ["http", "https"].contains(configuration.baseURL.scheme?.lowercased() ?? "") else {
            throw AIServiceError.invalidEndpoint
        }
        let endpoint = configuration.baseURL.appendingPathComponent("chat/completions")
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("Bearer \(configuration.apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = [
            "model": configuration.model,
            "messages": [["role": "user", "content": prompt]],
            "temperature": 0.7
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let response = try await transport.data(for: request)
        guard (200..<300).contains(response.statusCode) else {
            throw AIServiceError.badResponse(response.statusCode)
        }
        guard let json = response.decodedJSON,
              let content = json["choices"]?[0]?["message"]?["content"]?.stringValue,
              !content.isEmpty else {
            throw AIServiceError.missingContent
        }
        return content
    }
}
