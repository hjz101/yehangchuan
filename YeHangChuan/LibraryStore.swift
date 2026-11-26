import Foundation
import YeHangCore

/// 索引里的各个分区。与 `AppStore.Snapshot` 字段一致，但**不含 `customChapters`**：
/// 正文不进索引，这是「书架消失」那类问题的根因 —— 旧版把整座书库塞进一个
/// JSON，任何一个字段改动都让整个文件解码失败。
///
/// 只用于**编码**。读的时候逐分区解码（见 `AppStore.apply(_:)`），
/// 某个分区读不出来只退回默认值，不连累整个书架。
struct LibrarySections: Encodable, Sendable {
    var books: [Book]
    var sources: [BookSource]
    var excerpts: [Excerpt]
    var settings: ReaderSnapshot
    var goalMinutes: Int
    var appearance: AppAppearance
    var bookmarks: [Bookmark]
    var positions: [String: ReadingPosition]
    var groups: [String]
    var eyeCare: EyeCareSettings

    init(_ snapshot: AppStore.Snapshot) {
        books = snapshot.books
        sources = snapshot.sources
        excerpts = snapshot.excerpts
        settings = snapshot.settings
        goalMinutes = snapshot.goalMinutes
        appearance = snapshot.appearance
        bookmarks = snapshot.bookmarks
        positions = snapshot.positions
        groups = snapshot.groups
        eyeCare = snapshot.eyeCare
    }
}

/// 书架的新存储：索引（元数据）+ 每本书的正文文件。
///
/// 与旧的一体化快照比：
/// - 索引里没有正文，翻页写回只有几十 KB，不随书库变大而变慢；
/// - 正文按书分文件，一次保存只重写**真的改过**的那一本；
/// - 章节正文按内容命名，同样的内容不会重复写盘。
///
/// 写序由 `LibraryDocumentWriter` 保证：先正文、再索引、最后删。
/// 索引是提交点 —— 写到一半崩溃时，索引仍指向上一版完整数据。
final class LibraryStore: @unchecked Sendable {
    static let shared = LibraryStore()

    struct Contents: Sendable {
        var sections: [String: JSONValue]
        /// 书 ID → 章节，已按顺序排好。
        var chapters: [String: [Chapter]]
        /// 书 ID → 读不出来的原因。单本坏了不连累书库，但必须说出来。
        var failures: [String: String]
        /// 读到的是上一版索引：上次保存的内容没读出来。界面要如实说明。
        var recoveredFromPreviousIndex: Bool
    }

    private let queue = DispatchQueue(label: "yehangchuan.library", qos: .utility)
    private var lastSequence = 0
    private var lastWrittenSequence = 0
    /// 上次落盘的内容，用来判断哪本书真的变了。
    /// 只在 `queue` 上访问。持有的是同一批 String 的引用，不复制正文。
    private var written: [String: [Chapter]] = [:]
    private var listed: Set<String> = []

    private let storage: LibraryStorage?
    let directory: URL?
    /// 最近一次读写失败的原因，给「存储」页如实展示。只在 `queue` 上访问。
    private var storedError: String?

    private init() {
        let manager = FileManager.default
        let base = manager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        var directory = base?.appendingPathComponent("YeHangChuan", isDirectory: true)
        if let directory {
            try? manager.createDirectory(at: directory, withIntermediateDirectories: true)
        } else {
            directory = base
        }
        self.directory = directory
        storage = directory.map { LibraryStorage(root: $0) }
    }

    /// 最近一次读写失败的原因。没有失败就是 nil。
    var lastError: String? {
        queue.sync { storedError }
    }

    func nextSequence() -> Int {
        queue.sync {
            lastSequence += 1
            return lastSequence
        }
    }

    // MARK: 读

    /// 读新结构。三种结果分开处理，因为它们对用户的后果完全不同：
    /// - 没有索引：全新安装，交给旧路径/演示数据；
    /// - 索引损坏：**先留档再回退**，绝不就地覆盖，那是用户的书库；
    /// - 版本太新：只报错，连留档都不做（那可能是更新版 App 正在用的数据）。
    func read() -> Contents? {
        guard let storage else { return nil }
        let result: LibraryReadResult
        do {
            result = try LibraryDocumentReader.read(from: storage)
        } catch {
            let message = (error as? LocalizedError)?.errorDescription ?? String(describing: error)
            // 数据比本 App 新：改名等于毁掉更新版 App 的数据，只如实报出来。
            queue.sync { storedError = message }
            return nil
        }

        switch result {
        case .none:
            return nil

        case .corrupt(let reason):
            // 留档后回落到上一版索引（如果有）或旧快照。
            _ = try? storage.quarantineIndex()
            queue.sync { storedError = reason }
            SnapshotStore.shared.recordDecodeFailure(reason)
            return nil

        case .loaded(let document):
            // 读到的是「上一版索引」说明当前这份坏掉了。三项都要做：
            // 1. 坏文件改名留档（留下证据、下次保存不再撞一次）；
            // 2. 把恢复出来的索引立刻写回当前位置 —— 否则本进程不保存的话，
            //    下次启动就没有 library.json 了，只能一路降级到旧快照，
            //    而旧快照的段落 ID 是旧式的，书签会跳错位置；
            // 3. 交给调用方如实告知「这次读到的是上一版」。
            if document.recoveredFromPreviousIndex {
                _ = try? storage.quarantineIndex()
                try? storage.saveIndex(document.index)
            }
            var chapters: [String: [Chapter]] = [:]
            for (bookID, stored) in document.chapters {
                chapters[bookID] = stored.map(Self.chapter(from:))
            }
            // 刚读到的就是磁盘上的内容：作为「哪些书真的变了」的基线。
            queue.sync {
                written = chapters
                listed = Set(document.index.booksWithChapters)
            }
            return Contents(
                sections: document.index.sections,
                chapters: chapters,
                failures: document.failures,
                recoveredFromPreviousIndex: document.recoveredFromPreviousIndex
            )
        }
    }

