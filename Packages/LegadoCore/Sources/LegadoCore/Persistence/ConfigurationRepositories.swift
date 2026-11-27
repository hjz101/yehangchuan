import Foundation
import SQLite3

public struct SearchKeyword: Codable, Hashable, Identifiable, Sendable {
    public var word: String
    public var usage: Int
    public var lastUseTime: Int64
    public var id: String { word }

    public init(word: String, usage: Int = 1, lastUseTime: Int64? = nil) {
        self.word = word
        self.usage = usage
        self.lastUseTime = lastUseTime ?? Int64(Date().timeIntervalSince1970 * 1_000)
    }
}

public struct LegadoCache: Codable, Hashable, Identifiable, Sendable {
    public var key: String
    public var value: String?
    public var deadline: Int64
    public var id: String { key }

    public init(key: String, value: String? = nil, deadline: Int64 = 0) {
        self.key = key
        self.value = value
        self.deadline = deadline
    }
}

public struct LegadoCookie: Codable, Hashable, Identifiable, Sendable {
    public var url: String
    public var cookie: String
    public var id: String { url }

    public init(url: String, cookie: String = "") {
        self.url = url
        self.cookie = cookie
    }
}

public struct TxtTocRule: Codable, Hashable, Identifiable, Sendable {
    public var id: Int64
    public var name: String
    public var rule: String
    public var replacement: String
    public var example: String?
    public var serialNumber: Int
    public var enable: Bool
    public init(
        id: Int64 = Int64(Date().timeIntervalSince1970 * 1_000),
        name: String = "",
        rule: String = "",
        replacement: String = "",
        example: String? = nil,
        serialNumber: Int = -1,
        enable: Bool = true
    ) {
        self.id = id; self.name = name; self.rule = rule; self.replacement = replacement
        self.example = example; self.serialNumber = serialNumber; self.enable = enable
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, rule, replacement, example, serialNumber, enable
    }

    public init(from decoder: Decoder) throws {
        let value = try decoder.container(keyedBy: CodingKeys.self)
        id = try value.decodeIfPresent(Int64.self, forKey: .id) ?? Int64(Date().timeIntervalSince1970 * 1_000)
        name = try value.decodeIfPresent(String.self, forKey: .name) ?? ""
        rule = try value.decodeIfPresent(String.self, forKey: .rule) ?? ""
        replacement = try value.decodeIfPresent(String.self, forKey: .replacement) ?? ""
        example = try value.decodeIfPresent(String.self, forKey: .example)
        serialNumber = try value.decodeIfPresent(Int.self, forKey: .serialNumber) ?? -1
        enable = try value.decodeIfPresent(Bool.self, forKey: .enable) ?? true
    }
}

public struct HttpTTS: Codable, Hashable, Identifiable, Sendable {
    public var id: Int64
    public var name: String
    public var url: String
    public var contentType: String?
    public var concurrentRate: String?
    public var loginUrl: String?
    public var loginUi: String?
    public var header: String?
    public var jsLib: String?
    public var enabledCookieJar: Bool?
    public var loginCheckJs: String?
    public var lastUpdateTime: Int64
    public init(id: Int64 = Int64(Date().timeIntervalSince1970 * 1_000), name: String = "", url: String = "") {
        self.id = id; self.name = name; self.url = url; contentType = nil; concurrentRate = "0"
        loginUrl = nil; loginUi = nil; header = nil; jsLib = nil; enabledCookieJar = false
        loginCheckJs = nil; lastUpdateTime = id
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let now = Int64(Date().timeIntervalSince1970 * 1_000)
        id = (try? values.decode(Int64.self, forKey: .id))
            ?? Int64((try? values.decode(String.self, forKey: .id)) ?? "")
            ?? now
        name = try values.decodeIfPresent(String.self, forKey: .name) ?? ""
        url = try values.decodeIfPresent(String.self, forKey: .url) ?? ""
        contentType = try values.decodeIfPresent(String.self, forKey: .contentType)
        concurrentRate = try values.decodeIfPresent(String.self, forKey: .concurrentRate)
        loginUrl = try values.decodeIfPresent(String.self, forKey: .loginUrl)
        if let text = try? values.decodeIfPresent(String.self, forKey: .loginUi) {
            loginUi = text
        } else if let json = try? values.decodeIfPresent(JSONValue.self, forKey: .loginUi) {
            loginUi = (try? JSONEncoder().encode(json)).flatMap { String(data: $0, encoding: .utf8) }
        } else {
            loginUi = nil
        }
        header = try values.decodeIfPresent(String.self, forKey: .header)
        jsLib = try values.decodeIfPresent(String.self, forKey: .jsLib)
        enabledCookieJar = try values.decodeIfPresent(Bool.self, forKey: .enabledCookieJar) ?? false
        loginCheckJs = try values.decodeIfPresent(String.self, forKey: .loginCheckJs)
        lastUpdateTime = (try? values.decode(Int64.self, forKey: .lastUpdateTime))
            ?? Int64((try? values.decode(String.self, forKey: .lastUpdateTime)) ?? "")
            ?? now
    }
}

