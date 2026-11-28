import Foundation
import XCTest
@testable import LegadoCore

final class CookieHandlingTests: XCTestCase {
    private var root: URL!
    private var store: LegadoCookieStore!
    private var persistent: PersistentRuntimeCache!
    private let host = "cookie-\(UUID().uuidString.lowercased()).example.com"

    override func setUpWithError() throws {
        try super.setUpWithError()
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("yh-cookie-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let settings = CredentialSettings()
        settings.configure(backend: .sqlite, keychain: InMemoryKeychainStore())
        persistent = PersistentRuntimeCache(url: root.appendingPathComponent("legado.sqlite3"), settings: settings)
        store = LegadoCookieStore(storage: .shared, persistent: persistent)
    }

    override func tearDownWithError() throws {
        store.removeCookies(for: "https://\(host)")
        try? FileManager.default.removeItem(at: root)
        try super.tearDownWithError()
    }

    func testSplitKeepsExpiresDateComma() {
        let header = "a=1; Path=/; Expires=Wed, 21 Oct 2015 07:28:00 GMT, b=2; Path=/; HttpOnly"
        let entries = SetCookieHeaderParser.split(header)
        XCTAssertEqual(entries.count, 2)
        XCTAssertTrue(entries[1].hasPrefix("b=2"))
    }

    func testDeletionDetection() {
        XCTAssertTrue(SetCookieHeaderParser.isDeletion("gone=; Max-Age=0; Path=/"))
        XCTAssertTrue(SetCookieHeaderParser.isDeletion("gone=1; Max-Age=0"))
        XCTAssertTrue(SetCookieHeaderParser.isDeletion("gone=1; Expires=Wed, 21 Oct 2015 07:28:00 GMT"))
        XCTAssertTrue(SetCookieHeaderParser.isDeletion("empty=; Path=/"))
        XCTAssertFalse(SetCookieHeaderParser.isDeletion("keep=1; Path=/; Max-Age=3600"))
    }

    func testSetCookieKeepsEveryCookieInHeader() {
        store.setCookie("a=1; Path=/, b=2; Path=/", for: "https://\(host)")
        let header = store.cookieHeader(for: "https://\(host)")
        XCTAssertTrue(header.contains("a=1"))
        XCTAssertTrue(header.contains("b=2"))
        let saved = persistent.cookie(for: LegadoCookieStore.persistenceDomain(for: host)) ?? ""
        XCTAssertTrue(saved.contains("a=1"))
        XCTAssertTrue(saved.contains("b=2"))
    }

    func testDeletionCookieRemovesPersistedCookie() {
        store.setCookie("a=1; Path=/, b=2; Path=/", for: "https://\(host)")
        store.setCookie("a=; Max-Age=0; Path=/", for: "https://\(host)")
        let header = store.cookieHeader(for: "https://\(host)")
        XCTAssertFalse(header.contains("a=1"))
        XCTAssertTrue(header.contains("b=2"))
        let saved = persistent.cookie(for: LegadoCookieStore.persistenceDomain(for: host)) ?? ""
        XCTAssertFalse(saved.contains("a=1"))
        XCTAssertTrue(saved.contains("b=2"))
    }
}
