import CoreText
import XCTest
@testable import YeHangCore

final class ChapterLayoutTests: XCTestCase {
    private func style(size: CGFloat = 18) -> PageTextStyle {
        PageTextStyle(
            font: CTFontCreateWithName("PingFang SC" as CFString, size, nil),
            extraLineSpacing: 6,
            paragraphSpacing: 12,
            firstLineIndent: size * 2
        )
    }

    private let chapter = [
        "　　夜色像一块浸了水的布，慢慢压在江面上。船篷下的灯芯爆了一下，又安静下来。",
        "　　他把书翻到中间，纸页发出干燥的响声。这一页讲的是如何在没有星光的夜里辨认方向。",
        "　　远处传来橹声，一下一下，像是有人在很慢地数数。"
    ]

    /// 分页必须完整覆盖整章：页与页首尾相接，拼回去等于原文。
    func testPagesCoverEveryCharacterWithoutOverlap() {
        for size in [CGSize(width: 310, height: 430), CGSize(width: 352, height: 550), CGSize(width: 740, height: 180)] {
            for fontSize in [16.0, 18.0, 24.0] as [CGFloat] {
                let layout = ChapterLayout(chapterID: "c1", paragraphs: chapter, style: style(size: fontSize))
                let pages = layout.pages(in: size)

                XCTAssertFalse(pages.isEmpty, "\(size) @\(fontSize) 应当至少有一页")
                var cursor = 0
                for page in pages {
                    XCTAssertEqual(page.range.location, cursor, "\(size) @\(fontSize) 页之间不允许有空洞")
                    XCTAssertGreaterThan(page.length, 0)
                    cursor += page.length
                }
                XCTAssertEqual(cursor, layout.attributedText.length, "\(size) @\(fontSize) 必须覆盖到最后一个字符")

                let rebuilt = pages
                    .map { (layout.attributedText.string as NSString).substring(with: $0.range) }
                    .joined()
                XCTAssertEqual(rebuilt, layout.attributedText.string)
            }
        }
    }

    /// 验收门：每一页画出来，能显示的字数必须等于这一页分配到的字数。
    /// 这正是 demo 里 73–339pt 文字溢出的防线。
    func testEveryPageFitsCompletelyWhenRendered() {
        for size in [CGSize(width: 310, height: 430), CGSize(width: 352, height: 550), CGSize(width: 740, height: 180)] {
            for fontSize in [16.0, 18.0, 24.0, 28.0] as [CGFloat] {
                let layout = ChapterLayout(chapterID: "c1", paragraphs: chapter, style: style(size: fontSize))
                for (index, page) in layout.pages(in: size).enumerated() {
                    XCTAssertFalse(page.overflows, "\(size) @\(fontSize) 第 \(index) 页不该溢出")
                    let slice = layout.attributedString(for: page)
                    let visible = ChapterLayout.visibleLength(of: slice, in: size)
                    XCTAssertEqual(visible, slice.length, "\(size) @\(fontSize) 第 \(index) 页有文字被裁掉")
                }
            }
        }
    }

    /// 跨页的续排段落不能带段首缩进，否则每页开头凭空多两格。
    func testContinuationPageDropsFirstLineIndent() {
        let long = String(repeating: "江水很静，船走得很慢。", count: 40)
        let layout = ChapterLayout(chapterID: "c1", paragraphs: [long], style: style())
        let pages = layout.pages(in: CGSize(width: 320, height: 260))
        XCTAssertGreaterThan(pages.count, 1)

        let first = layout.attributedString(for: pages[0])
        let second = layout.attributedString(for: pages[1])
        let firstIndent = (first.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle)?.firstLineHeadIndent
        let secondIndent = (second.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle)?.firstLineHeadIndent
        XCTAssertEqual(firstIndent ?? 0, 36, accuracy: 0.5)
        XCTAssertEqual(secondIndent ?? -1, 0, accuracy: 0.5)
    }

    /// 超长段落必须被切开，不能整段挤在一页里溢出。
    func testLongParagraphIsSplitAcrossPages() {
        let long = String(repeating: "字", count: 5_000)
        let layout = ChapterLayout(chapterID: "c1", paragraphs: [long], style: style())
        let pages = layout.pages(in: CGSize(width: 340, height: 500))
        XCTAssertGreaterThan(pages.count, 5)
        XCTAssertTrue(pages.allSatisfy { !$0.overflows })
    }

    // MARK: - 锚点

    func testAnchorRoundTripsThroughEveryParagraph() {
        let layout = ChapterLayout(chapterID: "c1", paragraphs: chapter, style: style())
        for index in chapter.indices {
            for offset in stride(from: 0, to: chapter[index].utf16.count, by: 3) {
                let anchor = ReaderAnchor(paragraphIndex: index, utf16Offset: offset)
                let chapterOffset = layout.chapterOffset(for: anchor)
                XCTAssertEqual(layout.anchor(atChapterOffset: chapterOffset), anchor)
            }
        }
    }

    func testAnchorFindsPageAndNeverFallsBackSilently() {
        let layout = ChapterLayout(chapterID: "c1", paragraphs: chapter, style: style())
        let pages = layout.pages(in: CGSize(width: 320, height: 700))
        let anchor = ReaderAnchor(paragraphIndex: 1, utf16Offset: 4)
        let page = layout.pageIndex(for: anchor, in: pages)
        XCTAssertNotNil(page)
        XCTAssertTrue(pages[page!].range.contains(layout.chapterOffset(for: anchor)))

        // 空页表不该猜出一个页码。
        XCTAssertNil(layout.pageIndex(for: anchor, in: []))
    }

    /// 锚点不能落在 emoji 中间，否则恢复时会切出半个字符。
    func testAnchorDoesNotSplitComposedCharacters() {
        let layout = ChapterLayout(chapterID: "c1", paragraphs: ["甲👩🏽‍🚀乙"], style: style())
        let anchor = layout.anchor(atChapterOffset: 2)
        XCTAssertEqual(anchor.paragraphIndex, 0)
        // 偏移 1/2/3 都落在同一个组合字符内部，必须收敛到它的起点 1。
        XCTAssertEqual(anchor.utf16Offset, 1)
    }
}