public struct RuleSub: Codable, Hashable, Identifiable, Sendable {
    public var id: Int64
    public var name: String
    public var url: String
    public var type: Int
    public var customOrder: Int
    public var autoUpdate: Bool
    public var update: Int64
    public var updateInterval: Int
    public var silentUpdate: Bool
    public var js: String?
    public var showRule: String?
    public var sourceUrl: String?
    public init(id: Int64 = Int64(Date().timeIntervalSince1970 * 1_000), name: String = "", url: String = "") {
        self.id = id; self.name = name; self.url = url; type = 0; customOrder = 0
        autoUpdate = false; update = id; updateInterval = 0; silentUpdate = false
        js = nil; showRule = nil; sourceUrl = nil
    }
}

public struct KeyboardAssist: Codable, Hashable, Identifiable, Sendable {
    public var type: Int
    public var key: String
    public var value: String
    public var serialNo: Int
    public var id: String { "\(type)\u{0}\(key)" }
    public init(type: Int = 0, key: String, value: String, serialNo: Int = 0) {
        self.type = type; self.key = key; self.value = value; self.serialNo = serialNo
    }
}

public struct Server: Codable, Hashable, Identifiable, Sendable {
    public enum ServerType: String, Codable, Sendable { case webDAV = "WEBDAV" }
    public struct WebDAVConfig: Codable, Hashable, Sendable {
        public var url: String
        public var username: String
        public var password: String
        public init(url: String, username: String, password: String) {
            self.url = url; self.username = username; self.password = password
        }
    }
    public var id: Int64
    public var name: String
    public var type: ServerType
    public var config: String?
    public var sortNumber: Int
    public init(id: Int64 = Int64(Date().timeIntervalSince1970 * 1_000), name: String = "", type: ServerType = .webDAV) {
        self.id = id; self.name = name; self.type = type; config = nil; sortNumber = 0
    }
    public var webDAVConfig: WebDAVConfig? {
        guard type == .webDAV, let config else { return nil }
        return try? JSONDecoder().decode(WebDAVConfig.self, from: Data(config.utf8))
    }
}

public enum SearchKeywordOrder: Sendable { case usage, lastUseTime }

public protocol SearchKeywordRepository: Sendable {
    func load(order: SearchKeywordOrder) async throws -> [SearchKeyword]
    @discardableResult func record(_ word: String, at time: Int64) async throws -> SearchKeyword
    func delete(_ word: String) async throws
    func deleteAll() async throws
}

public actor SQLiteSearchKeywordRepository: SearchKeywordRepository {
    private let database: LegadoDatabase
    private let legacyWords: [String]
    private var migratedLegacy = false

    public init(database: LegadoDatabase, legacyWords: [String] = []) {
        self.database = database
        self.legacyWords = legacyWords
    }

    public func load(order: SearchKeywordOrder) async throws -> [SearchKeyword] {
        try await migrateLegacyIfNeeded()
        return try await database.loadSearchKeywords(order: order)
    }

    public func record(_ word: String, at time: Int64) async throws -> SearchKeyword {
        try await migrateLegacyIfNeeded()
        return try await database.recordSearchKeyword(word, at: time)
    }

    public func delete(_ word: String) async throws { try await database.deleteSearchKeyword(word) }
    public func deleteAll() async throws { try await database.deleteAllSearchKeywords() }

    private func migrateLegacyIfNeeded() async throws {
        guard !migratedLegacy else { return }
        migratedLegacy = true
        try await database.importLegacySearchKeywords(legacyWords)
    }
}

