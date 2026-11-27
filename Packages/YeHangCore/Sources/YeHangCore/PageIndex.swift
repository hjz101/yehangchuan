import Foundation

/// 页表索引：把「页数组 + 章 ID 列表」整理成可常数时间查询的索引。
///
/// 从界面层的 `PaginatedBook` 抽出来放进内核，是因为跨章翻页、重复章 ID、
/// 越界取页这几件事一旦错了，读者看到的是空白页或跳到别人的书，
/// 必须有 `swift test` 直接钉住，而不是靠模拟器肉眼检查。
public struct PageIndex: Equatable, Sendable {
    public let pages: [ReadingPage]
    /// 书 ID → 该章的页数。页眉显示「本章第几页」时不能每次都数一遍。
    public let chapterPageCounts: [String: Int]
    private let chapterIndexByID: [String: Int]

    public init(pages: [ReadingPage], chapterIDs: [String]) {
        self.pages = pages
        var counts: [String: Int] = [:]
        for page in pages { counts[page.chapterID, default: 0] += 1 }
        self.chapterPageCounts = counts
        self.chapterIndexByID = Dictionary(
            chapterIDs.enumerated().map { ($0.element, $0.offset) },
            uniquingKeysWith: { first, _ in first }
        )
    }

    public func page(at index: Int) -> ReadingPage? {
        pages.indices.contains(index) ? pages[index] : nil
    }

    public func chapterIndex(for id: String) -> Int? {
        chapterIndexByID[id]
    }
}

/// 页级缓存的容量。条目本来就少，满了整体清掉而不是逐条淘汰。
public enum PageCachePolicy {
    public static let capacity = 24
}

/// 页级缓存：清空后重建一两页的代价可以忽略，也不必维护访问顺序。
public struct PageCache<Value> {
    private var storage: [String: Value] = [:]

    public init() {}

    public func value(for key: String) -> Value? {
        storage[key]
    }

    public mutating func store(_ value: Value, for key: String) {
        if storage.count >= PageCachePolicy.capacity { storage.removeAll(keepingCapacity: true) }
        storage[key] = value
    }

    public mutating func removeAll() {
        storage.removeAll(keepingCapacity: true)
    }
}
