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

    // MARK: - 命中与行片段

    /// 长按选字：点在某一行上，命中的字符必须落在这一行里。
    /// 这是段评、摘录、查词共用的入口，错一个字就会引错整段。
    func testHitTestReturnsCharacterInsideTappedLine() throws {
        let layout = ChapterLayout(chapterID: "c1", paragraphs: chapter, style: style())
        let size = CGSize(width: 320, height: 500)
        let pages = layout.pages(in: size)
        let page = try XCTUnwrap(pages.first)
        let fragments = layout.paragraphBoxes(in: page, size: size)
        let line = try XCTUnwrap(fragments.first)

        let point = CGPoint(x: line.frame.minX + 2, y: line.firstLine.midY)
        let offset = try XCTUnwrap(layout.chapterOffset(at: point, in: page, size: size))
        XCTAssertTrue(page.range.contains(offset), "命中的字符必须在本页范围内")

        // 命中的字要落回这一行：用返回的偏移重新算锚点，段落应当一致。
        XCTAssertEqual(layout.anchor(atChapterOffset: offset).paragraphIndex, line.paragraphIndex)
    }

    /// 点在正文下方的空白处，应当归到最近的最后一行，而不是返回「没点到」。
    func testHitTestBelowTextSnapsToNearestLine() throws {
        let layout = ChapterLayout(chapterID: "c1", paragraphs: chapter, style: style())
        let size = CGSize(width: 320, height: 700)
        let page = try XCTUnwrap(layout.pages(in: size).first)

        let offset = try XCTUnwrap(layout.chapterOffset(at: CGPoint(x: 40, y: 690), in: page, size: size))
        XCTAssertTrue(page.range.contains(offset))
    }

    /// 每个段落的标注只挂一次，且挂在它在**本页**的第一行上。
    /// 同一段跨页续排时，下一页也要有自己的首行片段。
    func testParagraphFragmentsAppearOncePerPage() throws {
        let long = String(repeating: "江水很静，船走得很慢。", count: 40)
        let layout = ChapterLayout(chapterID: "c1", paragraphs: [long], style: style())
        let size = CGSize(width: 320, height: 300)
        let pages = layout.pages(in: size)
        XCTAssertGreaterThan(pages.count, 2)

        for (index, page) in pages.enumerated() {
            let fragments = layout.paragraphBoxes(in: page, size: size)
            XCTAssertEqual(fragments.count, 1, "第 \(index) 页只有一个段落的片段")
            XCTAssertEqual(fragments[0].paragraphIndex, 0)
            XCTAssertGreaterThan(fragments[0].firstLine.height, 0)
        }
    }

    /// 多个段落时，片段的纵向位置必须递增 —— 界面按它摆放标注，
    /// 顺序反了标注就会上下乱跳。
    func testParagraphFragmentsAreOrderedTopToBottom() throws {
        let layout = ChapterLayout(chapterID: "c1", paragraphs: chapter, style: style())
        let size = CGSize(width: 320, height: 700)
        let page = try XCTUnwrap(layout.pages(in: size).first)
        let fragments = layout.paragraphBoxes(in: page, size: size)

        XCTAssertEqual(fragments.map(\.paragraphIndex), fragments.map(\.paragraphIndex).sorted())
        let tops = fragments.map(\.firstLine.minY)
        XCTAssertEqual(tops, tops.sorted(), "片段必须从上到下排列")
    }
}