public actor InMemorySearchKeywordRepository: SearchKeywordRepository {
    private var values: [String: SearchKeyword]
    public init(values: [SearchKeyword] = []) {
        self.values = Dictionary(uniqueKeysWithValues: values.map { ($0.word, $0) })
    }
    public func load(order: SearchKeywordOrder) -> [SearchKeyword] {
        values.values.sorted {
            switch order {
            case .usage:
                $0.usage == $1.usage ? $0.lastUseTime > $1.lastUseTime : $0.usage > $1.usage
            case .lastUseTime:
                $0.lastUseTime == $1.lastUseTime ? $0.usage > $1.usage : $0.lastUseTime > $1.lastUseTime
            }
        }
    }
    public func record(_ word: String, at time: Int64) -> SearchKeyword {
        var value = values[word] ?? .init(word: word, usage: 0, lastUseTime: time)
        value.usage += 1
        value.lastUseTime = time
        values[word] = value
        return value
    }
    public func delete(_ word: String) { values[word] = nil }
    public func deleteAll() { values.removeAll() }
}

public protocol LegadoCacheRepository: Sendable {
    func value(for key: String, now: Int64) async throws -> String?
    func put(_ cache: LegadoCache) async throws
    func delete(_ key: String) async throws
    func deleteSourceVariables(_ sourceKey: String) async throws
    func clearExpired(now: Int64) async throws
}

public actor SQLiteLegadoCacheRepository: LegadoCacheRepository {
    private let database: LegadoDatabase
    public init(database: LegadoDatabase) { self.database = database }
    public func value(for key: String, now: Int64) async throws -> String? {
        try await database.cacheValue(for: key, now: now)
    }
    public func put(_ cache: LegadoCache) async throws { try await database.putCache(cache) }
    public func delete(_ key: String) async throws { try await database.deleteCache(key) }
    public func deleteSourceVariables(_ sourceKey: String) async throws {
        try await database.deleteSourceVariables(sourceKey)
    }
    public func clearExpired(now: Int64) async throws { try await database.clearExpiredCaches(now: now) }
}

public protocol LegadoCookieRepository: Sendable {
    func get(_ url: String) async throws -> LegadoCookie?
    func getOkHTTP() async throws -> [LegadoCookie]
    func put(_ cookie: LegadoCookie) async throws
    func delete(_ url: String) async throws
    func deleteOkHTTP() async throws
}

public protocol SearchBookRepository: Sendable {
    func cachedMatches(keyword: String) async throws -> [SearchBook]
    func get(bookURL: String) async throws -> SearchBook?
    func first(name: String, author: String) async throws -> SearchBook?
    func changeSources(name: String, author: String, sourceGroup: String, key: String?) async throws -> [SearchBook]
    func enabledWithCover(name: String, author: String) async throws -> [SearchBook]
    func put(_ books: [SearchBook]) async throws
    func clear(name: String, author: String) async throws
    func clearExpired(before time: Int64) async throws
}

extension SearchBookRepository {
    public func cachedMatches(keyword: String) async throws -> [SearchBook] {
        try await changeSources(name: keyword, author: "", sourceGroup: "", key: nil)
    }
}

public protocol ConfigurationRepository: Sendable {
    func loadTxtTocRules() async throws -> [TxtTocRule]
    func saveTxtTocRules(_ values: [TxtTocRule]) async throws
    func loadHttpTTS() async throws -> [HttpTTS]
    func saveHttpTTS(_ values: [HttpTTS]) async throws
    func loadRuleSubs() async throws -> [RuleSub]
    func saveRuleSubs(_ values: [RuleSub]) async throws
    func loadKeyboardAssists() async throws -> [KeyboardAssist]
    func saveKeyboardAssists(_ values: [KeyboardAssist]) async throws
    func loadServers() async throws -> [Server]
    func saveServers(_ values: [Server]) async throws
}

