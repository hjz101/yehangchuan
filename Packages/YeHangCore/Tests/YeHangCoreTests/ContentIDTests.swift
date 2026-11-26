import XCTest
@testable import YeHangCore

final class ContentIDTests: XCTestCase {
    /// 删掉一章开头的重复标题后，后面所有段落的 ID 必须原样不变。
    /// 这是书签、阅读位置在净化正文后仍然指得准的前提。
    func testParagraphIDsSurviveRemovingLeadingDuplicateTitle() {
        let body = ["第一章 夜航", "夜色像一块浸了水的布。", "他把书翻到中间。"]
        let cleaned = Array(body.dropFirst())
        let before = ContentID.paragraphIDs(chapterID: "c1", paragraphs: body)
        let after = ContentID.paragraphIDs(chapterID: "c1", paragraphs: cleaned)
        XCTAssertEqual(Array(before.dropFirst()), after)
    }

    func testIdenticalParagraphsStayDistinct() {
        let ids = ContentID.paragraphIDs(chapterID: "c1", paragraphs: ["相同", "相同", "相同"])
        XCTAssertEqual(Set(ids).count, 3)
    }

    func testInsertionDoesNotShiftExistingIDs() {
        let original = ["甲", "乙", "丙"]
        let changed = ["插入", "甲", "乙", "丙"]
        let before = ContentID.paragraphIDs(chapterID: "c1", paragraphs: original)
        let after = ContentID.paragraphIDs(chapterID: "c1", paragraphs: changed)
        XCTAssertEqual(before, Array(after.dropFirst()))
    }

    /// 不同章节的同名段落不能共用一个 ID，否则书签会跨章误命中。
    func testSameParagraphInDifferentChaptersDiffers() {
        let a = ContentID.paragraphIDs(chapterID: "c1", paragraphs: ["正文"])
        let b = ContentID.paragraphIDs(chapterID: "c2", paragraphs: ["正文"])
        XCTAssertNotEqual(a, b)
    }

    /// 组件拼接不允许歧义：["a:b","c"] 与 ["a","b:c"] 不能撞。
    func testDigestIsUnambiguousAcrossComponents() {
        XCTAssertNotEqual(
            ContentID.digest(components: ["a:b", "c"]),
            ContentID.digest(components: ["a", "b:c"])
        )
    }

    func testChapterIDIsStableForSameBook() {
        XCTAssertEqual(
            ContentID.chapter(bookID: "b1", index: 3, title: "第七章"),
            ContentID.chapter(bookID: "b1", index: 3, title: "第七章")
        )
        XCTAssertNotEqual(
            ContentID.chapter(bookID: "b1", index: 3, title: "第七章"),
            ContentID.chapter(bookID: "b2", index: 3, title: "第七章")
        )
    }
}
