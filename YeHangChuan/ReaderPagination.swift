import CoreText
import SwiftUI
import UIKit
import YeHangCore

// MARK: - 页面几何

/// 正文区域在整页上的位置。
///
/// 分页测量与绘制必须用**同一组值**：这是「量出来的页」等于「画出来的页」
/// 的前提。以前一边按字数估算容量、一边交给 SwiftUI 自己排版，两份结果
/// 对不上，文字被裁掉正是从那里来的。
enum ReaderMetrics {
    /// 上下留白的默认值：顶部给悬浮工具栏与页眉，底部给页脚、进度条与工具条。
    /// 读者可以在阅读设置里改，所以这里只是初值。
    static let defaultSide: CGFloat = 28
    static let defaultTop: CGFloat = 96
    static let defaultBottom: CGFloat = 152
    /// 工具栏最下沿落在 96 点。< minTop 时读者开工具栏的那一刻，第一行
    /// 就被压在返回键与页眉底下，读到的边界和屏幕上看到的不一样。
    /// 所以 96 是上边界的地板，而不是「建议值」。
    static let minTop: CGFloat = 96
    static let maxTop: CGFloat = 240
    /// 下边界最小 152：底部浮层（进度条 + 工具栏）加页脚就是这条高度，
    /// 再小就会把正文送进浮层底下。抓手与「完成」按钮另占一条，不需要
    /// 靠正文让位。
    static let minBottom: CGFloat = 152
    static let maxBottom: CGFloat = 320
    /// 左右留白的活动范围。26 是页边看起来像书边的下限，68 是窄栏单行的上限。
    static let minSide: CGFloat = 16
    static let maxSide: CGFloat = 68
    /// 段评胶囊挂靠的右侧留白。只在书里确实有段评时保留 ——
    /// 没有段评的书不该为一条永远不会出现的胶囊让出正文宽度。
    static let commentGutter: CGFloat = 24

    static func textSize(
        in viewport: CGSize,
        sideMargin: Double,
        topMargin: Double,
        bottomMargin: Double,
        hasComments: Bool
    ) -> CGSize {
        let gutter = hasComments ? commentGutter : 0
        return CGSize(
            width: max(viewport.width - sideMargin * 2 - gutter, 40),
            height: max(viewport.height - topMargin - bottomMargin, 40)
        )
    }
}

// MARK: - 字体

/// 可以跨线程传递的排版参数。
///
/// `CTFont` 不是线程无关的，所以分页丢到后台跑时只传这些数字，
/// 到真正要用字体时才拼出来。前后两处拼出来的完全一样，
/// 不会出现「后台量的时候一个字体、前台画的时候另一个字体」。
struct ReaderTypeface: Sendable {
    var fontName: String
    var weight: CGFloat
    var fontSize: CGFloat
    var extraLineSpacing: CGFloat
    var paragraphSpacing: CGFloat
    var firstLineIndent: CGFloat

    func style() -> PageTextStyle {
        let descriptor = UIFontDescriptor(fontAttributes: [
            .name: fontName,
            .traits: [UIFontDescriptor.TraitKey.weight: UIFont.Weight(rawValue: weight)]
        ])
        let font = UIFont(descriptor: descriptor, size: fontSize)
        return PageTextStyle(
            font: CTFontCreateWithName(font.fontName as CFString, fontSize, nil),
            extraLineSpacing: extraLineSpacing,
            paragraphSpacing: paragraphSpacing,
            firstLineIndent: firstLineIndent
        )
    }
}

enum ReaderTypography {
    static func fontName(for design: ReaderFontDesign) -> String {
        switch design {
        case .serif: "Songti SC"
        case .system: "PingFang SC"
        case .rounded: "Yuanti SC"
        }
    }

    static func weightValue(_ weight: ReaderWeight) -> CGFloat {
        switch weight {
        case .regular: UIFont.Weight.regular.rawValue
        case .medium: UIFont.Weight.medium.rawValue
        case .semibold: UIFont.Weight.semibold.rawValue
        }
    }

