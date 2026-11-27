import Foundation
import XCTest
@testable import LegadoCore

/// 凭据迁移的核心保证：SQLite 始终是权威副本、绝不删除；Keychain 是双写的
/// 第二份，任一步出问题都能切回 `.sqlite` 完全回到迁移前行为。
final class CredentialMigrationTests: XCTestCase {
    private var root: URL!
    private var settings: CredentialSettings!
    private var keychain: InMemoryKeychainStore!
    private var storage: PersistentRuntimeCache!

    override func setUpWithError() throws {
        try super.setUpWithError()
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("yh-cred-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        keychain = InMemoryKeychainStore()
        settings = CredentialSettings()
        settings.configure(backend: .dualWrite, keychain: keychain)
        let db = root.appendingPathComponent("legado.sqlite3")
        storage = PersistentRuntimeCache(url: db, settings: settings)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
        try super.tearDownWithError()
    }

    /// 双写：put 之后两边都能读到同一个值。
    func testPutMirrorsToKeychain() throws {
        storage.put("v_src_loginInfo", value: "{\"token\":\"abc\"}")
        XCTAssertEqual(storage.get("v_src_loginInfo"), "{\"token\":\"abc\"}")
        XCTAssertEqual(keychain.read("cache:v_src_loginInfo"), "{\"token\":\"abc\"}")
    }

    /// 回滚开关：切回 .sqlite 后，读只认 SQLite，Keychain 不再被写。
    func testRollbackToSQLiteIgnoresKeychain() throws {
        storage.put("loginHeader_src", value: "旧值")
        keychain.write("cache:loginHeader_src", "新值（Keychain 被篡改）")

        settings.backend = .sqlite
        XCTAssertEqual(storage.get("loginHeader_src"), "旧值", "回滚后应只读 SQLite")

        storage.put("loginHeader_src", value: "回滚后写入")
        XCTAssertEqual(keychain.read("cache:loginHeader_src"), "新值（Keychain 被篡改）", "回滚后不应再写 Keychain")
    }

    /// keychainPreferred：以 Keychain 为权威，SQLite 仍是后盾且不被删除。
    func testKeychainPreferredReadsKeychainFirst() throws {
        storage.put("loginHeader_src", value: "SQLite 值")
        keychain.write("cache:loginHeader_src", "Keychain 新值")

        settings.backend = .keychainPreferred
        XCTAssertEqual(storage.get("loginHeader_src"), "Keychain 新值")
        XCTAssertEqual(storage.get("loginHeader_src"), "Keychain 新值")
    }

    /// 重装场景：SQLite 被清、Keychain 保留时，读应回填 SQLite。
    func testKeychainOnlyValueBackfillsSQLite() throws {
        keychain.write("cache:loginHeader_src", "仅存于钥匙串")

        XCTAssertEqual(storage.get("loginHeader_src"), "仅存于钥匙串")
        XCTAssertEqual(storage.get("loginHeader_src"), "仅存于钥匙串")
    }

    /// 带 deadline 的临时缓存不进 Keychain。
    func testExpiringCacheIsNotMirrored() throws {
        storage.put("temp_key", value: "短命", deadline: 1)
        XCTAssertNil(keychain.read("cache:temp_key"))
    }

    /// Cookie 双写与删除都同步到 Keychain，且用独立命名空间。
    func testCookieDualWriteAndDelete() throws {
        storage.putCookie(key: "example.com", value: "a=1")
        XCTAssertEqual(storage.cookie(for: "example.com"), "a=1")
        XCTAssertEqual(keychain.read("cookie:example.com"), "a=1")
        XCTAssertNil(keychain.read("cache:example.com"), "cookie 不应占用 cache 命名空间")

        storage.deleteCookie(key: "example.com")
        XCTAssertNil(storage.cookie(for: "example.com"))
        XCTAssertNil(keychain.read("cookie:example.com"))
    }

    /// 对账：正常双写后应干净；篡改 Keychain 后应报 mismatch，缺失应报 missing。
    func testReconcileDetectsMissingAndMismatch() throws {
        storage.put("loginHeader_src", value: "正确值")
        XCTAssertTrue(storage.reconcile().isClean)

        let mismatch = CredentialSettings()
        mismatch.configure(backend: .dualWrite, keychain: keychain)
        keychain.write("cache:loginHeader_src", "被改过")
        XCTAssertEqual(storage.reconcile().mismatch, ["loginHeader_src"])

        keychain.delete("cache:loginHeader_src")
        XCTAssertEqual(storage.reconcile().missing, ["loginHeader_src"])
    }

    /// 回填：对账发现缺失后，显式回填修复，不删除任何 SQLite 数据。
    func testBackfillRepairsKeychainWithoutTouchingSQLite() throws {
        storage.put("loginHeader_src", value: "凭据")
        let before = storage.get("loginHeader_src")
        keychain.delete("cache:loginHeader_src")

        storage.backfillKeychain()
        XCTAssertTrue(storage.reconcile().isClean)
        XCTAssertEqual(storage.get("loginHeader_src"), before)
    }
}
