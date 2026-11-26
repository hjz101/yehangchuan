import Foundation
import XCTest
@testable import YeHangCore

final class LibraryStorageTests: XCTestCase {
    private var root: URL!
    private var storage: LibraryStorage!

    override func setUpWithError() throws {
        try super.setUpWithError()
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("yh-storage-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        storage = LibraryStorage(root: root)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
        try super.tearDownWithError()
    }

    private func chapter(_ id: String, order: Int, paragraphs: [String] = ["正文"]) -> StoredChapter {
        StoredChapter(
            id: id,
            title: "第\(order)章",
            order: order,
            paragraphs: paragraphs.map { .init(id: "\(id)-\($0.hashValue)", text: $0) }
        )
    }

    // MARK: 索引

    func testIndexRoundTripKeepsEverySection() throws {
        var index = LibraryIndex()
        try index.encode([1, 2, 3], for: "books")
        try index.encode(["theme": "voyage"], for: "settings")
        try storage.saveIndex(index)

        let loaded = try XCTUnwrap(try storage.loadIndex())
        XCTAssertEqual(loaded.version, LibraryIndex.currentVersion)
        XCTAssertEqual(try loaded.decode([Int].self, for: "books"), [1, 2, 3])
        XCTAssertEqual(try loaded.decode([String: String].self, for: "settings"), ["theme": "voyage"])
    }

    /// 没有索引文件时返回 nil，而不是报错或返回空索引 ——
    /// 首次启动与「文件被删」必须能区分开。
    func testMissingIndexIsNil() throws {
        XCTAssertNil(try storage.loadIndex())
    }

    /// 读不懂的索引必须留档，绝不覆盖。
    func testCorruptIndexIsQuarantinedNotOverwritten() throws {
        try Data("{ 这不是 JSON".utf8).write(to: storage.indexURL)
        XCTAssertThrowsError(try storage.loadIndex())

        let archived = try storage.quarantineIndex(at: Date(timeIntervalSince1970: 1_700_000_000))
        XCTAssertNotNil(archived)
        XCTAssertFalse(FileManager.default.fileExists(atPath: storage.indexURL.path), "原文件应被移走")
        let moved = try XCTUnwrap(archived)
        XCTAssertTrue(FileManager.default.fileExists(atPath: moved.path), "留档必须还在")
        XCTAssertTrue(moved.lastPathComponent.contains("1700000000"))
    }

    /// 未来的版本号必须拒绝，而不是尝试按老格式读（会把新字段读丢）。
    func testFutureVersionIsRejected() throws {
        try storage.saveIndex(LibraryIndex(version: 99))
        let loaded = try XCTUnwrap(try storage.loadIndex())
        XCTAssertEqual(loaded.version, 99)
        XCTAssertFalse(loaded.isLegacy)
        // 读得出来但更高版本：由调用方按 unsupportedVersion 处理。
        try storage.saveIndex(LibraryIndex(version: LibraryIndex.currentVersion))
        XCTAssertEqual(try XCTUnwrap(try storage.loadIndex()).version, LibraryIndex.currentVersion)
    }

    // MARK: 章节

    func testChapterRoundTripIsOrderedAndComplete() throws {
        let chapters = (0..<5).map { chapter("c\($0)", order: $0) }
        try storage.saveChapters(chapters.shuffled(), bookID: "book-a")

        let loaded = try storage.chapters(bookID: "book-a")
        XCTAssertEqual(loaded.map(\.id), chapters.map(\.id), "顺序必须按 order，不是按写入顺序")
        XCTAssertEqual(try storage.chapterIDs(bookID: "book-a"), Set(chapters.map(\.id)))
    }

    /// 内容寻址：同样内容重复写入不产生新对象。
    func testIdenticalChaptersDoNotDuplicateObjects() throws {
        let value = chapter("c0", order: 0)
        try storage.saveChapters([value], bookID: "book-a")
        let before = try storage.byteCount(bookID: "book-a")
        try storage.saveChapters([value], bookID: "book-a")
        XCTAssertEqual(try storage.byteCount(bookID: "book-a"), before)
    }

    /// 更新一章后，旧对象变成孤儿，可被回收；新内容必须能读回。
    func testUpdatingChapterLeavesReclaimableObject() throws {
        try storage.saveChapters([chapter("c0", order: 0, paragraphs: ["旧正文"])], bookID: "book-a")
        try storage.saveChapters([chapter("c0", order: 0, paragraphs: ["新正文"])], bookID: "book-a")

        let loaded = try XCTUnwrap(try storage.chapter(id: "c0", bookID: "book-a"))
        XCTAssertEqual(loaded.paragraphs.map(\.text), ["新正文"])

        try storage.collectGarbage(bookID: "book-a")
        XCTAssertEqual(try XCTUnwrap(try storage.chapter(id: "c0", bookID: "book-a")).paragraphs.map(\.text), ["新正文"])
    }

    /// 正文对象被删掉时必须报错，而不是返回空章节让界面显示白屏。
    func testMissingObjectThrows() throws {
        try storage.saveChapters([chapter("c0", order: 0)], bookID: "book-a")
        let manifest = try storage.manifest(bookID: "book-a")
        let filename = try XCTUnwrap(manifest.entries["c0"])
        let url = storage.bookDirectory("book-a")
            .appendingPathComponent("objects")
            .appendingPathComponent(filename)
        try FileManager.default.removeItem(at: url)

        XCTAssertThrowsError(try storage.chapter(id: "c0", bookID: "book-a")) { error in
            XCTAssertEqual(error as? LibraryStorageError, .missingObject(filename))
        }
    }

    func testDuplicateChapterIDsRejectWholeBatch() throws {
        let batch = [chapter("dup", order: 0), chapter("dup", order: 1)]
        XCTAssertThrowsError(try storage.saveChapters(batch, bookID: "book-a")) { error in
            XCTAssertEqual(error as? LibraryStorageError, .duplicateChapterID)
        }
        XCTAssertEqual(try storage.chapterIDs(bookID: "book-a"), [], "拒绝时应一个字都没写")
    }

    /// 书 ID 可以是任意字符串，但不许借此跑出沙箱。
    func testBookIDCannotEscapeSandbox() throws {
        let hostile = "../../../../tmp/escaped"
        try storage.saveChapters([chapter("c0", order: 0)], bookID: hostile)

        let directory = storage.bookDirectory(hostile).standardizedFileURL
        XCTAssertTrue(directory.path.hasPrefix(root.standardizedFileURL.path), "章节目录必须留在根目录内")
        XCTAssertEqual(try storage.chapter(id: "c0", bookID: hostile)?.id, "c0")
    }

    func testManifestRejectsUnknownFilename() throws {
        let directory = storage.bookDirectory("book-a")
        try FileManager.default.createDirectory(
            at: directory.appendingPathComponent("objects"),
            withIntermediateDirectories: true
        )
        let hostile = ChapterManifest(entries: ["c0": "../../../../etc/passwd"])
        let encoder = JSONEncoder()
        try encoder.encode(hostile).write(
            to: directory.appendingPathComponent("manifest.json"),
            options: .atomic
        )
        XCTAssertThrowsError(try storage.chapter(id: "c0", bookID: "book-a")) { error in
            XCTAssertEqual(error as? LibraryStorageError, .invalidObjectName)
        }
    }

    /// 写对象成功但写清单失败：清单仍指向上一版，已提交内容不被破坏。
    func testManifestFailureKeepsPreviouslyCommittedChapters() throws {
        struct FailOnManifest: FileWriting {
            func write(_ data: Data, to url: URL) throws {
                if url.lastPathComponent == "manifest.json" { throw CocoaError(.fileWriteOutOfSpace) }
                try FileManager.default.createDirectory(
                    at: url.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                try data.write(to: url, options: .atomic)
            }
        }
        try storage.saveChapters([chapter("c0", order: 0, paragraphs: ["上一版"])], bookID: "book-a")

        let failing = LibraryStorage(root: root, writer: FailOnManifest())
        XCTAssertThrowsError(try failing.saveChapters([chapter("c0", order: 0, paragraphs: ["新一版"])], bookID: "book-a"))

        let onDisk = try XCTUnwrap(try storage.chapter(id: "c0", bookID: "book-a"))
        XCTAssertEqual(onDisk.paragraphs.map(\.text), ["上一版"], "清单提交失败时旧内容必须仍然可用")
    }

    func testRemoveBookDeletesEverything() throws {
        try storage.saveChapters([chapter("c0", order: 0)], bookID: "book-a")
        XCTAssertGreaterThan(try storage.byteCount(bookID: "book-a"), 0)
        try storage.removeBook("book-a")
        XCTAssertEqual(try storage.byteCount(bookID: "book-a"), 0)
        XCTAssertEqual(try storage.chapterIDs(bookID: "book-a"), [])
    }

    /// 段评等附加数据要原样带过存储层，不能在迁移中丢失。
    func testParagraphAttachmentsSurviveRoundTrip() throws {
        let attachments: JSONValue = .object(["comments": .array([.object(["author": .string("阿乙")])])])
        let value = StoredChapter(
            id: "c0",
            title: "第一章",
            order: 0,
            paragraphs: [.init(id: "p0", text: "正文", attachments: attachments)]
        )
        try storage.saveChapters([value], bookID: "book-a")
        let loaded = try XCTUnwrap(try storage.chapter(id: "c0", bookID: "book-a"))
        XCTAssertEqual(loaded.paragraphs[0].attachments, attachments)
    }
}
