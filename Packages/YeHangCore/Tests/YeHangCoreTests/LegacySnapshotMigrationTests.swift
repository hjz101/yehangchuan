import Foundation
import XCTest
@testable import YeHangCore

final class LegacySnapshotMigrationTests: XCTestCase {
    private func legacySnapshot(customChapters: String = "{}") -> Data {
        Data("""
        {
          "books": [{"id": "b1", "title": "夜航船", "progress": 0.42}],
          "sources": [],
          "excerpts": [],
          "settings": {"fontSize": 18},
          "goalMinutes": 60,
          "appearance": "深色",
          "bookmarks": [],
          "positions": {},
          "groups": ["夜读"],
          "customChapters": \(customChapters),
          "eyeCare": {}
        }
        """.utf8)
    }

    private func auditChapterJSON() -> String {
        """
        {
          "b1": [
            {
              "id": "c1",
              "title": "第一章 夜航",
              "paragraphs": [
                {"id": "c1-p0", "text": "夜色像一块浸了水的布。"},
                {"id": "c1-p1", "text": "他把书翻到中间。", "comments": [{"id": "m1", "author": "阿乙", "text": "好句"}]}
              ]
            },
            {
              "id": "c2",
              "title": "第二章 听橹",
              "paragraphs": [{"id": "c2-p0", "text": "远处传来橹声。"}]
            }
          ]
        }
        """
    }

    /// 迁移后：正文从索引里消失，章节进独立结构，其余分区一个字段不丢。
    func testMigrationMovesChaptersOutOfIndexAndKeepsEveryOtherSection() throws {
        let result = try LegacySnapshotMigration.migrate(legacySnapshot(customChapters: auditChapterJSON()))

        XCTAssertNil(result.index.sections["customChapters"], "正文不许留在索引里")
        XCTAssertNotNil(result.index.sections["books"])
        XCTAssertNotNil(result.index.sections["settings"])
        XCTAssertNotNil(result.index.sections["eyeCare"])
        XCTAssertEqual(result.index.version, LibraryIndex.currentVersion)
        XCTAssertEqual(result.index.booksWithChapters, ["b1"])
        XCTAssertEqual(result.chapters["b1"]?.count, 2)
        XCTAssertTrue(result.warnings.isEmpty)
    }

    /// 段落 ID 必须换成内容寻址的形式，且旧 ID 能映射到新 ID。
    func testParagraphIDsBecomeContentAddressedAndOldOnesAreMapped() throws {
        let result = try LegacySnapshotMigration.migrate(legacySnapshot(customChapters: auditChapterJSON()))
        let chapters = try XCTUnwrap(result.chapters["b1"])
        let ids = chapters[0].paragraphs.map(\.id)

        XCTAssertEqual(ids, ContentID.paragraphIDs(chapterID: "c1", paragraphs: ["夜色像一块浸了水的布。", "他把书翻到中间。"]))
        XCTAssertNotEqual(ids, ["c1-p0", "c1-p1"], "不再是索引派生")

        let map = try XCTUnwrap(result.paragraphIDMap["b1"])
        XCTAssertEqual(map["c1-p0"], ids[0])
        XCTAssertEqual(map["c1-p1"], ids[1])
    }

    /// 段评等附加数据不能在迁移里丢掉。
    func testParagraphCommentsSurviveMigration() throws {
        let result = try LegacySnapshotMigration.migrate(legacySnapshot(customChapters: auditChapterJSON()))
        let paragraph = try XCTUnwrap(result.chapters["b1"]?[0].paragraphs[1])
        let comments = paragraph.attachments?["comments"]?.arrayValue
        XCTAssertEqual(comments?.count, 1)
        XCTAssertEqual(comments?.first?["author"]?.stringValue, "阿乙")
    }

    /// 迁移 + 落盘 + 重读：整条链要能跑通。
    func testMigratedLibraryRoundTripsThroughStorage() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("yh-migrate-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let storage = LibraryStorage(root: root)

        let result = try LegacySnapshotMigration.migrate(legacySnapshot(customChapters: auditChapterJSON()))
        try storage.saveIndex(result.index)
        for (bookID, chapters) in result.chapters {
            try storage.saveChapters(chapters, bookID: bookID)
        }

        let index = try XCTUnwrap(try storage.loadIndex())
        XCTAssertNil(index.sections["customChapters"])
        let loaded = try storage.chapters(bookID: "b1")
        XCTAssertEqual(loaded.map(\.title), ["第一章 夜航", "第二章 听橹"])
        XCTAssertEqual(loaded[0].paragraphs.map(\.text), ["夜色像一块浸了水的布。", "他把书翻到中间。"])
    }

