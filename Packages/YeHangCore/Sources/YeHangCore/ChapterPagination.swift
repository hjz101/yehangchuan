import Foundation

/// 段落的最小输入：一个稳定 ID + 文本。
/// 阅读器只关心这两样，段评等附加数据留在 App 侧按 ID 查。
public struct SourceParagraph: Equatable, Sendable, Codable {
    public let id: String
    public let text: String

    public init(id: String, text: String) {
        self.id = id
        self.text = text
    }
}

/// 一章的输入。
public struct ChapterText: Equatable, Sendable {
    public let id: String
    public let title: String
    public let paragraphs: [SourceParagraph]

    public init(id: String, title: String, paragraphs: [SourceParagraph]) {
        self.id = id
        self.title = title
        self.paragraphs = paragraphs
    }
}

/// 一页里的一个段落片段。
///
/// 段落可能被页边界切开，所以这里的 `range` 是相对整段的 UTF-16 范围，
/// 而不是整段。界面据此判断：续排片段不再显示段评胶囊，
/// 被切断的段落也不该在这一页显示「本段结束」的装饰。
public struct PageParagraphSlice: Equatable, Sendable {
    public let paragraphIndex: Int
    public let paragraphID: String
    /// 相对整段落的位置与长度。
    public let range: NSRange
    /// 这一页显示的文字。
    public let text: String
    /// 整段的 UTF-16 长度。
    public let paragraphLength: Int

    public init(
        paragraphIndex: Int,
        paragraphID: String,
        range: NSRange,
        text: String,
        paragraphLength: Int
    ) {
        self.paragraphIndex = paragraphIndex
        self.paragraphID = paragraphID
        self.range = range
        self.text = text
        self.paragraphLength = paragraphLength
    }

    /// 本页是从这一段中间开始的（不是段首）。
    public var isContinuation: Bool { range.location > 0 }
    /// 这一段在本页之后还有后续。
    public var continuesOnNextPage: Bool { NSMaxRange(range) < paragraphLength }
    /// 这一页是否包含本段的开头（段评胶囊只挂在段首）。
    public var startsParagraph: Bool { range.location == 0 }
}

/// 一页。跨章翻页由调用方按 `chapterIndex` 拼接，不在这里跨越章边界。
public struct ReadingPage: Equatable, Sendable {
    public let chapterIndex: Int
    public let pageIndexInChapter: Int
    public let chapterID: String
    public let chapterTitle: String
    public let slices: [PageParagraphSlice]
    /// 页首锚点：段落下标 + 段内偏移。
    public let anchor: ReaderAnchor
    /// 可用区域连一行都放不下时为 true，界面需要提示而不是静默裁字。
    public let overflows: Bool

    public init(
        chapterIndex: Int,
        pageIndexInChapter: Int,
        chapterID: String,
        chapterTitle: String,
        slices: [PageParagraphSlice],
        anchor: ReaderAnchor,
        overflows: Bool
    ) {
        self.chapterIndex = chapterIndex
        self.pageIndexInChapter = pageIndexInChapter
        self.chapterID = chapterID
        self.chapterTitle = chapterTitle
        self.slices = slices
        self.anchor = anchor
        self.overflows = overflows
    }

    /// 本页首段（用于书签与「当前段落」这类界面提示）。
    public var firstParagraphID: String? { slices.first?.paragraphID }

    /// 本页显示的所有段落 ID（去重，按顺序）。
    public var paragraphIDs: [String] {
        var seen = Set<String>()
        return slices.compactMap { seen.insert($0.paragraphID).inserted ? $0.paragraphID : nil }
    }
}

/// 把一本书的章节按真实排版切成页。
///
/// 不跨章合并：一章的最后一页可以只填半页，这样章节本身是一个完整的
/// 排版单元，章内锚点与章间跳转都能独立计算，不会因为相邻章的字数变化
/// 而让整本书的页码全部平移。
public enum ChapterPagination {
    public static func pages(
        for chapters: [ChapterText],
        style: PageTextStyle,
        size: CGSize
    ) -> [ReadingPage] {
        var result: [ReadingPage] = []
        result.reserveCapacity(chapters.count * 8)

        for (chapterIndex, chapter) in chapters.enumerated() {
            let layout = ChapterLayout(
                chapterID: chapter.id,
                paragraphs: chapter.paragraphs.map(\.text),
                style: style
            )
            for (pageIndex, page) in layout.pages(in: size).enumerated() {
                result.append(
                    ReadingPage(
                        chapterIndex: chapterIndex,
                        pageIndexInChapter: pageIndex,
                        chapterID: chapter.id,
                        chapterTitle: chapter.title,
                        slices: slices(in: layout, page: page, chapter: chapter),
                        anchor: layout.anchor(atChapterOffset: page.range.location),
                        overflows: page.overflows
                    )
                )
            }
        }
        return result
    }

    /// 页范围 → 段落片段。页边界落在段落之间的换行上时，
    /// 这一页可能一个片段都没有（例如极窄的屏把整页留给空行），
    /// 这是真实情况，不编造片段。
    static func slices(in layout: ChapterLayout, page: PageRange, chapter: ChapterText) -> [PageParagraphSlice] {
        var result: [PageParagraphSlice] = []
        for (index, paragraphRange) in layout.paragraphRanges.enumerated() {
            let overlap = NSIntersectionRange(paragraphRange, page.range)
            guard overlap.length > 0 else { continue }
            let local = NSRange(location: overlap.location - paragraphRange.location, length: overlap.length)
            let text = (layout.paragraphs[index] as NSString).substring(with: local)
            let id = chapter.paragraphs.indices.contains(index) ? chapter.paragraphs[index].id : ""
            result.append(
                PageParagraphSlice(
                    paragraphIndex: index,
                    paragraphID: id,
                    range: local,
                    text: text,
                    paragraphLength: layout.paragraphs[index].utf16.count
                )
            )
        }
        return result
    }

    /// 从锚点找页。
    ///
    /// 必须给章序号：`ReaderAnchor` 只描述「章内第几段的第几个字」，
    /// 不同章的同一锚点无法互相比较，不传章就等于让全书页码乱序。
    /// 章内页首锚点单调递增，所以二分即可。找不到时返回 nil，
    /// 由调用方决定回退，不在这里偷偷跳到章首。
    public static func pageIndex(
        for anchor: ReaderAnchor,
        inChapter chapterIndex: Int,
        of pages: [ReadingPage]
    ) -> Int? {
        guard !pages.isEmpty else { return nil }
        let candidates = pages.indices.filter { pages[$0].chapterIndex == chapterIndex }
        guard !candidates.isEmpty else { return nil }

        var low = 0
        var high = candidates.count - 1
        var found: Int?
        while low <= high {
            let mid = (low + high) / 2
            if pages[candidates[mid]].anchor <= anchor {
                found = candidates[mid]
                low = mid + 1
            } else {
                high = mid - 1
            }
        }
        return found ?? candidates.first
    }
}

extension ReaderAnchor: Comparable {
    /// 阅读位置的自然顺序：先比段落，再比段内偏移。
    public static func < (lhs: ReaderAnchor, rhs: ReaderAnchor) -> Bool {
        if lhs.paragraphIndex != rhs.paragraphIndex {
            return lhs.paragraphIndex < rhs.paragraphIndex
        }
        return lhs.utf16Offset < rhs.utf16Offset
    }
}
