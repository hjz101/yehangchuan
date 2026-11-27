import Foundation
import AVFoundation
import LegadoCore

/// 漫画图片缓存。真漫画把降采样后的页图写进 `ImageCache/<bookID>/`；
/// 老演示书没有真实图片可存，只保留一份 JSON 清单。两种形态的开关、
/// 清理与占用统计都走同一组接口，所以设置页无需关心是哪种书。
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

    private static func manifestURL(for bookID: String) -> URL? {
        directory?.appendingPathComponent("\(bookID).json")
    }

    private static func folder(for bookID: String) -> URL? {
        directory?.appendingPathComponent(bookID, isDirectory: true)
    }

    // MARK: - 老演示书：只写页面清单

    @discardableResult
    static func store(bookID: String, title: String, pages: Int) -> Int? {
        guard let url = manifestURL(for: bookID) else { return nil }
        let manifest: [String: Any] = [
            "bookID": bookID,
            "title": title,
            "pages": pages,
            "cachedAt": ISO8601DateFormatter().string(from: Date())
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: manifest, options: [.prettyPrinted]),
              (try? data.write(to: url, options: .atomic)) != nil else { return nil }
        return data.count
    }

    // MARK: - 真漫画：逐页降采样落盘

    /// 一次只写一页的图片，由 `imageData` 按需供给，避免把整包原图读进内存。
    @discardableResult
    static func storeImages(
        bookID: String, title: String, pages: Int, imageData: (Int) -> Data?
    ) -> Int? {
        guard let folder = folder(for: bookID), let manifestURL = manifestURL(for: bookID) else { return nil }
        let manager = FileManager.default
        try? manager.removeItem(at: folder)
        try? manager.createDirectory(at: folder, withIntermediateDirectories: true)
        var bytes = 0
        var cachedPages = 0
        for index in 0..<pages {
            guard let data = imageData(index), !data.isEmpty else { continue }
            let file = folder.appendingPathComponent(String(format: "%04d.jpg", index))
            guard (try? data.write(to: file, options: .atomic)) != nil else { continue }
            bytes += data.count
            cachedPages += 1
        }
        guard cachedPages > 0 else {
            try? manager.removeItem(at: folder)
            return nil
        }
        let manifest: [String: Any] = [
            "bookID": bookID,
            "title": title,
            "pages": pages,
            "cachedPages": cachedPages,
            "bytes": bytes,
            "cachedAt": ISO8601DateFormatter().string(from: Date())
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: manifest, options: [.prettyPrinted]),
              (try? data.write(to: manifestURL, options: .atomic)) != nil else {
            try? manager.removeItem(at: folder)
            return nil
        }
        return bytes + data.count
    }

    // MARK: - 通用查询 / 清理

    @discardableResult
    static func remove(bookID: String) -> Int? {
        let manager = FileManager.default
        var freed = 0
        var removed = false
        if let url = manifestURL(for: bookID) {
            let size = recursiveSize(url)
            if (try? manager.removeItem(at: url)) != nil { freed += size; removed = true }
        }
        if let url = folder(for: bookID) {
            let size = recursiveSize(url)
            if (try? manager.removeItem(at: url)) != nil { freed += size; removed = true }
        }
        return removed ? freed : nil
    }

    static func isCached(bookID: String) -> Bool {
        let manager = FileManager.default
        if let url = manifestURL(for: bookID), manager.fileExists(atPath: url.path) { return true }
        if let url = folder(for: bookID), manager.fileExists(atPath: url.path) { return true }
        return false
    }

    @discardableResult
    static func removeAll() -> Int {
        guard let directory else { return 0 }
        let manager = FileManager.default
        guard let names = try? manager.contentsOfDirectory(atPath: directory.path) else { return 0 }
        var freed = 0
        for name in names {
            let url = directory.appendingPathComponent(name)
            let size = recursiveSize(url)
            if (try? manager.removeItem(at: url)) != nil { freed += size }
        }
        return freed
    }

    static func totalBytes() -> Int {
        guard let directory else { return 0 }
        return recursiveSize(directory)
    }

    private static func recursiveSize(_ url: URL) -> Int {
        let manager = FileManager.default
        var isDirectory: ObjCBool = false
        guard manager.fileExists(atPath: url.path, isDirectory: &isDirectory) else { return 0 }
        if !isDirectory.boolValue {
            return (try? manager.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.intValue ?? 0
        }
        guard let enumerator = manager.enumerator(
            at: url, includingPropertiesForKeys: [.fileSizeKey], options: [.skipsHiddenFiles]
        ) else { return 0 }
        var total = 0
        for case let fileURL as URL in enumerator {
            total += (try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        }
        return total
    }
}

/// 缓存与空间页的真实磁盘统计。
///
/// 以前这里两行写死的 12.4 MB / 36.2 MB，清理只把内存数字清零，磁盘上
/// 一个字节都没动。现在三类缓存都数真实目录，清理也真的删文件：
/// - 章节：LegadoCore 的章节正文缓存（`Application Support/Legado/ChapterContent`）；
/// - 图片：漫画降采样页图（`ImageCacheStore`）；
/// - 音频：导入到沙箱的音频文件（`AudioBooks`，用户文件，不随缓存清理删除）。
enum CacheUsage {
    struct Snapshot: Sendable {
        var chapterBytes: Int
        var imageBytes: Int
        var audioBytes: Int
        /// 清理音频时没删掉的文件（正在播放、占用中），界面要如实说。
        var audioSkipped: Int = 0
    }

    static let audioDirectoryName = "AudioBooks"

    static func audioDirectory() -> URL? {
        guard let base = LibraryStore.shared.directory else { return nil }
        return base.appendingPathComponent(audioDirectoryName, isDirectory: true)
    }

    /// 只读统计，不触发缓存目录的创建与迁移以外的副作用。
    static func snapshot() async -> Snapshot {
        let chapterBytes = (try? await ChapterContentCache.live().statistics().bytes) ?? 0
        return await Task.detached(priority: .utility) {
            Snapshot(
                chapterBytes: chapterBytes,
                imageBytes: ImageCacheStore.totalBytes(),
                audioBytes: directorySize(audioDirectory())
            )
        }.value
    }

    /// 清空章节正文缓存，返回真实释放的字节数。
    static func clearChapters() async -> Int {
        let before = (try? await ChapterContentCache.live().statistics().bytes) ?? 0
        try? await ChapterContentCache.live().removeAll()
        let after = (try? await ChapterContentCache.live().statistics().bytes) ?? 0
        return max(before - after, 0)
    }

    @discardableResult
    static func clearImages() -> Int {
        ImageCacheStore.removeAll()
    }

    /// 删除导入到沙箱的音频副本。返回 (释放字节数, 删不掉的文件数)。
    /// 用户正在播放的那一份会被系统占用，删不掉属正常，不静默吞掉。
    static func clearAudio() -> (freed: Int, skipped: Int) {
        guard let directory = audioDirectory() else { return (0, 0) }
        let manager = FileManager.default
        guard let names = try? manager.contentsOfDirectory(atPath: directory.path) else { return (0, 0) }
        var freed = 0
        var skipped = 0
        for name in names {
            let url = directory.appendingPathComponent(name)
            let size = fileSize(url)
            do {
                try manager.removeItem(at: url)
                freed += size
            } catch {
                skipped += 1
            }
        }
        return (freed, skipped)
    }

    private static func directorySize(_ url: URL?) -> Int {
        guard let url, let enumerator = FileManager.default.enumerator(
            at: url, includingPropertiesForKeys: [.fileSizeKey], options: [.skipsHiddenFiles]
        ) else { return 0 }
        var total = 0
        for case let fileURL as URL in enumerator {
            total += (try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        }
        return total
    }

    private static func fileSize(_ url: URL) -> Int {
        (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
    }
}
