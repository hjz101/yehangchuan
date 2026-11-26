import CryptoKit
import Foundation

/// 一次迁移的结果，用于界面如实汇报「搬了多少、有没有问题」。
public struct LibraryMigrationReport: Equatable, Sendable {
    public var didRun: Bool
    public var bookCount: Int
    public var chapterCount: Int
    public var paragraphCount: Int
    public var archivedFile: URL?
    public var warnings: [String]
    /// 给用户看的一句话。迁移失败时说明原因，成功时说明搬了多少东西。
    public var message: String

    public init(
        didRun: Bool,
        bookCount: Int = 0,
        chapterCount: Int = 0,
        paragraphCount: Int = 0,
        archivedFile: URL? = nil,
        warnings: [String] = [],
        message: String
    ) {
        self.didRun = didRun
        self.bookCount = bookCount
        self.chapterCount = chapterCount
        self.paragraphCount = paragraphCount
        self.archivedFile = archivedFile
        self.warnings = warnings
        self.message = message
    }
}

/// 迁移状态。存在即表示已经搬过，避免每次启动都重搬一遍、堆一堆留档文件。
public struct LibraryMigrationState: Codable, Equatable, Sendable {
    /// 迁移逻辑自身的版本。搬家规则变了就 +1，下次启动会按新规则重搬。
    public static let currentVersion = 1

    public var migrationVersion: Int
    public var sourceFingerprint: String
    public var archivedFile: String
    public var bookCount: Int
    public var chapterCount: Int
    public var migratedAt: Date

    public init(
        migrationVersion: Int = LibraryMigrationState.currentVersion,
        sourceFingerprint: String,
        archivedFile: String,
        bookCount: Int,
        chapterCount: Int,
        migratedAt: Date
    ) {
        self.migrationVersion = migrationVersion
        self.sourceFingerprint = sourceFingerprint
        self.archivedFile = archivedFile
        self.bookCount = bookCount
        self.chapterCount = chapterCount
        self.migratedAt = migratedAt
    }
}

/// 把旧的一体化 `snapshot.json` 搬成「索引 + 章节文件」。
///
/// 这一步是纯加法：搬完之后旧文件改名留档，但 App 的读写仍然走旧路径
/// （旧路径会回落到留档文件，见 `SnapshotStore.read`）。因此迁移出错时
/// 最坏情况是「新结构不完整」，用户的书库照旧能用。
///
/// 关键顺序：先写章节并读回校验，再写索引并读回校验，最后才改名留档。
/// 任何一步失败都不留档、不写状态，下次启动还会再试。
public enum LibraryMigrator {
    public static func stateURL(root: URL) -> URL {
        root.appendingPathComponent("migration.json")
    }

    public static func loadState(root: URL) -> LibraryMigrationState? {
        guard let data = try? Data(contentsOf: stateURL(root: root)) else { return nil }
        return try? JSONDecoder().decode(LibraryMigrationState.self, from: data)
    }

