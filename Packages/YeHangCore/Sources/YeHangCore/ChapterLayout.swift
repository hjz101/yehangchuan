import CoreText
import Foundation

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// 正文排版：把一章段落排成固定屏幕尺寸下的页。
///
/// 分页与绘制用的是同一套 CoreText 调用（`CTFramesetterCreateFrame` +
/// `CTFrameGetVisibleStringRange`），所以「量出来的页」就是「画出来的页」——
/// 不会出现估算容量导致文字被裁掉的情况。
///
/// 锚点用「段落下标 + 段内 UTF-16 偏移」，与页序号无关：
/// 换字号、转屏、改行距后重新分页，同一段文字仍然能找回来。
/// 不标 `Sendable`：内部持有 `NSAttributedString`，不是线程无关的。
/// 分页在单一队列上完成，结果（`[PageRange]`）才是可以跨线程传的。
public struct ChapterLayout {
    public let chapterID: String
    public let paragraphs: [String]
    public let style: PageTextStyle
    /// 整章拍平后的富文本：段落之间用 `\n` 连接，段落属性按 `style` 生成。
    public let attributedText: NSAttributedString
    /// 每个段落在 `attributedText` 里的位置。
    public let paragraphRanges: [NSRange]

    public init(chapterID: String, paragraphs: [String], style: PageTextStyle) {
        self.chapterID = chapterID
        self.paragraphs = paragraphs
        self.style = style

        let text = NSMutableAttributedString()
        var ranges: [NSRange] = []
        for (index, paragraph) in paragraphs.enumerated() {
            if index > 0 {
                text.append(NSAttributedString(string: "\n", attributes: style.bodyAttributes))
            }
            ranges.append(NSRange(location: text.length, length: (paragraph as NSString).length))
            text.append(NSAttributedString(string: paragraph, attributes: style.bodyAttributes))
        }
        attributedText = text
        paragraphRanges = ranges
    }

    // MARK: - 分页

    /// 按给定可用区域分页。返回的页范围连续、不重叠、完整覆盖整章。
    public func pages(in size: CGSize) -> [PageRange] {
        guard size.width >= 1, size.height >= 1, attributedText.length > 0 else { return [] }
        let string = attributedText.string as NSString
        var result: [PageRange] = []
        var start = 0

        while start < attributedText.length {
            let continuation = start > 0 && string.character(at: start - 1) != 0x0A
            let slice = pageSlice(from: start, continuation: continuation)
            let length = Self.visibleLength(of: slice, in: size)
            if length <= 0 {
                // 一行都放不下（可用高度小于一行）：把剩余内容整页交出，
                // 宁可溢出也要保证一个字都不丢，由界面提示用户调整字号。
                result.append(PageRange(range: NSRange(location: start, length: attributedText.length - start), overflows: true))
                break
            }
            result.append(PageRange(range: NSRange(location: start, length: length), overflows: false))
            start += length
        }
        return result
    }

    /// 某一页用于绘制与测量的富文本。
    ///
    /// 跨页续排的段落要把段首缩进去掉：那一行不是段首，
    /// 留着缩进会让每页开头凭空空两格，还会改变这一行的折行位置。
    public func attributedString(for page: PageRange) -> NSAttributedString {
        let string = attributedText.string as NSString
        let start = page.range.location
        let continuation = start > 0 && start <= string.length && string.character(at: start - 1) != 0x0A
        return pageSlice(from: start, continuation: continuation, limit: page.range.length)
    }

    private func pageSlice(from start: Int, continuation: Bool, limit: Int? = nil) -> NSAttributedString {
        let remaining = attributedText.length - start
        let length = min(max(0, limit ?? remaining), remaining)
        let slice = NSMutableAttributedString(
            attributedString: attributedText.attributedSubstring(from: NSRange(location: start, length: length))
        )
        guard continuation, slice.length > 0 else { return slice }

        let firstParagraph = (slice.string as NSString).paragraphRange(for: NSRange(location: 0, length: 0))
        let target = NSIntersectionRange(firstParagraph, NSRange(location: 0, length: slice.length))
        guard target.length > 0,
              let current = slice.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle,
              let adjusted = current.mutableCopy() as? NSMutableParagraphStyle else { return slice }
        adjusted.firstLineHeadIndent = 0
        slice.addAttribute(.paragraphStyle, value: adjusted, range: target)
        return slice
    }

