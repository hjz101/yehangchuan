import CoreText
import XCTest
@testable import YeHangCore

final class ReadingProgressTests: XCTestCase {
    private func style() -> PageTextStyle {
        PageTextStyle(
            font: CTFontCreateWithName("PingFang SC" as CFString, 18, nil),
            extraLineSpacing: 6,
            paragraphSpacing: 12,
            firstLineIndent: 36
        )
    }

    private func book(chapters: Int, paragraphsPerChapter: Int = 3) -> [ChapterText] {
        (0..<chapters).map { chapter in
            ChapterText(
                id: "c\(chapter)",
                title: "第 \(chapter + 1) 章",
                paragraphs: (0..<paragraphsPerChapter).map {
                    SourceParagraph(
                        id: "c\(chapter)-p\($0)",
                        text: String(repeating: "江水很静，船走得很慢。", count: 12)
                    )
                }
            )
        }
    }

    /// 进度必须随翻页单调不减，否则进度条会往回跳。
    func testProgressIsMonotonic() {
        let pages = ChapterPagination.pages(
            for: book(chapters: 4), style: style(), size: CGSize(width: 320, height: 260)
        )
        XCTAssertGreaterThan(pages.count, 8)

        var previous = -1.0
        for index in pages.indices {
            let value = ReadingProgress.fraction(at: index, of: pages, chapterCount: 4)
            XCTAssertGreaterThanOrEqual(value, previous, "第 \(index) 页的进度比上一页小")
            previous = value
        }
    }

    /// 分母是目录章数，不是当前排好版的章数。
    /// 在线书只拉到第一章时，读到第一章末尾也绝不能显示「已读 100%」。
    func testOnlyFirstChapterLoadedStillReadsLow() {
        let partial = ChapterPagination.pages(
            for: book(chapters: 1, paragraphsPerChapter: 6),
            style: style(),
            size: CGSize(width: 320, height: 260)
        )
        let last = partial.count - 1
        let value = ReadingProgress.fraction(at: last, of: partial, chapterCount: 400)
        XCTAssertLessThan(value, 0.01, "只读了 400 章里的第一章，进度必须接近 0")
    }

    /// 目录章数未知时不编造百分比。
    func testUnknownChapterCountReportsZero() {
        let pages = ChapterPagination.pages(
            for: book(chapters: 2), style: style(), size: CGSize(width: 320, height: 260)
        )
        XCTAssertEqual(ReadingProgress.fraction(at: 0, of: pages, chapterCount: 0), 0)
    }

    /// 读完最后一页也不是 100%：那要用户自己点「读完」。
    func testProgressNeverReachesOne() {
        let pages = ChapterPagination.pages(
            for: book(chapters: 3), style: style(), size: CGSize(width: 320, height: 260)
        )
        let value = ReadingProgress.fraction(at: pages.count - 1, of: pages, chapterCount: 3)
        XCTAssertLessThanOrEqual(value, 0.99)
        XCTAssertGreaterThan(value, 0.9, "读完最后一章应当接近满")
    }

    /// 反向定位：百分比 → 页。用于锚点失效后的兜底。
    func testNearestPageRoundTrips() {
        let pages = ChapterPagination.pages(
            for: book(chapters: 5), style: style(), size: CGSize(width: 320, height: 260)
        )
        for index in pages.indices {
            let fraction = ReadingProgress.fraction(at: index, of: pages, chapterCount: 5)
            let found = ReadingProgress.pageIndex(nearest: fraction, in: pages, chapterCount: 5)
            XCTAssertEqual(found, index, "第 \(index) 页的进度应能找回同一页")
        }
    }

    func testNearestPageReturnsNilWithoutData() {
        XCTAssertNil(ReadingProgress.pageIndex(nearest: 0.5, in: [], chapterCount: 3))
        let pages = ChapterPagination.pages(
            for: book(chapters: 1), style: style(), size: CGSize(width: 320, height: 600)
        )
        XCTAssertNil(ReadingProgress.pageIndex(nearest: 0.5, in: pages, chapterCount: 0))
    }

    /// 越界的页下标不能崩，也不能给出离谱的值。
    func testOutOfRangeIndexIsSafe() {
        let pages = ChapterPagination.pages(
            for: book(chapters: 2), style: style(), size: CGSize(width: 320, height: 260)
        )
        XCTAssertEqual(ReadingProgress.fraction(at: -1, of: pages, chapterCount: 2), 0)
        XCTAssertEqual(ReadingProgress.fraction(at: 9_999, of: pages, chapterCount: 2), 0)
    }
}