    @MainActor
    static func typeface(_ settings: ReaderSettings) -> ReaderTypeface {
        ReaderTypeface(
            fontName: fontName(for: settings.fontDesign),
            weight: weightValue(settings.fontWeight),
            fontSize: settings.fontSize,
            extraLineSpacing: settings.fontSize * settings.lineSpacing,
            paragraphSpacing: settings.fontSize * (0.72 + settings.lineSpacing * 0.5),
            // 首行缩进交给排版引擎，不再往正文里插两个全角空格：
            // 插入字符会改变段落长度，也就改变了所有段内偏移。
            firstLineIndent: settings.indent ? settings.fontSize * 2 : 0
        )
    }

    /// 净化正文：去掉「求票」「本章完」这类站内话术。
    ///
    /// 只影响显示，段落 ID 与段内偏移都不变 —— 所以净化开关
    /// 不会让书签和阅读位置错位。但这确实会改变分页，调用方要重排。
    static func displayText(_ paragraph: Paragraph, purify: Bool) -> String {
        guard purify else { return paragraph.text }
        var text = paragraph.text
        text = text.replacingOccurrences(
            of: #"[(（【][^)）】]{0,24}(本章完|求票|作者说)[^)）】]*[)）】]"#,
            with: "",
            options: .regularExpression
        )
        text = text.replacingOccurrences(
            of: #"(?m)^\s*(作者说|PS|ps)[:：].*$"#,
            with: "",
            options: .regularExpression
        )
        return text
    }
}

// MARK: - 排好版的一本书

/// 排好版的一本书：页表 + 每章的排版对象。
///
/// 页表由后台算好；每章的 `ChapterLayout` 在真正要画或要命中时才建，
/// 建完缓存 —— 翻一页最多涉及两三章，不会为了画出三页把全书重排一遍。
@MainActor
final class PaginatedBook {
    let chapters: [Chapter]
    let typeface: ReaderTypeface
    /// 正文可排版区域（不含左右留白与上下浮层）。
    let size: CGSize
    let pages: [ReadingPage]
    let hasComments: Bool
    /// 书 ID → 该章的页数。页眉要显示「本章第几页」，不能每次都数一遍。
    let chapterPageCounts: [String: Int]

    private var layouts = PageCache<ChapterLayout>()
    /// 页 id → 段落位置 / 页正文。翻一页只涉及两三页，但 `TabView` 会同时
    /// 挂住左右邻页，反复重建 `CTFramesetter` 是纯浪费。
    private var boxCache = PageCache<[PageParagraphBox]>()
    private var textCache = PageCache<NSAttributedString>()
    private let index: PageIndex

    init(
        chapters: [Chapter],
        typeface: ReaderTypeface,
        size: CGSize,
        pages: [ReadingPage],
        hasComments: Bool
    ) {
        self.chapters = chapters
        self.typeface = typeface
        self.size = size
        self.pages = pages
        self.hasComments = hasComments
        index = PageIndex(pages: pages, chapterIDs: chapters.map(\.id))
        chapterPageCounts = index.chapterPageCounts
    }

    var isEmpty: Bool { pages.isEmpty }

    func page(at position: Int) -> ReadingPage? {
        index.page(at: position)
    }

    func chapter(withID id: String) -> Chapter? {
        index.chapterIndex(for: id).map { chapters[$0] }
    }

    /// 这一页所属章节的排版对象。按需构建并缓存。
    func layout(for page: ReadingPage) -> ChapterLayout {
        layout(chapterID: page.chapterID)
    }

    func layout(chapterID: String) -> ChapterLayout {
        if let cached = layouts.value(for: chapterID) { return cached }
        let paragraphs = chapter(withID: chapterID)?.paragraphs.map(\.text) ?? []
        let layout = ChapterLayout(chapterID: chapterID, paragraphs: paragraphs, style: typeface.style())
        layouts.store(layout, for: chapterID)
        return layout
    }

    /// 本页在章内拍平文本里的范围。绘制按它切富文本。
    func pageRange(for page: ReadingPage) -> PageRange {
        PageRange(range: page.chapterRange, overflows: page.overflows)
    }

