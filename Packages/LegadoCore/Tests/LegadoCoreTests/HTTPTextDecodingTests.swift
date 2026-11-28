import Foundation
import XCTest
@testable import LegadoCore

final class HTTPTextDecodingTests: XCTestCase {
    private let text = "中文测试：夜航船"

    private func response(_ data: Data, charset: String? = nil, contentType: String? = nil) -> HTTPResponse {
        var headers: [String: String] = [:]
        if let contentType { headers["Content-Type"] = contentType }
        return HTTPResponse(
            data: data,
            statusCode: 200,
            headers: headers,
            finalURL: URL(string: "https://example.com/book")!,
            requestedCharset: charset
        )
    }

    func testUTF16LittleEndianWithBOM() {
        let data = Data([0xFF, 0xFE]) + text.data(using: .utf16LittleEndian)!
        XCTAssertEqual(response(data, charset: "utf-16").decodedText, text)
    }

    func testUTF16BigEndianWithBOM() {
        let data = Data([0xFE, 0xFF]) + text.data(using: .utf16BigEndian)!
        XCTAssertEqual(response(data, charset: "utf-16").decodedText, text)
    }

    func testUTF16WithoutBOMDefaultsToBigEndian() {
        let data = text.data(using: .utf16BigEndian)!
        XCTAssertEqual(response(data, charset: "utf-16").decodedText, text)
    }

    func testUTF8WithBOM() {
        let data = Data([0xEF, 0xBB, 0xBF]) + text.data(using: .utf8)!
        XCTAssertEqual(response(data, contentType: "text/html; charset=utf-8").decodedText, text)
    }
}
