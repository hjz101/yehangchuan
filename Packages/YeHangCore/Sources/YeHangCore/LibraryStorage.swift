import CryptoKit
import Foundation

/// 书架索引：只放「轻」数据，不放正文。
///
/// 旧版把全书正文塞进一个 JSON（`customChapters`），每次翻页都全量重编码，
/// 而且任何字段变更都会让整个文件解码失败、书库看起来「消失」。
/// 这里把正文搬到独立文件，索引只剩元数据 + 分区载荷。
public struct LibraryIndex: Codable, Equatable, Sendable {
    /// 索引自身的版本号。**必须**存在：没有它就无法判断手上这份文件是哪一代格式，
    /// 只能靠解码失败来猜，而解码失败意味着用户的书库已经没了。
    public static let currentVersion = 1

    public var version: Int
    /// 各个数据分区原样保留：键名与 App 原来的快照字段一致
    /// （books / sources / excerpts / settings / …），存储层不解释其含义。
    public var sections: [String: JSONValue]
    /// 在 `books/<hash>/` 下存有章节正文的书。正文不在索引里。
    public var booksWithChapters: [String]

    public init(
        version: Int = LibraryIndex.currentVersion,
        sections: [String: JSONValue] = [:],
        booksWithChapters: [String] = []
    ) {
        self.version = version
        self.sections = sections
        self.booksWithChapters = booksWithChapters
    }

    /// 从索引里取某个分区并解码成 App 的类型。
    public func decode<T: Decodable>(_ type: T.Type, for key: String) throws -> T? {
        guard let value = sections[key] else { return nil }
        let data = try JSONEncoder().encode(value)
        return try JSONDecoder().decode(type, from: data)
    }

    /// 把 App 的类型编码进某个分区。
    public mutating func encode<T: Encodable>(_ value: T, for key: String) throws {
        let data = try JSONEncoder().encode(value)
        sections[key] = try JSONDecoder().decode(JSONValue.self, from: data)
    }

    /// 旧格式（没有 version 字段，正文在 customChapters 里）。
    /// 只有迁移逻辑会用它，正常运行期不该再读到。
    public var isLegacy: Bool { version < LibraryIndex.currentVersion }
}

// MARK: - 章节正文

/// 一章正文的落盘形态。与 App 的 `Chapter` 对应，但只保存必要字段，
/// 并把 App 自己的附加载荷（段评等）原样带着，不在迁移中丢失。
public struct StoredChapter: Codable, Equatable, Sendable {
    public struct Paragraph: Codable, Equatable, Sendable {
        public var id: String
        public var text: String
        /// App 的附加数据（段评等）原样保留；存储层不解释它，也不丢它。
        public var attachments: JSONValue?

        public init(id: String, text: String, attachments: JSONValue? = nil) {
            self.id = id
            self.text = text
            self.attachments = attachments
        }
    }

    public var id: String
    public var title: String
    public var order: Int
    public var paragraphs: [Paragraph]
    /// 在线书的章节地址，本地与演示章节为 nil。
    public var networkURL: String?

    public init(
        id: String,
        title: String,
        order: Int,
        paragraphs: [Paragraph],
        networkURL: String? = nil
    ) {
        self.id = id
        self.title = title
        self.order = order
        self.paragraphs = paragraphs
        self.networkURL = networkURL
    }
}

/// 一本书的章节清单。它是提交点：正文对象先写好，清单最后原子替换。
/// 中途崩溃时清单仍指向上一批完整对象，不会出现「半本书」。
public struct ChapterManifest: Codable, Equatable, Sendable {
    public static let currentVersion = 1
    public var version: Int
    /// 章节 ID → 对象文件名（内容摘要 + .json）。
    public var entries: [String: String]

    public init(version: Int = ChapterManifest.currentVersion, entries: [String: String] = [:]) {
        self.version = version
        self.entries = entries
    }
}

// MARK: - 写入抽象

public protocol FileWriting: Sendable {
    func write(_ data: Data, to url: URL) throws
}

public struct AtomicFileWriter: FileWriting {
    public init() {}
    public func write(_ data: Data, to url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: url, options: .atomic)
    }
}

// MARK: - 磁盘布局

/// ```
/// <root>/
///   library.json                    ← 索引（含 version）
///   books/<bookHash>/manifest.json  ← 章节清单（提交点）
///   books/<bookHash>/objects/<sha>.json
/// ```
///
/// 方法都是同步的，调用方负责串行（App 侧已有 600ms 合并写入）。
public struct LibraryStorage: Sendable {
    public let root: URL
    private let writer: any FileWriting

    public init(root: URL, writer: any FileWriting = AtomicFileWriter()) {
        self.root = root
        self.writer = writer
    }

    public static func live() -> LibraryStorage {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return LibraryStorage(root: base.appendingPathComponent("YeHangChuan", isDirectory: true))
    }

    // MARK: 索引

    public var indexURL: URL { root.appendingPathComponent("library.json") }