    /// 留档的旧快照，按时间戳从新到旧。
    ///
    /// 迁移把 `snapshot.json` 改名成 `snapshot.migrated-<时间戳>.json`。
    /// 旧读路径靠它兜底：即使新结构有问题，用户的架子与正文仍然读得回来。
    public static func archivedSnapshots(in directory: URL) -> [URL] {
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: directory.path) else { return [] }
        return names
            .filter { $0.hasPrefix("snapshot.migrated-") && $0.hasSuffix(".json") }
            .sorted { stamp(of: $0) > stamp(of: $1) }
            .map { directory.appendingPathComponent($0) }
    }

    /// 最新的留档快照。没有则返回 nil。
    public static func newestArchivedSnapshot(in directory: URL) -> URL? {
        archivedSnapshots(in: directory).first
    }

    private static func stamp(of filename: String) -> Int {
        // snapshot.migrated-1700000000.json → 1700000000
        let trimmed = filename
            .replacingOccurrences(of: "snapshot.migrated-", with: "")
            .replacingOccurrences(of: ".json", with: "")
        return Int(trimmed) ?? 0
    }

    /// 执行迁移。
    /// - Parameters:
    ///   - legacyURL: 旧的 `snapshot.json` 路径。
    ///   - storage: 新结构的根。
    ///   - force: 忽略「已迁移过」的状态，强制重搬（调试用）。
    @discardableResult
    public static func migrate(
        legacyURL: URL,
        storage: LibraryStorage,
        now: Date = Date(),
        force: Bool = false
    ) throws -> LibraryMigrationReport {
        guard FileManager.default.fileExists(atPath: legacyURL.path) else {
            return LibraryMigrationReport(didRun: false, message: "没有旧书架文件，无需迁移。")
        }
        let data = try Data(contentsOf: legacyURL)
        let fingerprint = ContentID.hex(SHA256.hash(data: data))

        if !force,
           let state = loadState(root: storage.root),
           state.migrationVersion == LibraryMigrationState.currentVersion {
            return LibraryMigrationReport(
                didRun: false,
                bookCount: state.bookCount,
                chapterCount: state.chapterCount,
                message: "书架已迁移过（\(state.chapterCount) 章），本次跳过。"
            )
        }

        let result = try LegacySnapshotMigration.migrate(data)

        // 索引里的书签与阅读位置还指着旧式段落 ID（章ID-p序号）。
        // 新结构的正文用的是内容寻址 ID，这里必须同步改写，
        // 否则下一步切换读写路径后，所有书签都会指到不存在的段落。
        var index = result.index
        var warnings = result.warnings
        try LegacySnapshotMigration.remapAnchorIDs(
            in: &index,
            using: result.paragraphIDMap,
            warnings: &warnings
        )

        // 1. 先写章节正文并读回校验：正文是最大的一块，必须先确认它完整。
        var paragraphTotal = 0
        for (bookID, chapters) in result.chapters {
            try storage.saveChapters(chapters, bookID: bookID)
            let reloaded = try storage.chapters(bookID: bookID)
            try verify(chapters: chapters, against: reloaded, bookID: bookID)
            paragraphTotal += chapters.reduce(0) { $0 + $1.paragraphs.count }
        }

        // 2. 再写索引并读回校验：每个分区都要原样还在，少一个字段都不算成功。
        try storage.saveIndex(index)
        let stored = try storage.loadIndex()
        guard let stored else { throw MigrationVerificationError.indexMissing }
        guard stored.version == index.version else {
            throw MigrationVerificationError.indexVersion(expected: index.version, actual: stored.version)
        }
        guard stored.sections == index.sections else {
            throw MigrationVerificationError.sectionsMismatch
        }
        guard stored.booksWithChapters == index.booksWithChapters else {
            throw MigrationVerificationError.sectionsMismatch
        }

        // 3. 全部校验通过，才把旧文件改名留档。
        let stamp = Int(now.timeIntervalSince1970)
        let archived = legacyURL
            .deletingPathExtension()
            .appendingPathExtension("migrated-\(stamp).json")
        try FileManager.default.moveItem(at: legacyURL, to: archived)

        let state = LibraryMigrationState(
            sourceFingerprint: fingerprint,
            archivedFile: archived.lastPathComponent,
            bookCount: result.chapters.count,
            chapterCount: result.chapters.values.reduce(0) { $0 + $1.count },
            migratedAt: now
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
        try encoder.encode(state).write(to: stateURL(root: storage.root), options: .atomic)

        return LibraryMigrationReport(
            didRun: true,
            bookCount: state.bookCount,
            chapterCount: state.chapterCount,
            paragraphCount: paragraphTotal,
            archivedFile: archived,
            warnings: warnings,
            message: "书架已迁移：\(state.bookCount) 本 / \(state.chapterCount) 章 / \(paragraphTotal) 段。"
        )
    }

    /// 逐章比对：数量、顺序、每段 ID 与文字都要一致。
    private static func verify(
        chapters: [StoredChapter],
        against reloaded: [StoredChapter],
        bookID: String
    ) throws {
        guard chapters.count == reloaded.count else {
            throw MigrationVerificationError.chapterCountMismatch(bookID: bookID, expected: chapters.count, actual: reloaded.count)
        }
        let expected = chapters.sorted { $0.order < $1.order }
        for (lhs, rhs) in zip(expected, reloaded) {
            guard lhs.id == rhs.id, lhs.title == rhs.title else {
                throw MigrationVerificationError.chapterMismatch(bookID: bookID, chapterID: lhs.id)
            }
            guard lhs.paragraphs.map(\.id) == rhs.paragraphs.map(\.id) else {
                throw MigrationVerificationError.paragraphIDsMismatch(bookID: bookID, chapterID: lhs.id)
            }
            guard lhs.paragraphs.map(\.text) == rhs.paragraphs.map(\.text) else {
                throw MigrationVerificationError.paragraphTextMismatch(bookID: bookID, chapterID: lhs.id)
            }
        }
    }
}

public enum MigrationVerificationError: Error, LocalizedError, Equatable, Sendable {
    case chapterCountMismatch(bookID: String, expected: Int, actual: Int)
    case chapterMismatch(bookID: String, chapterID: String)
    case paragraphIDsMismatch(bookID: String, chapterID: String)
    case paragraphTextMismatch(bookID: String, chapterID: String)
    case indexMissing
    case indexVersion(expected: Int, actual: Int)
    case sectionsMismatch

    public var errorDescription: String? {
        switch self {
        case .chapterCountMismatch(let bookID, let expected, let actual):
            "《\(bookID)》迁移后章节数不对（应 \(expected)，实际 \(actual)），旧文件已保留。"
        case .chapterMismatch(let bookID, let chapterID):
            "《\(bookID)》的章节 \(chapterID) 迁移后对不上，旧文件已保留。"
        case .paragraphIDsMismatch(let bookID, let chapterID):
            "《\(bookID)》章节 \(chapterID) 的段落 ID 迁移后对不上，旧文件已保留。"
        case .paragraphTextMismatch(let bookID, let chapterID):
            "《\(bookID)》章节 \(chapterID) 的正文迁移后对不上，旧文件已保留。"
        case .indexMissing:
            "书架索引写入后读不回来，旧文件已保留。"
        case .indexVersion(let expected, let actual):
            "书架索引版本不对（应 \(expected)，实际 \(actual)），旧文件已保留。"
        case .sectionsMismatch:
            "书架索引里有字段没搬全，旧文件已保留。"
        }
    }
}