public actor SQLiteConfigurationRepository: ConfigurationRepository {
    private let database: LegadoDatabase
    public init(database: LegadoDatabase) { self.database = database }
    public func loadTxtTocRules() async throws -> [TxtTocRule] { try await database.loadTxtTocRules() }
    public func loadTxtTocRules(initialDefaults: [TxtTocRule]) async throws -> [TxtTocRule] {
        try await database.loadTxtTocRules(initialDefaults: initialDefaults)
    }
    public func saveTxtTocRules(_ values: [TxtTocRule]) async throws { try await database.replaceTxtTocRules(values) }
    public func loadHttpTTS() async throws -> [HttpTTS] { try await database.loadHttpTTS() }
    public func saveHttpTTS(_ values: [HttpTTS]) async throws { try await database.replaceHttpTTS(values) }
    public func loadRuleSubs() async throws -> [RuleSub] { try await database.loadRuleSubs() }
    public func saveRuleSubs(_ values: [RuleSub]) async throws { try await database.replaceRuleSubs(values) }
    public func loadKeyboardAssists() async throws -> [KeyboardAssist] { try await database.loadKeyboardAssists() }
    public func saveKeyboardAssists(_ values: [KeyboardAssist]) async throws { try await database.replaceKeyboardAssists(values) }
    public func loadServers() async throws -> [Server] { try await database.loadServers() }
    public func saveServers(_ values: [Server]) async throws { try await database.replaceServers(values) }
}

public actor SQLiteSearchBookRepository: SearchBookRepository {
    private let database: LegadoDatabase
    public init(database: LegadoDatabase) { self.database = database }

    public func cachedMatches(keyword: String) async throws -> [SearchBook] {
        try await database.cachedSearchMatches(keyword: keyword)
    }

    public func get(bookURL: String) async throws -> SearchBook? {
        let books = try await database.loadSearchBooks()
        return books.first { $0.bookURL == bookURL }
    }

    public func first(name: String, author: String) async throws -> SearchBook? {
        let books = try await database.loadSearchBooks()
        let sources = try await database.loadBookSources()
        let sourceIDs = Set(sources.map(\.bookSourceUrl))
        return books
            .filter { $0.name == name && $0.author == author }
            .filter { sourceIDs.contains($0.origin) }
            .sorted { $0.originOrder < $1.originOrder }
            .first
    }

    public func changeSources(
        name: String,
        author: String,
        sourceGroup: String,
        key: String?
    ) async throws -> [SearchBook] {
        let sources = try await database.loadBookSources()
        let sourceMap = Dictionary(uniqueKeysWithValues: sources.map { ($0.bookSourceUrl, $0) })
        let books = try await database.loadSearchBooks()
        return books.compactMap { book in
            guard book.name == name,
                  book.author.localizedCaseInsensitiveContains(author),
                  let source = sourceMap[book.origin], source.enabled,
                  sourceGroup.isEmpty || (source.bookSourceGroup ?? "").contains(sourceGroup) else { return nil }
            if let key, !key.isEmpty,
               !book.originName.localizedCaseInsensitiveContains(key),
               !(book.latestChapterTitle ?? "").localizedCaseInsensitiveContains(key) { return nil }
            var value = book
            value.originOrder = source.customOrder
            return value
        }.sorted { $0.originOrder < $1.originOrder }
    }

    public func enabledWithCover(name: String, author: String) async throws -> [SearchBook] {
        let sources = try await database.loadBookSources()
        let sourceMap = Dictionary(uniqueKeysWithValues: sources.map { ($0.bookSourceUrl, $0) })
        let books = try await database.loadSearchBooks()
        return books.compactMap { book in
            guard book.name == name, book.author == author,
                  !(book.coverURL ?? "").isEmpty,
                  let source = sourceMap[book.origin], source.enabled else { return nil }
            var value = book
            value.originOrder = source.customOrder
            return value
        }.sorted { $0.originOrder < $1.originOrder }
    }

    public func put(_ books: [SearchBook]) async throws { try await database.putSearchBooks(books) }
    public func clear(name: String, author: String) async throws {
        try await database.deleteSearchBooks(name: name, author: author)
    }
    public func clearExpired(before time: Int64) async throws {
        try await database.clearExpiredSearchBooks(before: time)
    }
}