    /// 段落片段对应的真实段落（带段评）。
    func paragraph(for slice: PageParagraphSlice, in page: ReadingPage) -> Paragraph? {
        guard let chapter = chapter(withID: page.chapterID),
              chapter.paragraphs.indices.contains(slice.paragraphIndex) else { return nil }
        return chapter.paragraphs[slice.paragraphIndex]
    }

    /// 本页要画的富文本（不含文字颜色，颜色由绘制层按主题加）。
    ///
    /// 直接按 `chapterRange` 从整章里切，而不是拿段落片段重新拼一遍 ——
    /// 拼出来的那份和测量时用的那份一旦有一个字的差别，结果就是文字被裁。
    func text(for page: ReadingPage) -> NSAttributedString {
        if let cached = textCache.value(for: page.id) { return cached }
        let text = layout(for: page).attributedString(for: pageRange(for: page))
        textCache.store(text, for: page.id)
        return text
    }

    /// 本页每个段落占据的位置（首行用于摆段评胶囊）。
    func paragraphBoxes(for page: ReadingPage) -> [PageParagraphBox] {
        if let cached = boxCache.value(for: page.id) { return cached }
        let boxes = layout(for: page).paragraphBoxes(in: pageRange(for: page), size: size)
        boxCache.store(boxes, for: page.id)
        return boxes
    }

    /// 页内坐标 → 该段的段落对象。长按选段用。
    ///
    /// 判定规则在 `ParagraphHitTesting`（YeHangCore）里，那边有单测钉住。
    /// 放在界面层时它跑不进 `swift test`，而模拟器又没法注入长按 ——
    /// 整条 CoreText 链路就这一环没有防线。这里只做「下标 → 段落」的换算。
    func paragraph(at point: CGPoint, in page: ReadingPage) -> Paragraph? {
        guard let index = ParagraphHitTesting.index(at: point, among: paragraphBoxes(for: page)),
              let chapter = chapter(withID: page.chapterID),
              chapter.paragraphs.indices.contains(index) else { return nil }
        return chapter.paragraphs[index]
    }

}

// MARK: - 绘制

/// 用 CoreText 把一页画出来。
///
/// 走这条路而不是 `Text`，是因为分页与绘制必须是同一套排版：
/// `ChapterLayout` 用 `CTFramesetterCreateFrame` + `CTFrameGetVisibleStringRange`
/// 量出这一页能放多少字，这里用同样的调用把它们画出来。
/// 交给 SwiftUI 自己排的话，两份结果总会有差，差的那些字就没了。
struct CoreTextPageView: UIViewRepresentable {
    let text: NSAttributedString
    let size: CGSize

    func makeUIView(context: Context) -> CoreTextPageUIView {
        let view = CoreTextPageUIView()
        view.backgroundColor = .clear
        view.isOpaque = false
        view.isUserInteractionEnabled = false
        view.contentMode = .redraw
        return view
    }

    func updateUIView(_ view: CoreTextPageUIView, context: Context) {
        view.attributedText = text
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: CoreTextPageUIView, context: Context) -> CGSize? {
        size
    }
}

final class CoreTextPageUIView: UIView {
    var attributedText = NSAttributedString() {
        didSet { setNeedsDisplay() }
    }

    /// 尺寸一变就重画。
    ///
    /// `contentMode = .redraw` 只在内容模式相关的缩放时生效，并不能覆盖
    /// 「representable 先按内在尺寸布局、随后被撑到目标尺寸」这条路径。
    /// 少了这一句，第一遍会以很小的 bounds 画一遍，之后再也不重画 ——
    /// 屏幕上是「整页只剩几行」，正是分页要防的那件事。
    override func layoutSubviews() {
        super.layoutSubviews()
        setNeedsDisplay()
    }

