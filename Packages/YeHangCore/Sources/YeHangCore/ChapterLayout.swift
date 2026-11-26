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