    // MARK: 写

    /// 合并写入的落点。`sequence` 保证晚到的旧数据不会覆盖新数据。
    /// - Parameter synchronously: 进入后台时用，必须在这行代码返回前就写完。
    func write(_ snapshot: AppStore.Snapshot, sequence: Int, synchronously: Bool = false) {
        let body = { [self] in
            guard sequence > lastWrittenSequence else { return }
            lastWrittenSequence = sequence
            do {
                try performWrite(snapshot)
            } catch {
                storedError = (error as? LocalizedError)?.errorDescription ?? String(describing: error)
                print("[YeHangChuan] 书架保存失败：\(storedError ?? "")")
            }
        }
        if synchronously {
            queue.sync(execute: body)
        } else {
            queue.async(execute: body)
        }
    }

    private func performWrite(_ snapshot: AppStore.Snapshot) throws {
        guard let storage else { return }

        // 只写这次真的动过的书。没动的书磁盘上已经是同一份内容，重编码是纯浪费。
        // 改过的整本交给 `replaceChapters`：正文按内容寻址，没变的章节
        // 连文件都不会重写，所以「整本」并不等于「写很多」。
        var changed: [String: [StoredChapter]] = [:]
        for (bookID, chapters) in snapshot.customChapters where !chapters.isEmpty {
            guard written[bookID] != chapters else { continue }
            changed[bookID] = chapters.enumerated().map { Self.stored($1, order: $0) }
        }

        let present = Set(snapshot.customChapters.filter { !$0.value.isEmpty }.keys)
        let removed = listed.subtracting(present)

        let plan = LibraryWritePlan(
            sections: try Self.sections(of: snapshot),
            chapters: changed,
            replacedBooks: Set(changed.keys),
            booksWithChapters: present.sorted(),
            removedBooks: removed.sorted()
        )
        try LibraryDocumentWriter.write(plan, to: storage)

        written = snapshot.customChapters.filter { !$0.value.isEmpty }
        listed = present
        storedError = nil
    }

    // MARK: 类型转换

    private static func sections(of snapshot: AppStore.Snapshot) throws -> [String: JSONValue] {
        let data = try JSONEncoder().encode(LibrarySections(snapshot))
        let value = try JSONDecoder().decode(JSONValue.self, from: data)
        return value.objectValue ?? [:]
    }

    private static func stored(_ chapter: Chapter, order: Int) -> StoredChapter {
        StoredChapter(
            id: chapter.id,
            title: chapter.title,
            order: order,
            paragraphs: chapter.paragraphs.map { paragraph in
                StoredChapter.Paragraph(
                    id: paragraph.id,
                    text: paragraph.text,
                    attachments: attachments(of: paragraph)
                )
            },
            networkURL: chapter.networkURL
        )
    }

    /// 段落里除正文之外的字段（目前是段评）原样存下来。
    /// 存储层不解释它，只保证不丢。
    private static func attachments(of paragraph: Paragraph) -> JSONValue? {
        guard !paragraph.comments.isEmpty else { return nil }
        guard let data = try? JSONEncoder().encode(paragraph.comments),
              let value = try? JSONDecoder().decode(JSONValue.self, from: data) else { return nil }
        return .object(["comments": value])
    }

    private static func chapter(from stored: StoredChapter) -> Chapter {
        Chapter(
            id: stored.id,
            title: stored.title,
            paragraphs: stored.paragraphs.map { paragraph in
                Paragraph(
                    id: paragraph.id,
                    text: paragraph.text,
                    comments: comments(of: paragraph.attachments)
                )
            },
            networkURL: stored.networkURL
        )
    }

    private static func comments(of attachments: JSONValue?) -> [SegmentComment] {
        guard let value = attachments?["comments"],
              let data = try? JSONEncoder().encode(value) else { return [] }
        return (try? JSONDecoder().decode([SegmentComment].self, from: data)) ?? []
    }
}
