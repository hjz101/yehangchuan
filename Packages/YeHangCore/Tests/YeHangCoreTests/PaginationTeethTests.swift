import CoreText
import XCTest
@testable import YeHangCore

/// 反证测试：证明上面那套「页必须装得下」的断言不是空断言。
///
/// 如果度量本身是坏的（永远返回「装得下」），
/// `ChapterLayoutTests.testEveryPageFitsCompletelyWhenRendered` 就会永远绿，
/// 等于没有防线。这里故意构造装不下的情形，确认它能被抓到。
final class PaginationTeethTests: XCTestCase {
    private func style(size: CGFloat = 18) -> PageTextStyle {
        PageTextStyle(font: CTFontCreateWithName("PingFang SC" as CFString, size, nil))
    }

    /// 整章塞进一小块区域，可见字符数必须显著少于总字符数。
    /// 若度量返回满长，说明 `CTFrameGetVisibleStringRange` 没起作用。
    func testMeasurementDetectsOverflow() {
        let paragraph = String(repeating: "夜色像一块浸了水的布，慢慢压在江面上。", count: 200)
        let layout = ChapterLayout(chapterID: "c1", paragraphs: [paragraph], style: style())
        let small = CGSize(width: 200, height: 120)
        let visible = ChapterLayout.visibleLength(of: layout.attributedText, in: small)

        XCTAssertGreaterThan(layout.attributedText.length, 1_000)
        XCTAssertGreaterThan(visible, 0, "至少能放下几个字才算度量正常")
        XCTAssertLessThan(visible, layout.attributedText.length, "整章不该全部装进一小块区域")
    }

    /// 屏幕越大、字号越小，页数必须越少；反之越多。
    /// 若分页退化成「一章一页」，这条会失败。
    func testPageCountRespondsToViewportAndFontSize() {
        let paragraph = String(repeating: "江水很静，船走得很慢。", count: 120)
        func count(_ size: CGSize, _ fontSize: CGFloat) -> Int {
            ChapterLayout(chapterID: "c", paragraphs: [paragraph], style: style(size: fontSize))
                .pages(in: size)
                .count
        }
        let phone = count(CGSize(width: 350, height: 600), 18)
        let tall = count(CGSize(width: 350, height: 900), 18)
        let bigFont = count(CGSize(width: 350, height: 600), 28)

        XCTAssertGreaterThan(phone, 1, "长文本必须分成多页")
        XCTAssertLessThanOrEqual(tall, phone, "更高的屏不该分出更多页")
        XCTAssertGreaterThan(bigFont, phone, "更大的字号必须分出更多页")
    }

    /// 可用高度连一行都放不下时，必须如实标 overflows，
    /// 而不是悄悄丢字或返回空页。
    func testImpossibleViewportReportsOverflowInsteadOfLosingText() {
        let layout = ChapterLayout(chapterID: "c1", paragraphs: ["一二三四五六七八九十"], style: style(size: 20))
        let pages = layout.pages(in: CGSize(width: 100, height: 1))
        XCTAssertEqual(pages.count, 1)
        XCTAssertTrue(pages[0].overflows, "装不下时必须标记溢出")
        XCTAssertEqual(pages[0].range, NSRange(location: 0, length: layout.attributedText.length), "溢出也不能丢字")
    }
}
