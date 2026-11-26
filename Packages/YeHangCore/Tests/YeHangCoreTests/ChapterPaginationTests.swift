import CoreText
import XCTest
@testable import YeHangCore

final class ChapterPaginationTests: XCTestCase {
    private func style(_ size: CGFloat = 18) -> PageTextStyle {
        PageTextStyle(
            font: CTFontCreateWithName("PingFang SC" as CFString, size, nil),
            extraLineSpacing: 6,
            paragraphSpacing: 12,
            firstLineIndent: size * 2
        )
    }

    private func book() -> [ChapterText] {
        [
            ChapterText(
                id: "c1",
                title: "第一章 夜航",
                paragraphs: [
                    SourceParagraph(id: "p0", text: "　　夜色像一块浸了水的布，慢慢压在江面上。船篷下的灯芯爆了一下，又安静下来。"),
                    SourceParagraph(id: "p1", text: "　　他把书翻到中间，纸页发出干燥的响声。这一页讲的是如何在没有星光的夜里辨认方向。")
                ]
            ),
            ChapterText(
                id: "c2",
                title: "第二章 听橹",
                paragraphs: [
                    SourceParagraph(id: "p2", text: "　　远处传来橹声，一下一下，像是有人在很慢地数数。")
                ]
            )
        ]
    }

    func testPagesNeverSpanChapterBoundaries() {
        let chapters = book()
        // 故意用小视口，让每一章都分成多页，才能真正验证「不跨章」。
        let pages = ChapterPagination.pages(for: chapters, style: style(), size: CGSize(width: 320, height: 150))
        XCTAssertGreaterThan(pages.count, 2)
        XCTAssertGreaterThan(pages.filter { $0.chapterIndex == 0 }.count, 1, "第一章应被分成多页")

        // 每一页的章节归属必须单一，且章序号单调不减。
        var previousChapter = -1
        for page in pages {
            XCTAssertGreaterThanOrEqual(page.chapterIndex, previousChapter)
            previousChapter = page.chapterIndex
            XCTAssertEqual(Set(page.slices.map(\.paragraphIndex)).count, page.slices.count)
        }
        // 两章都要有页。
        XCTAssertEqual(Set(pages.map(\.chapterIndex)), [0, 1])
    }

    /// 章内页码必须从 0 开始连续递增，否则「第 n / m 页」会算错。
    func testPageIndexInChapterIsContiguous() {
        let pages = ChapterPagination.pages(for: book(), style: style(), size: CGSize(width: 320, height: 260))
        var expected: [Int: Int] = [:]
        for page in pages {
            let next = expected[page.chapterIndex, default: 0]
            XCTAssertEqual(page.pageIndexInChapter, next)
            expected[page.chapterIndex] = next + 1
        }
    }

    /// 每页拼起来的文字必须等于该章原文（跨页切开的段落也要能拼回去）。
    func testSlicesReconstructChapterText() {
        let chapters = book()
        let pages = ChapterPagination.pages(for: chapters, style: style(), size: CGSize(width: 320, height: 240))

        for (chapterIndex, chapter) in chapters.enumerated() {
            var rebuilt = [String](repeating: "", count: chapter.paragraphs.count)
            for page in pages where page.chapterIndex == chapterIndex {
                for slice in page.slices {
                    rebuilt[slice.paragraphIndex] += slice.text
                }
            }
            for (index, paragraph) in chapter.paragraphs.enumerated() {
                XCTAssertEqual(rebuilt[index], paragraph.text, "第 \(chapterIndex) 章第 \(index) 段拼不回原文")
            }
        }
    }

    /// 段评胶囊只该挂在段首，续排片段不能重复挂。
    func testContinuationSlicesAreMarkedSoCommentsAreNotDuplicated() {
        let long = String(repeating: "江水很静，船走得很慢。", count: 60)
        let chapters = [ChapterText(id: "c1", title: "第一章", paragraphs: [SourceParagraph(id: "p0", text: long)])]
        let pages = ChapterPagination.pages(for: chapters, style: style(), size: CGSize(width: 320, height: 200))
        XCTAssertGreaterThan(pages.count, 2)

        XCTAssertEqual(pages[0].slices.first?.range.location, 0)
        for page in pages.dropFirst() {
            let slice = page.slices.first
            XCTAssertEqual(slice?.isContinuation, true, "第二页起应是续排，不该带段首缩进也不该重复挂胶囊")
            XCTAssertEqual(slice?.startsParagraph, false)
        }
        // 除最后一页，前面每页都应有「后面还有」的标记。
        for page in pages.dropLast() {
            XCTAssertEqual(page.slices.last?.continuesOnNextPage, true)
        }
    }

