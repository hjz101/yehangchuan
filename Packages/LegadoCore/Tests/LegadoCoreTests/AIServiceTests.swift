import Foundation
import XCTest
@testable import LegadoCore

final class AIServiceTests: XCTestCase {
    /// 测试里每次只发一次请求，无需加锁；@unchecked 只为满足 HTTPTransport: Sendable。
    private final class RecordingTransport: HTTPTransport, @unchecked Sendable {
        private(set) var request: URLRequest?
        private let response: HTTPResponse

        init(_ response: HTTPResponse) { self.response = response }

        func data(for request: URLRequest) async throws -> HTTPResponse {
            self.request = request
            return response
        }
    }

    private func response(status: Int, json: String) -> HTTPResponse {
        HTTPResponse(
            data: Data(json.utf8), statusCode: status,
            headers: ["Content-Type": "application/json"],
            finalURL: URL(string: "https://api.example.com/v1/chat/completions")!
        )
    }

    func testChatSendsRealRequestAndParsesContent() async throws {
        let transport = RecordingTransport(response(status: 200, json: #"{"choices":[{"message":{"content":"这是一段真实摘要"}}]}"#))
        let service = AIService(transport: transport)
        let configuration = AIConfiguration(
            baseURL: URL(string: "https://api.example.com/v1")!,
            apiKey: "sk-test", model: "demo-model"
        )

        let result = try await service.chat("请摘要", configuration: configuration)
        XCTAssertEqual(result, "这是一段真实摘要")

        let request = try XCTUnwrap(transport.request)
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.url?.absoluteString, "https://api.example.com/v1/chat/completions")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer sk-test")
        let body = try JSONDecoder().decode(JSONValue.self, from: XCTUnwrap(request.httpBody))
        XCTAssertEqual(body["model"]?.stringValue, "demo-model")
        XCTAssertEqual(body["messages"]?[0]?["content"]?.stringValue, "请摘要")
    }

    func testBadStatusAndMissingContent() async throws {
        let configuration = AIConfiguration(
            baseURL: URL(string: "https://api.example.com/v1")!, apiKey: "k", model: "m"
        )
        do {
            _ = try await AIService(transport: RecordingTransport(response(status: 503, json: "{}")))
                .chat("x", configuration: configuration)
            XCTFail("expected badResponse")
        } catch let error as AIServiceError {
            guard case .badResponse(503) = error else { return XCTFail("got \(error)") }
        }

        do {
            _ = try await AIService(transport: RecordingTransport(response(status: 200, json: #"{"choices":[]}"#)))
                .chat("x", configuration: configuration)
            XCTFail("expected missingContent")
        } catch let error as AIServiceError {
            guard case .missingContent = error else { return XCTFail("got \(error)") }
        }
    }

    func testRejectsNonHTTPEndpoint() async throws {
        do {
            _ = try await AIService(transport: RecordingTransport(response(status: 200, json: "{}")))
                .chat("x", configuration: .init(
                    baseURL: URL(string: "ftp://example.com")!, apiKey: "k", model: "m"
                ))
            XCTFail("expected invalidEndpoint")
        } catch let error as AIServiceError {
            guard case .invalidEndpoint = error else { return XCTFail("got \(error)") }
        }
    }
}
