import CoreGraphics
import XCTest
@testable import YeHangCore

/// 长按选中哪一段：这条规则过去只写在界面层，`swift test` 碰不到，
/// 模拟器上又没法注入长按，等于整条 CoreText 链路唯一没有防线的一环。
/// 这里把它钉住：点在段上就选那一段，点在空隙里就归最近的那一段。
final class ParagraphHitTestingTests: XCTestCase {
    private func boxes() -> [PageParagraphBox] {
        [
            PageParagraphBox(
                paragraphIndex: 0,
                frame: CGRect(x: 0, y: 0, width: 300, height: 100),
                firstLine: CGRect(x: 0, y: 0, width: 300, height: 20),
                lastLine: CGRect(x: 0, y: 80, width: 300, height: 20)
            ),
            PageParagraphBox(
                paragraphIndex: 1,
                frame: CGRect(x: 0, y: 120, width: 300, height: 40),
                firstLine: CGRect(x: 0, y: 120, width: 300, height: 20),
                lastLine: CGRect(x: 0, y: 140, width: 300, height: 20)
            ),
            PageParagraphBox(
                paragraphIndex: 2,
                frame: CGRect(x: 0, y: 200, width: 300, height: 40),
                firstLine: CGRect(x: 0, y: 200, width: 300, height: 20),
                lastLine: CGRect(x: 0, y: 220, width: 300, height: 20)
            )
        ]
    }

    func testPointInsideBoxHitsThatParagraph() {
        XCTAssertEqual(ParagraphHitTesting.index(at: CGPoint(x: 10, y: 10), among: boxes()), 0)
        XCTAssertEqual(ParagraphHitTesting.index(at: CGPoint(x: 10, y: 130), among: boxes()), 1)
        XCTAssertEqual(ParagraphHitTesting.index(at: CGPoint(x: 10, y: 220), among: boxes()), 2)
    }

    /// 段落之间 20pt 的空隙：落在上半截归上一段，下半截归下一段。
    /// 不能因为差几个像素就什么都不选。
    func testPointInGapSnapsToNearestParagraph() {
        XCTAssertEqual(ParagraphHitTesting.index(at: CGPoint(x: 10, y: 105), among: boxes()), 0)
        XCTAssertEqual(ParagraphHitTesting.index(at: CGPoint(x: 10, y: 115), among: boxes()), 1)
        XCTAssertEqual(ParagraphHitTesting.index(at: CGPoint(x: 10, y: 180), among: boxes()), 1)
        XCTAssertEqual(ParagraphHitTesting.index(at: CGPoint(x: 10, y: 195), among: boxes()), 2)
    }

    /// 正文两侧的留白、正文下方的空白：按纵向最近归段，绝不返回 nil。
    func testPointOutsideEveryBoxStillResolves() throws {
        XCTAssertEqual(ParagraphHitTesting.index(at: CGPoint(x: 400, y: 130), among: boxes()), 1)
        XCTAssertEqual(ParagraphHitTesting.index(at: CGPoint(x: 10, y: 900), among: boxes()), 2)
        XCTAssertEqual(ParagraphHitTesting.index(at: CGPoint(x: -50, y: 10), among: boxes()), 0)
    }

    /// 跨十行的长段落被旁边一个矮段落的中心「抢」走，是常见错法：
    /// 比较的必须是到矩形边缘的距离，不是到中心点的距离。
    func testTallParagraphIsNotStolenByShortNeighbour() {
        let tall = PageParagraphBox(
            paragraphIndex: 7,
            frame: CGRect(x: 0, y: 0, width: 300, height: 400),
            firstLine: CGRect(x: 0, y: 0, width: 300, height: 20),
            lastLine: CGRect(x: 0, y: 380, width: 300, height: 20)
        )
        let short = PageParagraphBox(
            paragraphIndex: 8,
            frame: CGRect(x: 0, y: 420, width: 300, height: 40),
            firstLine: CGRect(x: 0, y: 420, width: 300, height: 20),
            lastLine: CGRect(x: 0, y: 440, width: 300, height: 20)
        )
        XCTAssertEqual(ParagraphHitTesting.index(at: CGPoint(x: 10, y: 380), among: [tall, short]), 7)
        XCTAssertEqual(ParagraphHitTesting.index(at: CGPoint(x: 10, y: 415), among: [tall, short]), 8)
    }

    func testNoBoxesMeansNoSelection() {
        XCTAssertNil(ParagraphHitTesting.index(at: CGPoint(x: 10, y: 10), among: []))
    }
}