    /// 上一版索引。每次保存前留一份，用来兜住「索引写得出来、读不回来」这种
    /// 最尴尬的情况：原子写能防掉电，防不住逻辑上讲不通的数据。
    public var previousIndexURL: URL { root.appendingPathComponent("library.prev.json") }

    public func loadIndex() throws -> LibraryIndex? {
        guard FileManager.default.fileExists(atPath: indexURL.path) else { return nil }
        let data = try Data(contentsOf: indexURL)
        let decoder = JSONDecoder()
        return try decoder.decode(LibraryIndex.self, from: data)
    }

    /// 读上一版索引。没有就返回 nil。
    public func loadPreviousIndex() throws -> LibraryIndex? {
        guard FileManager.default.fileExists(atPath: previousIndexURL.path) else { return nil }
        return try JSONDecoder().decode(LibraryIndex.self, from: Data(contentsOf: previousIndexURL))
    }

    public func saveIndex(_ index: LibraryIndex) throws {
        var sorted = index
        sorted.sections = index.sections
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(sorted)
        // 先把当前这份留成上一版，再覆盖。顺序不能反：反过来的话，
        // 崩溃在两者之间就只剩一份坏索引，没有回退点。
        //
        // 只在当前这份**确实读得懂**时才轮换：否则一次坏索引会把
        // 上一版的好索引顶掉，回退点就没了。
        if let current = try? Data(contentsOf: indexURL),
           (try? JSONDecoder().decode(LibraryIndex.self, from: current)) != nil {
            try writer.write(current, to: previousIndexURL)
        }
        try writer.write(data, to: indexURL)
    }

    /// 把读不懂的索引改名留档，绝不覆盖。返回留档后的路径。
    @discardableResult
    public func quarantineIndex(at date: Date = Date()) throws -> URL? {
        guard FileManager.default.fileExists(atPath: indexURL.path) else { return nil }
        let stamp = Int(date.timeIntervalSince1970)
        let target = root.appendingPathComponent("library.corrupt-\(stamp).json")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try FileManager.default.moveItem(at: indexURL, to: target)
        return target
    }

    // MARK: 章节

    /// 书名可以是任意字符串，不能直接当目录名（`../` 会跑出沙箱）。
    /// 统一用摘要做目录名。
    public func bookDirectory(_ bookID: String) -> URL {
        let name = ContentID.digest(components: ["book", bookID])
        return root.appendingPathComponent("books", isDirectory: true)
            .appendingPathComponent(name, isDirectory: true)
    }

    private var objectsDirectoryName: String { "objects" }

    public func manifest(bookID: String) throws -> ChapterManifest {
        let url = bookDirectory(bookID).appendingPathComponent("manifest.json")
        guard FileManager.default.fileExists(atPath: url.path) else { return ChapterManifest() }
        let manifest = try JSONDecoder().decode(ChapterManifest.self, from: Data(contentsOf: url))
        guard manifest.version <= ChapterManifest.currentVersion else {
            throw LibraryStorageError.unsupportedVersion(manifest.version)
        }
        return manifest
    }

    /// 写入一批章节：先写正文对象，最后原子替换清单。
    public func saveChapters(_ chapters: [StoredChapter], bookID: String) throws {
        guard Set(chapters.map(\.id)).count == chapters.count else {
            throw LibraryStorageError.duplicateChapterID
        }
        let directory = bookDirectory(bookID)
        let objects = directory.appendingPathComponent(objectsDirectoryName, isDirectory: true)
        try FileManager.default.createDirectory(at: objects, withIntermediateDirectories: true)

        var next = try manifest(bookID: bookID)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]

