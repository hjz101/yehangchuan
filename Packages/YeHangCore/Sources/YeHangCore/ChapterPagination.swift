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
    /// 本页在整章拍平文本里的字符范围。
    ///
    /// 绘制页正文需要它：`ChapterLayout.attributedString(for:)` 按这个范围
    /// 切出与本页完全一致的一段富文本。调用方据此渲染，不必自己再从
    /// 段落片段拼一遍 —— 拼错了就成了「量的是这份、画的是另一份」，
    /// 文字被裁掉正是这么来的。
    public let chapterRange: NSRange
    /// 可用区域连一行都放不下时为 true，界面需要提示而不是静默裁字。
    public let overflows: Bool

    public init(
        chapterIndex: Int,
        pageIndexInChapter: Int,
        chapterID: String,
        chapterTitle: String,
        slices: [PageParagraphSlice],
        anchor: ReaderAnchor,
        chapterRange: NSRange,
        overflows: Bool
    ) {
        self.chapterIndex = chapterIndex
        self.pageIndexInChapter = pageIndexInChapter
        self.chapterID = chapterID
        self.chapterTitle = chapterTitle
        self.slices = slices
        self.anchor = anchor
        self.chapterRange = chapterRange
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
        // 一次请求就排完整本。看起来铺张，但如果按章懒排，翻到下一章时
        // 「第 n / m 页」会变 —— 页数随着你往下读而增长，那是在骗人。
        // 实测 50 万字整本排完约 0.1 秒，放到后台队列即可。
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
                        chapterRange: page.range,
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

/// 阅读进度：读到全书的百分之几。
///
/// 口径是「已读完的章 + 本章内的页比例」，分母是**目录里的章数**，
/// 不是当前已经排好版的页数。这两者必须分开，因为在线书是按章懒加载的：
/// 一开始只有第一章有正文，若拿页数当分母，读到第一章末尾就会显示
/// 「已读 100%」—— 那是假话，书还有四百章没下。
///
/// 这个值只用于展示与兜底定位。真正的位置恢复靠 `ReadingPosition` 里的
/// 章节标题与段落 ID，那个是精确的。
public enum ReadingProgress {
    /// - Parameters:
    ///   - index: 当前页在 `pages` 里的下标。
    ///   - pages: 全书页表。
    ///   - chapterCount: 目录里的章数。为 0（目录还没拉回来）时返回 0。
    /// - Returns: 0...1。永远到不了 1：读完最后一页书也不算「已读完」，
    ///   那要用户自己点「读完」。
    public static func fraction(at index: Int, of pages: [ReadingPage], chapterCount: Int) -> Double {
        guard chapterCount > 0, !pages.isEmpty, pages.indices.contains(index) else { return 0 }
        let page = pages[index]
        let pagesInChapter = pages.lazy.filter { $0.chapterIndex == page.chapterIndex }.count
        let within = pagesInChapter > 0
            ? Double(page.pageIndexInChapter) / Double(pagesInChapter)
            : 0
        let chapters = Double(min(max(page.chapterIndex, 0), chapterCount - 1))
        return min(max((chapters + within) / Double(chapterCount), 0), 0.99)
    }

    /// 进度 → 最接近的那一页。用在「位置锚点找不到了」的兜底：
    /// 段落被删、换源后正文重排，只剩百分比可依。
    ///
    /// 找不到时返回 nil，由调用方决定停在原处还是回到章首，
    /// 不在这里替用户做决定。
    public static func pageIndex(
        nearest fraction: Double,
        in pages: [ReadingPage],
        chapterCount: Int
    ) -> Int? {
        guard !pages.isEmpty, chapterCount > 0 else { return nil }
        var best = 0
        var smallest = Double.greatestFiniteMagnitude
        for index in pages.indices {
            let distance = abs(self.fraction(at: index, of: pages, chapterCount: chapterCount) - fraction)
            if distance < smallest {
                smallest = distance
                best = index
            }
        }
        return best
    }
}