    /// 用与绘制完全相同的调用量出这一页能放下多少字符。
    static func visibleLength(of string: NSAttributedString, in size: CGSize) -> Int {
        guard string.length > 0, size.width >= 1, size.height >= 1 else { return 0 }
        let framesetter = CTFramesetterCreateWithAttributedString(string)
        let path = CGPath(rect: CGRect(origin: .zero, size: size), transform: nil)
        let frame = CTFramesetterCreateFrame(framesetter, CFRange(location: 0, length: 0), path, nil)
        return CTFrameGetVisibleStringRange(frame).length
    }

    // MARK: - 锚点

    /// 章内字符偏移 → 段落锚点。
    public func anchor(atChapterOffset offset: Int) -> ReaderAnchor {
        guard !paragraphRanges.isEmpty else { return ReaderAnchor(paragraphIndex: 0, utf16Offset: 0) }
        let clamped = min(max(0, offset), attributedText.length)
        let index = paragraphRanges.lastIndex { $0.location <= clamped } ?? 0
        let range = paragraphRanges[index]
        let text = paragraphs[index] as NSString
        let within = ReadingAnchorMath.safeOffset(
            min(max(0, clamped - range.location), range.length),
            in: text
        )
        return ReaderAnchor(paragraphIndex: index, utf16Offset: within)
    }

    /// 段落锚点 → 章内字符偏移。
    public func chapterOffset(for anchor: ReaderAnchor) -> Int {
        guard !paragraphRanges.isEmpty else { return 0 }
        let index = min(max(0, anchor.paragraphIndex), paragraphRanges.count - 1)
        let range = paragraphRanges[index]
        let text = paragraphs[index] as NSString
        return range.location + ReadingAnchorMath.safeOffset(min(max(0, anchor.utf16Offset), range.length), in: text)
    }

    /// 锚点落在第几页。找不到时返回 nil，由调用方决定回退策略，
    /// 而不是悄悄跳到章首。
    public func pageIndex(for anchor: ReaderAnchor, in pages: [PageRange]) -> Int? {
        guard !pages.isEmpty else { return nil }
        let offset = chapterOffset(for: anchor)
        return pages.lastIndex { $0.range.location <= offset }
    }

    // MARK: - 绘制与命中

    /// 页内坐标 → 章内字符偏移。
    ///
    /// 点的坐标系与界面一致（左上角原点、y 向下），内部翻成 CoreText 的
    /// 左下原点。命中用的 CTFrame 与绘制用的是同一份页面富文本，
    /// 所以「点在哪个字上」不会因为两份排版不一致而错位。
    ///
    /// 点落在行与行之间的空白、或正文下面的空白时，归到纵向最近的那一行 ——
    /// 停在一个字下面一点再长按，读到的应该仍是那个字，而不是「什么都没点到」。
    public func chapterOffset(at point: CGPoint, in page: PageRange, size: CGSize) -> Int? {
        guard let (frame, string) = makeFrame(for: page, in: size) else { return nil }
        let point = CGPoint(x: point.x, y: size.height - point.y)
        guard let lines = CTFrameGetLines(frame) as? [CTLine], !lines.isEmpty else { return nil }

        var origins = [CGPoint](repeating: .zero, count: lines.count)
        CTFrameGetLineOrigins(frame, CFRange(location: 0, length: 0), &origins)

        var hit = 0
        var nearest = CGFloat.greatestFiniteMagnitude
        for (index, line) in lines.enumerated() {
            let rect = lineRect(line, origin: origins[index])
            if point.y >= rect.minY, point.y <= rect.maxY {
                hit = index
                break
            }
            let distance = min(abs(point.y - rect.minY), abs(point.y - rect.maxY))
            if distance < nearest {
                nearest = distance
                hit = index
            }
        }

        let position = CTLineGetStringIndexForPosition(lines[hit], point)
        guard position != kCFNotFound else { return nil }
        // CTLine 的下标是相对本页那一份富文本的，加上本页起点才是章内偏移。
        let local = min(max(position, 0), max(string.length - 1, 0))
        return page.range.location + local
    }