public actor SQLiteLegadoCookieRepository: LegadoCookieRepository {
    private let database: LegadoDatabase
    public init(database: LegadoDatabase) { self.database = database }
    public func get(_ url: String) async throws -> LegadoCookie? { try await database.cookie(for: url) }
    public func getOkHTTP() async throws -> [LegadoCookie] { try await database.loadOkHTTPCookies() }
    public func put(_ cookie: LegadoCookie) async throws { try await database.putCookie(cookie) }
    public func delete(_ url: String) async throws { try await database.deleteCookie(url) }
    public func deleteOkHTTP() async throws { try await database.deleteOkHTTPCookies() }
}

public enum SearchKeywordRepositoryFactory {
    public static func live(defaults: UserDefaults = .standard) -> any SearchKeywordRepository {
        guard let database = try? LegadoDatabase(url: LegadoDatabase.defaultURL()) else {
            return InMemorySearchKeywordRepository()
        }
        return SQLiteSearchKeywordRepository(
            database: database,
            legacyWords: defaults.stringArray(forKey: "bookSearchHistory") ?? []
        )
    }
}

public enum SearchBookRepositoryFactory {
    public static func live() -> any SearchBookRepository {
        guard let database = try? LegadoDatabase(url: LegadoDatabase.defaultURL()) else {
            return InMemorySearchBookRepository()
        }
        return SQLiteSearchBookRepository(database: database)
    }
}

public final class PersistentRuntimeCache: @unchecked Sendable {
    public static let shared = PersistentRuntimeCache()
    private let lock = NSLock()
    private var handle: OpaquePointer?
    private let settings: CredentialSettings

    /// Keychain 账号命名空间：缓存与 Cookie 分开放，避免同名键互相覆盖。
    private static let cacheNamespace = "cache:"
    private static let cookieNamespace = "cookie:"

    public init(url: URL = LegadoDatabase.defaultURL(), settings: CredentialSettings = .shared) {
        self.settings = settings
        let migrator = try? LegadoDatabase(url: url)
        _ = migrator
        sqlite3_open_v2(
            url.path,
            &handle,
            SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX,
            nil
        )
        if let handle { sqlite3_busy_timeout(handle, 5_000) }
    }

    deinit { if let handle { sqlite3_close(handle) } }

    // MARK: - 缓存读写

    public func get(_ key: String, now: Int64 = Int64(Date().timeIntervalSince1970 * 1_000)) -> String? {
        let backend = settings.backend
        let keychain = settings.keychain
        let account = Self.cacheNamespace + key

        if backend == .keychainPreferred, let value = keychain.read(account) {
            return value
        }

        lock.lock()
        let fromSQLite = Self.readValue(handle, "SELECT value FROM caches WHERE `key` = ? AND (deadline = 0 OR deadline > ?)", key, now)
        lock.unlock()

        if let value = fromSQLite {
            // 历史数据的补齐走显式 backfillKeychain()，不在每次读时都写钥匙串。
            return value
        }
        // SQLite 没有，Keychain 有：重装后本地库被清、钥匙串保留的场景。
        // 回填 SQLite，让这条链路始终以 SQLite 为权威副本。
        if backend != .sqlite, let value = keychain.read(account) {
            put(key, value: value)
            return value
        }
        return nil
    }