    override func draw(_ rect: CGRect) {
        guard let context = UIGraphicsGetCurrentContext(), attributedText.length > 0 else { return }
        // CoreText 的原点在左下，UIKit 的在左上：翻一次再画。
        context.textMatrix = .identity
        context.translateBy(x: 0, y: bounds.height)
        context.scaleBy(x: 1, y: -1)

        let framesetter = CTFramesetterCreateWithAttributedString(attributedText)
        let path = CGPath(rect: CGRect(origin: .zero, size: bounds.size), transform: nil)
        let frame = CTFramesetterCreateFrame(framesetter, CFRange(location: 0, length: 0), path, nil)
        CTFrameDraw(frame, context)

        #if DEBUG
        let visible = CTFrameGetVisibleStringRange(frame).length
        if visible < attributedText.length {
            print("[YeHangChuan] 正文被裁：画出 \(visible) / \(attributedText.length) 字，bounds \(bounds.size)")
        }
        #endif
    }
}

// MARK: - 触摸

/// 覆盖在正文上的透明触摸层，负责「点一下」和「长按某一段」。
///
/// 为什么要落到 UIKit：SwiftUI 的 `onLongPressGesture` 不给位置，
/// 而选中哪一段恰恰取决于按在哪里。用 `UILongPressGestureRecognizer`
/// 才拿得到原始坐标，再交给 `PaginatedBook` 去命中段落。
///
/// 只放 tap 与 long press 两个识别器：手指一移动它们就失败，
/// 所以左右滑翻页、上下滚动的拖动照常交给外层的手势处理，不会被吞掉。
///
/// 这两个识别器**不互相 require(toFail:)**。用一个 0.35 秒的长按去挡轻点，
/// 意味着每次点屏幕唤出工具栏都要先等那 0.35 秒 —— 手感就是「点了没反应」。
/// 改成：长按一旦成立就置一个标记，随后抬手时轻点的回调直接丢一次。
struct PageTouchSurface: UIViewRepresentable {
    /// 落点 + 触摸层尺寸。分区（左右翻页、中间唤出工具栏）由调用方决定：
    /// 这里只如实报告「点在了哪儿」，不猜用户想要什么。
    let onTap: (CGPoint, CGSize) -> Void
    let onLongPress: (CGPoint) -> Void

    func makeUIView(context: Context) -> TouchUIView {
        let view = TouchUIView()
        view.backgroundColor = .clear
        view.isOpaque = false

        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap(_:)))
        let press = UILongPressGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleLongPress(_:))
        )
        press.minimumPressDuration = 0.35
        // 手指稍微抖一下不该丢掉这次长按。
        press.allowableMovement = 12

        view.addGestureRecognizer(tap)
        view.addGestureRecognizer(press)
        return view
    }

    func updateUIView(_ view: TouchUIView, context: Context) {
        context.coordinator.onTap = onTap
        context.coordinator.onLongPress = onLongPress
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onTap: onTap, onLongPress: onLongPress)
    }

    final class Coordinator: NSObject {
        var onTap: (CGPoint, CGSize) -> Void
        var onLongPress: (CGPoint) -> Void
        /// 本次触摸已经被长按消费掉：抬手时不要再多触发一次轻点。
        private var longPressHandled = false

        init(onTap: @escaping (CGPoint, CGSize) -> Void, onLongPress: @escaping (CGPoint) -> Void) {
            self.onTap = onTap
            self.onLongPress = onLongPress
        }

        @objc func handleTap(_ recognizer: UITapGestureRecognizer) {
            guard !longPressHandled, let view = recognizer.view else { return }
            onTap(recognizer.location(in: view), view.bounds.size)
        }

        @objc func handleLongPress(_ recognizer: UILongPressGestureRecognizer) {
            // 只在按下那一刻响应一次：长按中手指出汗抖动会持续发 .changed，
            // 每个都响应的话会弹出好几遍。
            switch recognizer.state {
            case .began:
                guard let view = recognizer.view else { return }
                longPressHandled = true
                onLongPress(recognizer.location(in: view))
            case .ended, .cancelled, .failed:
                // 手势结束后隔一拍再清标记：同一次触摸里的轻点识别器
                // 是在长按结束之后才决定是否触发的。
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
                    self?.longPressHandled = false
                }
            default:
                break
            }
        }
    }
}

/// 只做命中测试的透明层。`hitTest` 永远返回自己，
/// 但除它以外没有别的东西 —— 视觉上完全不可见，只负责把触摸交出去。
final class TouchUIView: UIView {
    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        bounds.contains(point)
    }
}