    /// 这一页里每个段落占据的区域（左上角原点、y 向下）。
    ///
    /// 段评标记挂在这里：一个段落在一页里可能跨好几行，
    /// 标记只该出现在它开头那一行；续排到下一页的段落首行在下一页，
    /// 所以标记会跟着走，不会消失也不会重复。
    ///
    /// `frame` 是整块（所有行合并），用来判断「长按点在哪一段上」；
    /// `firstLine` 是段落在本页的第一行，用来摆放标记与缩进对齐。
    public func paragraphBoxes(in page: PageRange, size: CGSize) -> [PageParagraphBox] {
        guard let (frame, _) = makeFrame(for: page, in: size) else { return [] }
        guard let lines = CTFrameGetLines(frame) as? [CTLine], !lines.isEmpty else { return [] }

        var origins = [CGPoint](repeating: .zero, count: lines.count)
        CTFrameGetLineOrigins(frame, CFRange(location: 0, length: 0), &origins)

        var order: [Int] = []
        var firstLines: [Int: CGRect] = [:]
        var merged: [Int: CGRect] = [:]
        for (index, line) in lines.enumerated() {
            let stringRange = CTLineGetStringRange(line)
            guard stringRange.location != kCFNotFound else { continue }
            let offset = page.range.location + max(0, stringRange.location)
            let paragraphIndex = anchor(atChapterOffset: offset).paragraphIndex

            let core = lineRect(line, origin: origins[index])
            // CoreText 的原点在左下，界面在左上：翻一次 y。
            let rect = CGRect(
                x: core.minX,
                y: size.height - core.maxY,
                width: core.width,
                height: core.height
            )
            if firstLines[paragraphIndex] == nil {
                order.append(paragraphIndex)
                firstLines[paragraphIndex] = rect
                merged[paragraphIndex] = rect
            } else {
                merged[paragraphIndex] = merged[paragraphIndex]!.union(rect)
            }
        }
        return order.compactMap { index in
            guard let frame = merged[index], let first = firstLines[index] else { return nil }
            return PageParagraphBox(paragraphIndex: index, frame: frame, firstLine: first)
        }
    }

    /// 建一份与绘制完全一致的页面排版。`chapterOffset(at:)` 与
    /// `paragraphLineFragments` 共用它，避免各建一份后行位置对不上。
    private func makeFrame(for page: PageRange, in size: CGSize) -> (CTFrame, NSAttributedString)? {
        guard size.width >= 1, size.height >= 1 else { return nil }
        let slice = attributedString(for: page)
        guard slice.length > 0 else { return nil }
        let framesetter = CTFramesetterCreateWithAttributedString(slice)
        let path = CGPath(rect: CGRect(origin: .zero, size: size), transform: nil)
        return (CTFramesetterCreateFrame(framesetter, CFRange(location: 0, length: 0), path, nil), slice)
    }

    /// 一行在 CoreText 坐标系（左下原点）里的矩形。
    private func lineRect(_ line: CTLine, origin: CGPoint) -> CGRect {
        var ascent: CGFloat = 0
        var descent: CGFloat = 0
        var leading: CGFloat = 0
        let width = CGFloat(CTLineGetTypographicBounds(line, &ascent, &descent, &leading))
        return CGRect(
            x: origin.x,
            y: origin.y - descent,
            width: max(width, 0),
            height: ascent + descent + leading
        )
    }
}

/// 一个段落在当前页里占据的位置。
///
/// 坐标系与界面一致：原点在绘制区域左上角，y 向下。
public struct PageParagraphBox: Equatable, Sendable {
    public let paragraphIndex: Int
    /// 本页里这一段所有行的合并矩形。
    public let frame: CGRect
    /// 这一段在本页的第一行（标注挂在这里）。
    public let firstLine: CGRect

    public init(paragraphIndex: Int, frame: CGRect, firstLine: CGRect) {
        self.paragraphIndex = paragraphIndex
        self.frame = frame
        self.firstLine = firstLine
    }
}

/// 一页覆盖的章内字符范围。
public struct PageRange: Equatable, Sendable {
    public let range: NSRange
    /// 可用区域连一行都放不下时为 true：这一页会溢出，需要界面提示。
    public let overflows: Bool

    public init(range: NSRange, overflows: Bool = false) {
        self.range = range
        self.overflows = overflows
    }

    public var length: Int { range.length }
}

/// 阅读位置锚点：段落下标 + 段内 UTF-16 偏移，与页序号、字号都无关。
public struct ReaderAnchor: Codable, Equatable, Hashable, Sendable {
    public var paragraphIndex: Int
    public var utf16Offset: Int

    public init(paragraphIndex: Int = 0, utf16Offset: Int = 0) {
        self.paragraphIndex = paragraphIndex
        self.utf16Offset = utf16Offset
    }
}

public enum ReadingAnchorMath {
    /// 把偏移夹到合法范围，并且不落在组合字符（emoji、带修饰的汉字）中间。
    public static func safeOffset(_ offset: Int, in text: NSString) -> Int {
        guard text.length > 0 else { return 0 }
        let bounded = min(max(0, offset), text.length - 1)
        return text.rangeOfComposedCharacterSequence(at: bounded).location
    }
}
