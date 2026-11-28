import Foundation
import XCTest
@testable import LegadoCore

final class HttpTTSAudioTests: XCTestCase {
    func testSuggestedFileExtensionUsesResponseContentType() {
        let audio = HttpTTSAudio(
            data: Data([0x01]),
            contentType: "audio/mpeg; charset=binary",
            finalURL: URL(string: "https://example.com/speak")!
        )

        XCTAssertEqual(audio.suggestedFileExtension, "mp3")
    }

    func testSuggestedFileExtensionFallsBackToURLExtension() {
        let audio = HttpTTSAudio(
            data: Data([0x01]),
            contentType: nil,
            finalURL: URL(string: "https://example.com/speak.m4a")!
        )

        XCTAssertEqual(audio.suggestedFileExtension, "m4a")
    }
}