    public func put(_ key: String, value: String, deadline: Int64 = 0) {
        lock.lock()
        let wrote = Self.writeValue(
            handle,
            """
            INSERT INTO caches(`key`, value, deadline) VALUES(?, ?, ?)
            ON CONFLICT(`key`) DO UPDATE SET value = excluded.value, deadline = excluded.deadline
            """,
            key, value, deadline
        )
        lock.unlock()

        guard wrote else { return }
        let backend = settings.backend
        guard backend != .sqlite else { return }
        let account = Self.cacheNamespace + key
        // 只有永不过期的条目才是凭据（loginHeader / loginInfo / JS 变量）；
        // 带 deadline 的临时缓存不该进钥匙串。若之前镜像过又改成临时，删掉旧副本。
        if deadline == 0 {
            settings.keychain.write(account, value)
        } else {
            settings.keychain.delete(account)
        }
    }

    // MARK: - Cookie 读写

    public func cookie(for key: String) -> String? {
        let backend = settings.backend
        let keychain = settings.keychain
        let account = Self.cookieNamespace + key

        if backend == .keychainPreferred, let value = keychain.read(account) {
            return value
        }

        lock.lock()
        let fromSQLite = Self.readValue(handle, "SELECT cookie FROM cookies WHERE url = ?", key)
        lock.unlock()

        if let value = fromSQLite { return value }
        if backend != .sqlite, let value = keychain.read(account) {
            putCookie(key: key, value: value)
            return value
        }
        return nil
    }

    public func putCookie(key: String, value: String) {
        lock.lock()
        let wrote = Self.writeValue(
            handle,
            "INSERT INTO cookies(url, cookie) VALUES(?, ?) ON CONFLICT(url) DO UPDATE SET cookie = excluded.cookie",
            key, value
        )
        lock.unlock()

        guard wrote, settings.backend != .sqlite else { return }
        settings.keychain.write(Self.cookieNamespace + key, value)
    }

    public func deleteCookie(key: String) {
        lock.lock()
        Self.executeBound(handle, "DELETE FROM cookies WHERE url = ?", text: key)
        lock.unlock()
        if settings.backend != .sqlite {
            settings.keychain.delete(Self.cookieNamespace + key)
        }
    }

    // MARK: - 对账 / 枚举（供迁移验证使用）

    /// 把所有永久缓存键读出来（不含带 deadline 的临时项），供对账与回填。
    public func allCredentialCacheKeys() -> [String] {
        lock.lock()
        defer { lock.unlock() }
        return Self.column(handle, "SELECT `key` FROM caches WHERE deadline = 0")
    }

    public func allCookieKeys() -> [String] {
        lock.lock()
        defer { lock.unlock() }
        return Self.column(handle, "SELECT url FROM cookies")
    }

    /// 逐键比对 SQLite 与 Keychain，产出对账报告。只读，不修改任何一边。
    public func reconcile() -> CredentialReconciliation {
        let keychain = settings.keychain
        var report = CredentialReconciliation()
        for key in allCredentialCacheKeys() {
            guard let sqlite = sqliteCacheValue(key) else { continue }
            report.checked += 1
            compare(sqlite, keychain: keychain, account: Self.cacheNamespace + key, key: key, into: &report)
        }
        for key in allCookieKeys() {
            guard let sqlite = sqliteCookieValue(key) else { continue }
            report.checked += 1
            compare(sqlite, keychain: keychain, account: Self.cookieNamespace + key, key: key, into: &report)
        }
        return report
    }

    /// 把当前 SQLite 里的全部凭据强制回填到 Keychain（对账通过后调用）。
    public func backfillKeychain() {
        guard settings.backend != .sqlite else { return }
        let keychain = settings.keychain
        for key in allCredentialCacheKeys() {
            if let value = sqliteCacheValue(key) { keychain.write(Self.cacheNamespace + key, value) }
        }
        for key in allCookieKeys() {
            if let value = sqliteCookieValue(key) { keychain.write(Self.cookieNamespace + key, value) }
        }
    }

    private func sqliteCacheValue(_ key: String) -> String? {
        lock.lock()
        defer { lock.unlock() }
        return Self.readValue(handle, "SELECT value FROM caches WHERE `key` = ? AND deadline = 0", key)
    }

    private func sqliteCookieValue(_ key: String) -> String? {
        lock.lock()
        defer { lock.unlock() }
        return Self.readValue(handle, "SELECT cookie FROM cookies WHERE url = ?", key)
    }

