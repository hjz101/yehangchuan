import CoreGraphics

/// 页内坐标 → 段落下标。
///
/// 「长按选中的是哪一段」这件事原本写在界面层（`PaginatedBook.paragraph(at:in:)`），
/// 于是它成了整条 CoreText 链路上唯一没有测试覆盖的一环：跑 `swift test` 碰不到它，
/// 而模拟器上又没法注入长按。把判定抽成纯函数放到这里，规则就能被单测钉住，
/// 界面层只负责把命中结果换成 `Paragraph`。
///
/// 输入是 `ChapterLayout.paragraphBoxes(in:size:)` 算出来的盒子，
/// 坐标系与界面一致：原点在正文区域左上角，y 向下。
public enum ParagraphHitTesting {
    /// 点在某个段落盒子里 → 就是那一段。
    ///
    /// 点在盒子之外（段落之间的空隙、正文两侧的留白、正文下方的空白）→
    /// 归到**矩形边界**上纵向最近的那一段，而不是「没点到」。
    /// 长按差几像素就什么都不弹，是最恼人的交互。
    ///
    /// 比较的是到矩形边缘的纵向距离，不是到矩形中心（midY）的距离：
    /// 一个段落跨十行时，它的中心可能离落点很远，而紧挨着落点的那一行
    /// 恰恰属于它 —— 按中心比会把落点判给旁边那个矮段落。
    public static func index(at point: CGPoint, among boxes: [PageParagraphBox]) -> Int? {
        guard !boxes.isEmpty else { return nil }

        // 取最后一个命中的：页边界上被切开的段落，后出现的那一块是续排部分，
        // 读者按在接缝上时想要的是眼前这一块。
        if let hit = boxes.last(where: { $0.frame.contains(point) }) {
            return hit.paragraphIndex
        }

        func verticalDistance(to rect: CGRect) -> CGFloat {
            if point.y < rect.minY { return rect.minY - point.y }
            if point.y > rect.maxY { return point.y - rect.maxY }
            return 0
        }

        let nearest = boxes.min { lhs, rhs in
            let left = verticalDistance(to: lhs.frame)
            let right = verticalDistance(to: rhs.frame)
            // 距离相同时按 x 取靠左的那一段，保证同样的点永远得到同样的结果。
            if left == right { return lhs.frame.minX < rhs.frame.minX }
            return left < right
        }
        return nearest?.paragraphIndex
    }
}
