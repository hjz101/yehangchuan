import Foundation
import XCTest
@testable import LegadoCore

final class HttpTTSServiceTests: XCTestCase {
    private final class TextTransport: HTTPTransport, @unchecked Sendable {
        private let lock = NSLock()
        private var stored = 0

        var calls: Int { lock.withLock { stored } }

        func data(for request: URLRequest) async throws -> HTTPResponse {
            lock.withLock { stored += 1 }
            return HTTPResponse(
                data: Data("登录已失效".utf8),
                statusCode: 200,
                headers: ["Content-Type": "text/plain; charset=utf-8"],
                finalURL: request.url!
            )
        }
    }

    func testTextResponseIsNotRetried() async throws {
        let transport = TextTransport()
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("yh-tts-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let service = HttpTTSService(
            transport: transport,
            cache: HttpTTSAudioCache(directory: directory)
        )
        let engine = HttpTTS(name: "测试", url: "https://example.com/tts?text={{speakText}}")

        do {
            _ = try await service.audio(engine: engine, text: "你好", speechRate: 0)
            XCTFail("文本响应应立即抛出")
        } catch HttpTTSServiceError.textResponse {
            // 期望的确定性错误
        } catch {
            XCTFail("期望 textResponse，实际为 \(error)")
        }
        XCTAssertEqual(transport.calls, 1)
    }
}
