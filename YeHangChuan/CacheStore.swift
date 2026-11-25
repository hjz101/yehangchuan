import Foundation

/// 图片「缓存」在演示工程里没有真实的图片文件可存，
/// 但界面上写着「已缓存 N 页图片」，那 N 页数量得是能落盘、能清掉的东西。
/// 这里把每话的页面清单写成一个 JSON 清单文件，体积与真实读取都成立：
/// 开关会真的写文件、关掉会真的删文件，清理缓存也会真的删掉。
enum ImageCacheStore {
    static let directoryName = "ImageCache"

    private static var directory: URL? {
        let manager = FileManager.default
        guard let base = manager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return nil
        }
        var url = base.appendingPathComponent("YeHangChuan", isDirectory: true)
        url.appendPathComponent(directoryName, isDirectory: true)
        try? manager.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private static func fileURL(for bookID: String) -> URL? {
        directory?.appendingPathComponent("\(bookID).json")
    }

    /// 写入清单并返回文件字节数；失败返回 nil。
    @discardableResult
    static func store(bookID: String, title: String, pages: Int) -> Int? {
        guard let url = fileURL(for: bookID) else { return nil }
        let manifest: [String: Any] = [
            "bookID": bookID,
            "title": title,
            "pages": pages,
            "cachedAt": ISO8601DateFormatter().string(from: Date())
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: manifest, options: [.prettyPrinted]) else {
            return nil
        }
        guard (try? data.write(to: url, options: .atomic)) != nil else { return nil }
        return data.count
    }

    /// 删除清单，返回释放的字节数。
    @discardableResult
    static func remove(bookID: String) -> Int? {
        guard let url = fileURL(for: bookID) else { return nil }
        let manager = FileManager.default
        let size = (try? manager.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.intValue ?? 0
        guard (try? manager.removeItem(at: url)) != nil else { return nil }
        return size
    }

    static func isCached(bookID: String) -> Bool {
        guard let url = fileURL(for: bookID) else { return false }
        return FileManager.default.fileExists(atPath: url.path)
    }

    /// 清空整个图片缓存目录，返回释放的字节数。
    @discardableResult
    static func removeAll() -> Int {
        guard let directory else { return 0 }
        let manager = FileManager.default
        guard let names = try? manager.contentsOfDirectory(atPath: directory.path) else { return 0 }
        var freed = 0
        for name in names {
            let url = directory.appendingPathComponent(name)
            let size = (try? manager.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.intValue ?? 0
            if (try? manager.removeItem(at: url)) != nil { freed += size }
        }
        return freed
    }

    /// 当前缓存占用，用于刷新设置页的数字。
    static func totalBytes() -> Int {
        guard let directory else { return 0 }
        let manager = FileManager.default
        guard let names = try? manager.contentsOfDirectory(atPath: directory.path) else { return 0 }
        return names.reduce(0) { partial, name in
            let url = directory.appendingPathComponent(name)
            let size = (try? manager.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.intValue ?? 0
            return partial + size
        }
    }
}
