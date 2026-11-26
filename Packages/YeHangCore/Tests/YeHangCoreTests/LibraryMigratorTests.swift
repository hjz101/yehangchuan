import Foundation
import XCTest
@testable import YeHangCore

final class LibraryMigratorTests: XCTestCase {
    private var root: URL!
    private var storage: LibraryStorage!
    private var legacyURL: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("yh-migrator-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        storage = LibraryStorage(root: root)
        legacyURL = root.appendingPathComponent("snapshot.json")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
        try super.tearDownWithError()
    }

    private func writeLegacySnapshot(chapters: String? = nil, positions: String = "{}", bookmarks: String = "[]") throws {
        let body = chapters ?? """
        {
          "b1": [{
            "id": "c1",
            "title": "第一章 夜航",
            "paragraphs": [
              {"id": "c1-p0", "text": "夜色像一块浸了水的布。"},
              {"id": "c1-p1", "text": "他把书翻到中间。", "comments": [{"id": "m1", "author": "阿乙", "text": "好句"}]}
            ]
          }]
        }
        """
        let json = """
        {
          "books": [{"id": "b1", "title": "夜航船", "progress": 0.42}],
          "sources": [],
          "excerpts": [],
          "settings": {"fontSize": 18},
          "goalMinutes": 60,
          "appearance": "深色",
          "bookmarks": \(bookmarks),
          "positions": \(positions),
          "groups": ["夜读"],
          "customChapters": \(body),
          "eyeCare": {}
        }
        """
        try Data(json.utf8).write(to: legacyURL)
    }

    // MARK: 主路径

    func testMigrationMovesEverythingAndArchivesLegacyFile() throws {
        try writeLegacySnapshot()
        let report = try LibraryMigrator.migrate(
            legacyURL: legacyURL,
            storage: storage,
            now: Date(timeIntervalSince1970: 1_700_000_000)
        )

        XCTAssertTrue(report.didRun)
        XCTAssertEqual(report.bookCount, 1)
        XCTAssertEqual(report.chapterCount, 1)
        XCTAssertEqual(report.paragraphCount, 2)
        XCTAssertTrue(report.warnings.isEmpty)

        // 旧文件必须改名留档，而不是被删。
        XCTAssertFalse(FileManager.default.fileExists(atPath: legacyURL.path))
        let archived = try XCTUnwrap(report.archivedFile)
        XCTAssertTrue(FileManager.default.fileExists(atPath: archived.path))
        XCTAssertTrue(archived.lastPathComponent.contains("1700000000"))

        // 新结构读得回来。
        let index = try XCTUnwrap(try storage.loadIndex())
        XCTAssertEqual(index.booksWithChapters, ["b1"])
        XCTAssertNil(index.sections["customChapters"])
        let chapters = try storage.chapters(bookID: "b1")
        XCTAssertEqual(chapters.count, 1)
        XCTAssertEqual(chapters[0].paragraphs.map(\.text), ["夜色像一块浸了水的布。", "他把书翻到中间。"])
        // 段评要活着。
        XCTAssertNotNil(chapters[0].paragraphs[1].attachments)
    }

    /// 索引里的书签与阅读位置必须同步换成新的内容寻址 ID，
    /// 否则下一步切读写路径后，所有书签都会指向不存在的段落。
    func testAnchorIDsInIndexAreRewrittenToContentAddressedIDs() throws {
        try writeLegacySnapshot(positions: """
        {"b1": {"bookID": "b1", "chapterTitle": "第一章 夜航", "paragraphID": "c1-p1",
                "offset": 4, "progress": 0.42}}
        """, bookmarks: """
        [{"id": "m1", "bookID": "b1", "chapterTitle": "第一章 夜航",
          "pageIndex": 3, "paragraphID": "c1-p0"},
         {"id": "m2", "bookID": "b1", "pageIndex": 1, "paragraphID": "gone-p0"}]
        """)

        let report = try LibraryMigrator.migrate(legacyURL: legacyURL, storage: storage)
        XCTAssertTrue(report.didRun)

        let expected = ContentID.paragraphIDs(
            chapterID: "c1",
            paragraphs: ["夜色像一块浸了水的布。", "他把书翻到中间。"]
        )
        let index = try XCTUnwrap(try storage.loadIndex())
        let position = try XCTUnwrap(index.sections["positions"]?["b1"]?.objectValue)
        XCTAssertEqual(position["paragraphID"]?.stringValue, expected[1])
        XCTAssertEqual(position["offset"]?.intValue, 4, "改写锚点不能碰 offset")
        XCTAssertEqual(position["chapterTitle"]?.stringValue, "第一章 夜航")

        let bookmarks = try XCTUnwrap(index.sections["bookmarks"]?.arrayValue)
        XCTAssertEqual(bookmarks[0]["paragraphID"]?.stringValue, expected[0])
        XCTAssertEqual(bookmarks[0]["pageIndex"]?.intValue, 3)
        XCTAssertNil(bookmarks[1]["paragraphID"], "指不到的锚点要删掉，而不是留个假 ID")
        XCTAssertEqual(bookmarks[1]["pageIndex"]?.intValue, 1, "删锚点不等于删书签")
        XCTAssertTrue(report.warnings.contains { $0.contains("书签") })
    }