    /// 书签与阅读位置里的旧段落 ID 要重写；指不到的留空退化成「本章开头」。
    /// 更重要的是：重写时不能把同一对象里别的字段（offset / chapterTitle /
    /// progress / 未认识的未来字段）一起丢掉。
    func testAnchorIDsAreRemappedAndUnmappableOnesAreCleared() throws {
        let data = Data("""
        {
          "positions": {
            "b1": {"bookID": "b1", "chapterTitle": "第一章 夜航", "paragraphID": "c1-p1",
                   "offset": 3, "progress": 0.42, "updatedAt": "2026-11-01T10:00:00Z"}
          },
          "bookmarks": [
            {"id": "m1", "bookID": "b1", "bookTitle": "夜航船", "chapterTitle": "第一章 夜航",
             "pageIndex": 7, "progress": 0.3, "paragraphID": "c1-p0", "offset": 9},
            {"id": "m2", "bookID": "b1", "chapterTitle": "第一章 夜航", "pageIndex": 2, "paragraphID": "c9-p9"}
          ],
          "customChapters": \(auditChapterJSON())
        }
        """.utf8)

        var result = try LegacySnapshotMigration.migrate(data)
        var warnings: [String] = []
        try LegacySnapshotMigration.remapAnchorIDs(
            in: &result.index,
            using: result.paragraphIDMap,
            warnings: &warnings
        )

        let expectedIDs = ContentID.paragraphIDs(
            chapterID: "c1",
            paragraphs: ["夜色像一块浸了水的布。", "他把书翻到中间。"]
        )

        let position = try XCTUnwrap(result.index.sections["positions"]?["b1"]?.objectValue)
        XCTAssertEqual(position["paragraphID"]?.stringValue, expectedIDs[1])
        // 未被迁移触碰的字段必须原样还在。
        XCTAssertEqual(position["offset"]?.intValue, 3)
        XCTAssertEqual(position["chapterTitle"]?.stringValue, "第一章 夜航")
        XCTAssertEqual(position["progress"]?.doubleValue, 0.42)
        XCTAssertEqual(position["updatedAt"]?.stringValue, "2026-11-01T10:00:00Z")

        let bookmarks = try XCTUnwrap(result.index.sections["bookmarks"]?.arrayValue)
        XCTAssertEqual(bookmarks[0]["paragraphID"]?.stringValue, expectedIDs[0])
        XCTAssertEqual(bookmarks[0]["pageIndex"]?.intValue, 7, "书签的页序号不能被迁移改掉")
        XCTAssertEqual(bookmarks[0]["offset"]?.intValue, 9)
        XCTAssertNil(bookmarks[1]["paragraphID"], "映射不到的书签要删掉锚点，而不是留个假 ID")
        XCTAssertEqual(bookmarks[1]["pageIndex"]?.intValue, 2, "删锚点不等于删书签")

        XCTAssertEqual(warnings.count, 1)
        XCTAssertTrue(warnings[0].contains("书签"))
    }

    /// 已经是新格式的输入再跑一次迁移不该二次搬移。
    func testMigratingAnAlreadyMigratedFileIsIdempotent() throws {
        let first = try LegacySnapshotMigration.migrate(legacySnapshot(customChapters: auditChapterJSON()))
        var sections = first.index.sections
        sections["version"] = .number(Double(LibraryIndex.currentVersion))
        sections["booksWithChapters"] = .array([.string("b1")])
        let encoded = try JSONEncoder().encode(JSONValue.object(sections))

        let second = try LegacySnapshotMigration.migrate(encoded)
        XCTAssertTrue(second.chapters.isEmpty, "新格式里没有 customChapters，不该再搬一次")
        XCTAssertEqual(second.index.booksWithChapters, ["b1"], "已有清单要保留")
        XCTAssertEqual(second.index.version, LibraryIndex.currentVersion)
    }

    func testFutureVersionIsRejected() throws {
        let data = Data(#"{"version": 99, "books": []}"#.utf8)
        XCTAssertThrowsError(try LegacySnapshotMigration.migrate(data)) { error in
            XCTAssertEqual(error as? MigrationError, .fromFuture(99))
        }
    }

    func testUnreadableDataThrowsInsteadOfSilentlyReturningEmpty() throws {
        XCTAssertThrowsError(try LegacySnapshotMigration.migrate(Data("<html>".utf8))) { error in
            XCTAssertEqual(error as? MigrationError, .unreadable)
        }
    }

    /// 章节数据坏掉时必须报错，而不是迁移出一个空书架把用户书库抹掉。
    func testMalformedChaptersAbortInsteadOfProducingEmptyLibrary() throws {
        let data = legacySnapshot(customChapters: #"{"b1": "这不是数组"}"#)
        XCTAssertThrowsError(try LegacySnapshotMigration.migrate(data)) { error in
            guard case .noUsableChapters = error as? MigrationError else {
                return XCTFail("应报 noUsableChapters，实际：\(error)")
            }
        }
    }
}