    /// 页首锚点必须单调递增，二分查找才能用。
    func testPageAnchorsAreMonotonicWithinChapter() {
        let pages = ChapterPagination.pages(for: book(), style: style(), size: CGSize(width: 320, height: 240))
        for chapterIndex in Set(pages.map(\.chapterIndex)) {
            let anchors = pages.filter { $0.chapterIndex == chapterIndex }.map(\.anchor)
            XCTAssertEqual(anchors, anchors.sorted(), "章内页首锚点必须单调")
        }
    }

    /// 锚点 → 页：落在哪一页就该返回哪一页。
    func testAnchorFindsItsPage() {
        let chapters = book()
        let pages = ChapterPagination.pages(for: chapters, style: style(), size: CGSize(width: 320, height: 240))

        for (index, page) in pages.enumerated() {
            let found = ChapterPagination.pageIndex(for: page.anchor, inChapter: page.chapterIndex, of: pages)
            XCTAssertEqual(found, index)
        }
        // 锚点比该章所有页首锚点都靠前时，回退到该章第一页而不是 nil。
        let first = try? XCTUnwrap(pages.first { $0.chapterIndex == 1 })
        if let first {
            let before = ReaderAnchor(paragraphIndex: 0, utf16Offset: 0)
            XCTAssertEqual(ChapterPagination.pageIndex(for: before, inChapter: 1, of: pages), pages.firstIndex(of: first))
        }
        XCTAssertNil(ChapterPagination.pageIndex(for: ReaderAnchor(), inChapter: 99, of: pages))
    }

    /// 空章与空段落不能产生空页，也不能崩。
    func testEmptyChapterProducesNoPages() {
        let chapters = [
            ChapterText(id: "c0", title: "空章", paragraphs: []),
            ChapterText(id: "c1", title: "有字", paragraphs: [SourceParagraph(id: "p0", text: "有正文")])
        ]
        let pages = ChapterPagination.pages(for: chapters, style: style(), size: CGSize(width: 320, height: 240))
        XCTAssertEqual(pages.count, 1)
        XCTAssertEqual(pages[0].chapterIndex, 1)
    }

    /// 每一页都能拿到可用于绘制的富文本，且这一段文字与本页片段一致。
    func testRenderedPageTextMatchesSlices() {
        let chapters = book()
        let layout = ChapterLayout(chapterID: "c1", paragraphs: chapters[0].paragraphs.map(\.text), style: style())
        let pages = ChapterPagination.pages(for: chapters, style: style(), size: CGSize(width: 320, height: 240))
        for page in pages where page.chapterIndex == 0 {
            let range = NSRange(location: layout.chapterOffset(for: page.anchor),
                                length: 0)
            _ = range
            let attributed = layout.attributedString(
                for: PageRange(range: NSRange(
                    location: layout.chapterOffset(for: page.anchor),
                    length: pageLength(page, in: layout)
                ))
            )
            let expected = page.slices.map(\.text).joined(separator: "\n")
            XCTAssertEqual(normalize(attributed.string), normalize(expected))
        }
    }

    /// 页在整章里的字符长度：从本页锚点到下一章内页的锚点，末页到章尾。
    private func pageLength(_ page: ReadingPage, in layout: ChapterLayout) -> Int {
        let start = layout.chapterOffset(for: page.anchor)
        let end = page.slices.last.map { slice in
            let paragraphRange = layout.paragraphRanges[slice.paragraphIndex]
            return paragraphRange.location + NSMaxRange(slice.range)
        } ?? start
        return max(0, end - start)
    }

    private func normalize(_ text: String) -> String {
        text.replacingOccurrences(of: "\n", with: "")
    }
}