    /// 迁移后写状态文件，第二次启动必须跳过，不能重复搬、堆一堆留档。
    func testSecondRunIsSkipped() throws {
        try writeLegacySnapshot()
        let first = try LibraryMigrator.migrate(legacyURL: legacyURL, storage: storage)
        XCTAssertTrue(first.didRun)

        // 模拟「用户后来又存了一次旧快照」，文件又出现了。
        try writeLegacySnapshot()
        let second = try LibraryMigrator.migrate(legacyURL: legacyURL, storage: storage)
        XCTAssertFalse(second.didRun, "已迁移过就不该再搬一遍")
        XCTAssertTrue(second.message.contains("跳过"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: legacyURL.path), "跳过时不该动旧文件")

        let state = try XCTUnwrap(LibraryMigrator.loadState(root: root))
        XCTAssertEqual(state.chapterCount, 1)
    }

    /// 搬家规则升级（migrationVersion 变大）后要能重搬。
    func testNewerMigrationVersionRunsAgain() throws {
        try writeLegacySnapshot()
        try LibraryMigrator.migrate(legacyURL: legacyURL, storage: storage)

        var state = try XCTUnwrap(LibraryMigrator.loadState(root: root))
        state.migrationVersion = 0
        try JSONEncoder().encode(state).write(to: LibraryMigrator.stateURL(root: root), options: .atomic)

        let again = try LibraryMigrator.migrate(legacyURL: legacyURL, storage: storage)
        XCTAssertFalse(again.didRun, "旧文件已经不在了，没有可搬的东西")
    }

    func testNoLegacyFileMeansNoWork() throws {
        let report = try LibraryMigrator.migrate(legacyURL: legacyURL, storage: storage)
        XCTAssertFalse(report.didRun)
        XCTAssertTrue(report.message.contains("无需迁移"))
        XCTAssertNil(try storage.loadIndex())
    }

    // MARK: 失败路径 —— 必须「旧文件保留、仍在原处」

    /// 迁移内容对不上时（这里用坏章节数据触发），旧文件不能被改名。
    func testFailedMigrationKeepsLegacyFileInPlace() throws {
        try writeLegacySnapshot(chapters: #"{"b1": "这不是数组"}"#)
        XCTAssertThrowsError(try LibraryMigrator.migrate(legacyURL: legacyURL, storage: storage))

        XCTAssertTrue(FileManager.default.fileExists(atPath: legacyURL.path), "迁移失败时旧文件必须原地保留")
        XCTAssertNil(LibraryMigrator.loadState(root: root), "失败时不该写迁移状态")
    }

    /// 索引写不进去时也要保留旧文件。
    func testIndexWriteFailureKeepsLegacyFile() throws {
        try writeLegacySnapshot()
        let failing = LibraryStorage(root: root, writer: FailOnIndex())
        // 先让章节能写（换一个不出错的 storage 写章节）
        let result = try LegacySnapshotMigration.migrate(Data(contentsOf: legacyURL))
        for (bookID, chapters) in result.chapters {
            try storage.saveChapters(chapters, bookID: bookID)
        }

        XCTAssertThrowsError(try LibraryMigrator.migrate(legacyURL: legacyURL, storage: failing, force: true))
        XCTAssertTrue(FileManager.default.fileExists(atPath: legacyURL.path))
        XCTAssertNil(LibraryMigrator.loadState(root: root))
    }

    private struct FailOnIndex: FileWriting {
        func write(_ data: Data, to url: URL) throws {
            if url.lastPathComponent == "library.json" { throw CocoaError(.fileWriteOutOfSpace) }
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try data.write(to: url, options: .atomic)
        }
    }

    /// 旧文件是坏 JSON 时也不能删它 —— 那是用户书库的最后一copy。
    func testCorruptLegacyFileIsPreserved() throws {
        try Data("<html>不是书架</html>".utf8).write(to: legacyURL)
        XCTAssertThrowsError(try LibraryMigrator.migrate(legacyURL: legacyURL, storage: storage))
        XCTAssertTrue(FileManager.default.fileExists(atPath: legacyURL.path))
        XCTAssertEqual(try Data(contentsOf: legacyURL), Data("<html>不是书架</html>".utf8))
    }

    // MARK: 与旧读路径的兼容

    /// 迁移后旧路径（读留档文件）仍然能读到完整书库 —— 这是「第一步不动读写」
    /// 的全部前提：哪怕新结构写坏了，用户的架子和正文都还在。
    func testArchivedFileStaysReadableByLegacyDecoder() throws {
        try writeLegacySnapshot()
        let report = try LibraryMigrator.migrate(legacyURL: legacyURL, storage: storage)
        let archived = try XCTUnwrap(report.archivedFile)

        let data = try Data(contentsOf: archived)
        let value = try JSONDecoder().decode(JSONValue.self, from: data)
        let sections = try XCTUnwrap(value.objectValue)
        XCTAssertEqual(sections["books"]?.arrayValue?.count, 1)
        XCTAssertEqual(sections["customChapters"]?.objectValue?.count, 1)
        XCTAssertEqual(sections["goalMinutes"]?.intValue, 60)
    }
}