    private func compare(
        _ sqlite: String,
        keychain: any KeychainStoring,
        account: String,
        key: String,
        into report: inout CredentialReconciliation
    ) {
        guard let mirrored = keychain.read(account) else {
            report.missing.append(key)
            return
        }
        if mirrored != sqlite { report.mismatch.append(key) }
    }

    // MARK: - SQLite 原语

    private static func readValue(_ handle: OpaquePointer?, _ sql: String, _ key: String, _ now: Int64? = nil) -> String? {
        guard let handle else { return nil }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK, let statement else { return nil }
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_text(statement, 1, key, -1, transient)
        if let now { sqlite3_bind_int64(statement, 2, now) }
        guard sqlite3_step(statement) == SQLITE_ROW, let value = sqlite3_column_text(statement, 0) else { return nil }
        return String(cString: value)
    }

    private static func writeValue(_ handle: OpaquePointer?, _ sql: String, _ key: String, _ value: String, _ deadline: Int64? = nil) -> Bool {
        guard let handle else { return false }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK, let statement else { return false }
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_text(statement, 1, key, -1, transient)
        sqlite3_bind_text(statement, 2, value, -1, transient)
        if let deadline { sqlite3_bind_int64(statement, 3, deadline) }
        return sqlite3_step(statement) == SQLITE_DONE
    }

    private static func executeBound(_ handle: OpaquePointer?, _ sql: String, text: String) {
        guard let handle else { return }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK, let statement else { return }
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_text(statement, 1, text, -1, transient)
        sqlite3_step(statement)
    }

    private static func column(_ handle: OpaquePointer?, _ sql: String) -> [String] {
        guard let handle else { return [] }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK, let statement else { return [] }
        defer { sqlite3_finalize(statement) }
        var result: [String] = []
        while sqlite3_step(statement) == SQLITE_ROW, let c = sqlite3_column_text(statement, 0) {
            result.append(String(cString: c))
        }
        return result
    }

    private static let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
}

public actor InMemorySearchBookRepository: SearchBookRepository {
    private var values: [String: SearchBook] = [:]
    public init(values: [SearchBook] = []) {
        self.values = Dictionary(uniqueKeysWithValues: values.map { ($0.bookURL, $0) })
    }
    public func get(bookURL: String) -> SearchBook? { values[bookURL] }
    public func cachedMatches(keyword: String) async throws -> [SearchBook] {
        guard !keyword.isEmpty else { return [] }
        return Array(values.values.filter {
            $0.name.localizedCaseInsensitiveContains(keyword) || $0.author.localizedCaseInsensitiveContains(keyword)
        }.sorted {
            let lhsExact = $0.name == keyword || $0.author == keyword
            let rhsExact = $1.name == keyword || $1.author == keyword
            if lhsExact != rhsExact { return lhsExact }
            return $0.time > $1.time
        }.prefix(200))
    }
    public func first(name: String, author: String) -> SearchBook? {
        values.values.filter { $0.name == name && $0.author == author }
            .sorted { $0.originOrder < $1.originOrder }.first
    }
    public func changeSources(name: String, author: String, sourceGroup: String, key: String?) -> [SearchBook] {
        values.values.filter {
            $0.name == name && $0.author.localizedCaseInsensitiveContains(author)
                && (key?.isEmpty != false
                    || $0.originName.localizedCaseInsensitiveContains(key ?? "")
                    || ($0.latestChapterTitle ?? "").localizedCaseInsensitiveContains(key ?? ""))
        }.sorted { $0.originOrder < $1.originOrder }
    }
    public func enabledWithCover(name: String, author: String) -> [SearchBook] {
        values.values.filter { $0.name == name && $0.author == author && !($0.coverURL ?? "").isEmpty }
            .sorted { $0.originOrder < $1.originOrder }
    }
    public func put(_ books: [SearchBook]) { for book in books { values[book.bookURL] = book } }
    public func clear(name: String, author: String) {
        values = values.filter { $0.value.name != name || $0.value.author != author }
    }
    public func clearExpired(before time: Int64) { values = values.filter { $0.value.time >= time } }
}
