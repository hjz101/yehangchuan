import Foundation
import XCTest
@testable import YeHangCore

/// 跨章翻页与缓存策略的回归：这两件事错了，读者看到的是空白页、
/// 跳到别的章，或者改字号后页表被旧缓存污染。
final class PageIndexTests: XCTestCase {
    private func page(chapterID: String, index: Int, chapterIndex: Int = 0) -> ReadingPage {
        ReadingPage(
            chapterIndex: chapterIndex,
            pageIndexInChapter: index,
            chapterID: chapterID,
            chapterTitle: chapterID,
            slices: [],
            anchor: ReaderAnchor(),
            chapterRange: NSRange(location: 0, length: 10),
            overflows: false
        )
    }

    func testCountsPagesPerChapter() {
        let pages = [
            page(chapterID: "a", index: 0),
            page(chapterID: "a", index: 1),
            page(chapterID: "b", index: 0, chapterIndex: 1)
        ]
        let index = PageIndex(pages: pages, chapterIDs: ["a", "b"])
        XCTAssertEqual(index.chapterPageCounts["a"], 2)
        XCTAssertEqual(index.chapterPageCounts["b"], 1)
        XCTAssertNil(index.chapterPageCounts["missing"])
    }

    func testPageAtOutOfRangeReturnsNil() {
        let index = PageIndex(pages: [page(chapterID: "a", index: 0)], chapterIDs: ["a"])
        XCTAssertNil(index.page(at: -1))
        XCTAssertNotNil(index.page(at: 0))
        XCTAssertNil(index.page(at: 1))
    }

    func testDuplicateChapterIDResolvesToFirstOccurrence() {
        let index = PageIndex(pages: [], chapterIDs: ["a", "b", "a"])
        XCTAssertEqual(index.chapterIndex(for: "a"), 0)
        XCTAssertEqual(index.chapterIndex(for: "b"), 1)
        XCTAssertNil(index.chapterIndex(for: "z"))
    }

    func testCacheEvictsWholeStorageWhenFull() {
        var cache = PageCache<Int>()
        for i in 0..<PageCachePolicy.capacity { cache.store(i, for: "k\(i)") }
        XCTAssertEqual(cache.value(for: "k0"), 0)
        cache.store(99, for: "new")
        XCTAssertNil(cache.value(for: "k0"), "容量满后应整体清空，而不是逐条淘汰")
        XCTAssertEqual(cache.value(for: "new"), 99)
    }

    func testCacheReturnsNilAfterRemoveAll() {
        var cache = PageCache<String>()
        cache.store("value", for: "key")
        XCTAssertEqual(cache.value(for: "key"), "value")
        cache.removeAll()
        XCTAssertNil(cache.value(for: "key"))
    }
}
