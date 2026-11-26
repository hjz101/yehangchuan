import Foundation

/// 一次保存要落到磁盘的全部内容。
///
/// 索引里的各个分区（书架、书源、书签……）原样带上；正文只带**这次真的动过**的书。
/// 正文按书分开存就是为了这一刻：翻一页只需要重写一本，不必把整座书库重新编码。
public struct LibraryWritePlan: Sendable {
    /// 索引分区。键名与 App 原有快照字段一致，不含 `customChapters`。
    public var sections: [String: JSONValue]
    /// 书 ID → 这次需要写盘的章节正文。
    public var chapters: [String: [StoredChapter]]
    /// 需要整本替换清单的书（换源、重新导入：章节全换了一批）。
    /// 与 `chapters` 互斥，出现在这里的书不会再走增量合并。
    public var replacedBooks: Set<String>
    /// 保存后磁盘上应当存有正文的书，按 ID 排序。索引据此记录清单。
    public var booksWithChapters: [String]
    /// 这次要删掉正文的书（已从书架移除）。
    public var removedBooks: [String]

    public init(
        sections: [String: JSONValue],
        chapters: [String: [StoredChapter]] = [:],
        replacedBooks: Set<String> = [],
        booksWithChapters: [String] = [],
        removedBooks: [String] = []
    ) {
        self.sections = sections
        self.chapters = chapters
        self.replacedBooks = replacedBooks
        self.booksWithChapters = booksWithChapters
        self.removedBooks = removedBooks
    }
}

/// 一次读取的结果：索引 + 各书正文 + 读不出来的书。
public struct LibraryDocument: Sendable {
    public var index: LibraryIndex
    /// 书 ID → 章节（按 `order` 排好）。
    public var chapters: [String: [StoredChapter]]
    /// 书 ID → 失败原因。单本书的正文坏了不连累整个书库，但必须如实报出来。
    public var failures: [String: String]
    /// 当前索引读不出来、退回上一版索引时为 true。界面要如实说明
    /// 「这次读到的是上一次保存的内容」，而不是装作一切正常。
    public var recoveredFromPreviousIndex: Bool

    public init(
        index: LibraryIndex,
        chapters: [String: [StoredChapter]],
        failures: [String: String] = [:],
        recoveredFromPreviousIndex: Bool = false
    ) {
        self.index = index
        self.chapters = chapters
        self.failures = failures
        self.recoveredFromPreviousIndex = recoveredFromPreviousIndex
    }
}

/// 把一次保存按「先正文、再索引、最后回收」的顺序落盘。
///
/// 顺序不是随手排的：
/// 1. **正文先写**。正文是内容寻址的，同名即同内容，只增不改，中途崩溃最多留下孤儿。
/// 2. **索引是提交点**。索引写完，前面这些正文才算生效；写到一半崩了，
///    索引仍然指着上一版完整数据，不会出现「半本书」。
/// 3. **最后才删**。已移除书籍的正文要等索引不再引用它们之后再删；
///    反过来的话，崩溃时索引还指着已经被删掉的文件。
public enum LibraryDocumentWriter {
    @discardableResult
    public static func write(_ plan: LibraryWritePlan, to storage: LibraryStorage) throws -> LibraryIndex {
        for bookID in plan.replacedBooks.sorted() {
            try storage.replaceChapters(plan.chapters[bookID] ?? [], bookID: bookID)
        }
        for (bookID, chapters) in plan.chapters.sorted(by: { $0.key < $1.key })
        where !plan.replacedBooks.contains(bookID) {
            try storage.saveChapters(chapters, bookID: bookID)
        }

        let index = LibraryIndex(
            sections: plan.sections,
            booksWithChapters: plan.booksWithChapters
        )
        try storage.saveIndex(index)

        for bookID in plan.removedBooks {
            try storage.removeBook(bookID)
        }
        return index
    }
}

/// 读新结构的结果。
public enum LibraryReadResult: Sendable {
    /// 索引不存在：全新安装，或迁移还没跑过。
    case none
    case loaded(LibraryDocument)
    /// 索引文件在，但读不懂。**绝不能**就地覆盖 —— 那是用户的书库。
    /// 调用方应当先改名留档，再决定回落到哪里。
    case corrupt(reason: String)
}

/// 读新结构。
public enum LibraryDocumentReader {
    /// 当前索引读不懂时先退回上一版索引（`library.prev.json`），
    /// 并标记 `recoveredFromPreviousIndex` —— 用户看到的是上次保存的内容，
    /// 而不是一个空书架。两份都读不懂才报 `corrupt`。
    ///
    /// 索引版本比本 App 新时抛 `unsupportedVersion`：那是更新版 App 正在用的
    /// 数据，按旧规则解释只会写坏它，绝不能当成「损坏」去留档或覆盖。
    public static func read(from storage: LibraryStorage) throws -> LibraryReadResult {
        switch try readIndex(at: storage.indexURL) {
        case .ok(let index):
            return .loaded(document(index: index, storage: storage))
        case .missing:
            return .none
        case .unreadable:
            // 当前索引坏了：先看上一版。它是上一次保存前的内容，
            // 最多丢一次保存，比丢掉整座书库好得多。
            switch try readIndex(at: storage.previousIndexURL) {
            case .ok(let index):
                return .loaded(document(index: index, storage: storage, recovered: true))
            case .missing, .unreadable:
                return .corrupt(reason: "书架索引文件损坏，已保留原文件。")
            }
        }
    }

    private enum IndexRead {
        case ok(LibraryIndex)
        case missing
        case unreadable
    }

    private static func readIndex(at url: URL) throws -> IndexRead {
        guard FileManager.default.fileExists(atPath: url.path) else { return .missing }
        guard let index = try? JSONDecoder().decode(LibraryIndex.self, from: Data(contentsOf: url)) else {
            return .unreadable
        }
        guard index.version <= LibraryIndex.currentVersion else {
            throw LibraryStorageError.unsupportedVersion(index.version)
        }
        return .ok(index)
    }

    private static func document(
        index: LibraryIndex,
        storage: LibraryStorage,
        recovered: Bool = false
    ) -> LibraryDocument {
        var chapters: [String: [StoredChapter]] = [:]
        var failures: [String: String] = [:]
        for bookID in index.booksWithChapters {
            do {
                chapters[bookID] = try storage.chapters(bookID: bookID)
            } catch {
                failures[bookID] = (error as? LocalizedError)?.errorDescription
                    ?? String(describing: error)
            }
        }
        return LibraryDocument(
            index: index,
            chapters: chapters,
            failures: failures,
            recoveredFromPreviousIndex: recovered
        )
    }
}