        for chapter in chapters {
            let data = try encoder.encode(chapter)
            let filename = ContentID.hex(SHA256.hash(data: data)) + ".json"
            let target = objects.appendingPathComponent(filename)
            if !FileManager.default.fileExists(atPath: target.path) {
                try writer.write(data, to: target)
            }
            // 登记必须无条件执行：崩溃可能停在「对象已写、清单未登记」之间，
            // 重跑时对象虽已存在，这一章仍必须进清单，否则校验永远失败。
            // 内容寻址下同名即同内容，存在就跳过写入，但绝不能跳过登记。
            next.entries[chapter.id] = filename
        }
        try writer.write(encoder.encode(next), to: directory.appendingPathComponent("manifest.json"))
    }

    /// 整本替换：清单只保留这一批章节，旧章一并清掉。
    ///
    /// 换源与重新导入都属于这种情况 —— 章节全换了一批，若走 `saveChapters`
    /// 的增量合并，旧源的章节会一直留在清单里，目录看着多出一倍。
    public func replaceChapters(_ chapters: [StoredChapter], bookID: String) throws {
        guard Set(chapters.map(\.id)).count == chapters.count else {
            throw LibraryStorageError.duplicateChapterID
        }
        let directory = bookDirectory(bookID)
        let objects = directory.appendingPathComponent(objectsDirectoryName, isDirectory: true)
        try FileManager.default.createDirectory(at: objects, withIntermediateDirectories: true)

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]

        var entries: [String: String] = [:]
        for chapter in chapters {
            let data = try encoder.encode(chapter)
            let filename = ContentID.hex(SHA256.hash(data: data)) + ".json"
            let target = objects.appendingPathComponent(filename)
            if !FileManager.default.fileExists(atPath: target.path) {
                try writer.write(data, to: target)
            }
            entries[chapter.id] = filename
        }
        // 清单是提交点：正文全部就位后一次性替换。
        let manifest = ChapterManifest(entries: entries)
        try writer.write(encoder.encode(manifest), to: directory.appendingPathComponent("manifest.json"))
    }

    public func chapter(id: String, bookID: String) throws -> StoredChapter? {
        let manifest = try manifest(bookID: bookID)
        guard let filename = manifest.entries[id] else { return nil }
        return try decodeChapter(id: id, filename: filename, bookID: bookID)
    }

    /// 按顺序读出整本书的章节。缺对象时如实报错，不静默跳过。
    public func chapters(bookID: String) throws -> [StoredChapter] {
        // manifest 只读一次。逐章调 chapter(id:) 会把同一份 manifest
        // 重读 N 次，书越大启动越慢。
        let manifest = try manifest(bookID: bookID)
        var result: [StoredChapter] = []
        result.reserveCapacity(manifest.entries.count)
        for (id, filename) in manifest.entries {
            result.append(try decodeChapter(id: id, filename: filename, bookID: bookID))
        }
        return result.sorted { $0.order < $1.order }
    }

    private func decodeChapter(id: String, filename: String, bookID: String) throws -> StoredChapter {
        let url = try objectURL(filename, bookID: bookID)
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw LibraryStorageError.missingObject(filename)
        }
        let chapter = try JSONDecoder().decode(StoredChapter.self, from: Data(contentsOf: url))
        guard chapter.id == id else { throw LibraryStorageError.objectMismatch }
        return chapter
    }

    public func chapterIDs(bookID: String) throws -> Set<String> {
        Set(try manifest(bookID: bookID).entries.keys)
    }

    public func removeBook(_ bookID: String) throws {
        let directory = bookDirectory(bookID)
        guard FileManager.default.fileExists(atPath: directory.path) else { return }
        try FileManager.default.removeItem(at: directory)
    }

    /// 清掉清单里已经不引用的对象（旧章节版本）。只在成功读取后调用，
    /// 崩溃后残留的孤儿对象靠它回收。
    public func collectGarbage(bookID: String) throws {
        let directory = bookDirectory(bookID)
        let objects = directory.appendingPathComponent(objectsDirectoryName, isDirectory: true)
        guard FileManager.default.fileExists(atPath: objects.path) else { return }
        let keep = Set(try manifest(bookID: bookID).entries.values)
        for url in try FileManager.default.contentsOfDirectory(at: objects, includingPropertiesForKeys: nil) {
            let name = url.lastPathComponent
            guard Self.isValidObjectName(name) else { continue }
            if !keep.contains(name) { try FileManager.default.removeItem(at: url) }
        }
    }

    /// 某个书在磁盘上占多少字节，用于「缓存」页面展示真实数值。
    public func byteCount(bookID: String) throws -> Int {
        let directory = bookDirectory(bookID)
        guard FileManager.default.fileExists(atPath: directory.path) else { return 0 }
        guard let enumerator = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: [.fileSizeKey]
        ) else { return 0 }
        var total = 0
        for case let url as URL in enumerator {
            total += (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        }
        return total
    }

    // MARK: 路径校验

    static func isValidObjectName(_ name: String) -> Bool {
        guard name.hasSuffix(".json") else { return false }
        let digest = name.dropLast(5)
        return digest.count == 64 && digest.allSatisfy { "0123456789abcdef".contains($0) }
    }

    private func objectURL(_ filename: String, bookID: String) throws -> URL {
        guard Self.isValidObjectName(filename) else { throw LibraryStorageError.invalidObjectName }
        let folder = bookDirectory(bookID)
            .appendingPathComponent(objectsDirectoryName, isDirectory: true)
            .standardizedFileURL
            .resolvingSymlinksInPath()
        let url = folder.appendingPathComponent(filename).standardizedFileURL.resolvingSymlinksInPath()
        guard url.deletingLastPathComponent() == folder else { throw LibraryStorageError.invalidObjectName }
        return url
    }
}

public enum LibraryStorageError: Error, LocalizedError, Equatable, Sendable {
    case unsupportedVersion(Int)
    case duplicateChapterID
    case missingObject(String)
    case objectMismatch
    case invalidObjectName

    public var errorDescription: String? {
        switch self {
        case .unsupportedVersion(let version):
            "书架数据的版本（\(version)）比当前 App 新，请先升级 App 再打开。"
        case .duplicateChapterID:
            "章节 ID 重复，未写入任何内容。"
        case .missingObject(let name):
            "章节正文文件缺失（\(name)），请重新下载这一章。"
        case .objectMismatch:
            "章节正文与索引对不上，已拒绝使用这份缓存。"
        case .invalidObjectName:
            "章节正文路径非法，已拒绝读写。"
        }
    }
}
