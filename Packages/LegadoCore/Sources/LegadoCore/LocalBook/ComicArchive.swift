import Foundation
import ImageIO
import ZIPFoundation

/// 漫画压缩包（CBZ / ZIP）的按需读取器。
///
/// 和 EPUBBook 一样，从不把不可信的压缩包路径解包到磁盘：只在内存里建立
/// 校验过的条目索引，读单页时流式解压并校验 checksum。页序用自然排序，
/// 因为漫画文件名里的数字宽度极不统一（001.jpg / 2.jpg / page-10.jpg）。
public enum ComicBookError: Error, LocalizedError, Sendable {
    case invalidArchive
    case noImages
    case missingPage(String)
    case resourceTooLarge
    case unsupportedFormat

    public var errorDescription: String? {
        switch self {
        case .invalidArchive: "漫画压缩包已损坏或不是有效的 ZIP"
        case .noImages: "压缩包内没有可读取的图片"
        case .missingPage(let path): "漫画页不存在：\(path)"
        case .resourceTooLarge: "单张漫画页过大，无法安全读取"
        case .unsupportedFormat: "当前只支持 CBZ / ZIP 漫画压缩包"
        }
    }
}

public struct ComicPage: Sendable, Hashable {
    public let index: Int
    /// 压缩包内已校验过的路径；读取时按此路径在条目索引里精确查找。
    public let path: String
    /// 按顶层文件夹归纳的「话」名；图片在根目录时为「全本」。
    public let chapter: String

    public init(index: Int, path: String, chapter: String) {
        self.index = index
        self.path = path
        self.chapter = chapter
    }
}

public struct ComicBookReport: Sendable {
    public let title: String
    public let pages: [ComicPage]
    public let chapterTitles: [String]
    public var pageCount: Int { pages.count }

    public init(title: String, pages: [ComicPage], chapterTitles: [String]) {
        self.title = title
        self.pages = pages
        self.chapterTitles = chapterTitles
    }
}

/// 非 Sendable：Archive 来自 ZIPFoundation，只在同步函数内短命使用。
/// 跨调用边界传递的是 Sendable 的 ComicBookReport / ComicPage。
public struct ComicArchive {
    private let archive: Archive
    private let entries: [String: Entry]
    private let report: ComicBookReport

    /// 单页上限。比 EPUB 正文宽松，但仍能挡住 zip bomb 式的一页超大图。
    private static let pageLimit = 64 * 1_024 * 1_024
    private static let maximumEntries = 50_000
    private static let imageExtensions: Set<String> = [
        "png", "jpg", "jpeg", "gif", "webp", "bmp", "heic", "heif", "avif", "tif", "tiff"
    ]

    public init(url: URL) throws {
        guard url.isFileURL, ["zip", "cbz"].contains(url.pathExtension.lowercased()) else {
            throw ComicBookError.unsupportedFormat
        }
        let archive: Archive
        do { archive = try Archive(url: url, accessMode: .read) }
        catch { throw ComicBookError.invalidArchive }

        var imagePaths: [String] = []
        var entries: [String: Entry] = [:]
        for entry in archive {
            guard entries.count < Self.maximumEntries else { throw ComicBookError.resourceTooLarge }
            // 目录与 symlink 一律不当成页面，天然挡住 zip-slip 的链接变体。
            guard entry.type == .file else { continue }
            guard Self.safePath(entry.path), entries[entry.path] == nil else { throw ComicBookError.invalidArchive }
            guard Self.isImage(entry.path) else { continue }
            entries[entry.path] = entry
            imagePaths.append(entry.path)
        }
        guard !imagePaths.isEmpty else { throw ComicBookError.noImages }
        imagePaths.sort(by: Self.naturalLess)

        var pages: [ComicPage] = []
        var chapterTitles: [String] = []
        var seenChapters: [String: Int] = [:]
        for path in imagePaths {
            let folder = path.split(separator: "/", maxSplits: 1).count > 1
                ? String(path.split(separator: "/", maxSplits: 1).first ?? "")
                : ""
            let chapter = folder.isEmpty ? "全本" : Self.cleanChapterName(folder)
            if seenChapters[chapter] == nil {
                seenChapters[chapter] = chapterTitles.count
                chapterTitles.append(chapter)
            }
            pages.append(ComicPage(index: pages.count, path: path, chapter: chapter))
        }
        self.archive = archive
        self.entries = entries
        self.report = ComicBookReport(
            title: url.deletingPathExtension().lastPathComponent,
            pages: pages,
            chapterTitles: chapterTitles
        )
    }

    public var info: ComicBookReport { report }

    public func pageData(_ page: ComicPage) throws -> Data {
        try Self.read(page.path, archive: archive, entries: entries)
    }

    /// 降采样缩略图（JPEG），用于条漫与缓存，避免整包高分辨率图进内存。
    public func thumbnail(_ page: ComicPage, maxPixelSize: Int = 1600) throws -> Data {
        let data = try pageData(page)
        guard let thumbnail = Self.downsample(data, maxPixelSize: maxPixelSize) else { return data }
        return thumbnail
    }

    // MARK: 一次性访问（供 service / reader 按需调用，不持有 Archive）

    public static func inspect(url: URL) throws -> ComicBookReport {
        try ComicArchive(url: url).info
    }

    public static func pageData(url: URL, path: String) throws -> Data {
        let book = try ComicArchive(url: url)
        guard let page = book.report.pages.first(where: { $0.path == path }) else {
            throw ComicBookError.missingPage(path)
        }
        return try book.pageData(page)
    }

    public static func thumbnail(url: URL, path: String, maxPixelSize: Int = 1600) throws -> Data {
        let book = try ComicArchive(url: url)
        guard let page = book.report.pages.first(where: { $0.path == path }) else {
            throw ComicBookError.missingPage(path)
        }
        return try book.thumbnail(page, maxPixelSize: maxPixelSize)
    }

    // MARK: 内部

    private static func read(_ path: String, archive: Archive, entries: [String: Entry]) throws -> Data {
        guard let entry = entries[path] else { throw ComicBookError.missingPage(path) }
        guard entry.uncompressedSize <= pageLimit else { throw ComicBookError.resourceTooLarge }
        var result = Data()
        let checksum = try archive.extract(entry) { chunk in
            guard result.count + chunk.count <= pageLimit else { throw ComicBookError.resourceTooLarge }
            result.append(chunk)
        }
        guard checksum == entry.checksum, result.count == entry.uncompressedSize else {
            throw ComicBookError.invalidArchive
        }
        return result
    }

    private static func downsample(_ data: Data, maxPixelSize: Int) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
                kCGImageSourceCreateThumbnailWithTransform: true
              ] as CFDictionary) else { return nil }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, "public.jpeg" as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.8] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return output as Data
    }

    private static func isImage(_ path: String) -> Bool {
        let name = (path as NSString).lastPathComponent
        guard !name.hasPrefix("."), name.lowercased() != "thumbs.db" else { return false }
        // macOS 打包压缩包时附带的资源分叉目录不是漫画页。
        guard !path.split(separator: "/").contains(where: { $0 == "__MACOSX" }) else { return false }
        return imageExtensions.contains((name as NSString).pathExtension.lowercased())
    }

    private static func cleanChapterName(_ folder: String) -> String {
        let name = (folder as NSString).lastPathComponent
        return name.isEmpty ? "全本" : name
    }

    private static func safePath(_ path: String) -> Bool {
        !path.isEmpty && !path.hasPrefix("/") && !path.contains("\\") && !path.contains("\0")
            && !path.split(separator: "/").contains("..")
    }

    /// 逐段比较，数字段按数值而非字典序 —— 保证 page-2 排在 page-10 前面。
    private static func naturalLess(_ lhs: String, _ rhs: String) -> Bool {
        let left = lhs.split(separator: "/").map(String.init)
        let right = rhs.split(separator: "/").map(String.init)
        for (a, b) in zip(left, right) where a != b {
            return naturalSegmentLess(a, b)
        }
        return left.count < right.count
    }

    private static func naturalSegmentLess(_ a: String, _ b: String) -> Bool {
        let an = Array(a)
        let bn = Array(b)
        var i = 0
        var j = 0
        while i < an.count && j < bn.count {
            if an[i].isNumber && bn[j].isNumber {
                var ai = i
                var bj = j
                while ai < an.count, an[ai].isNumber { ai += 1 }
                while bj < bn.count, bn[bj].isNumber { bj += 1 }
                let av = Int(String(an[i..<ai])) ?? 0
                let bv = Int(String(bn[j..<bj])) ?? 0
                if av != bv { return av < bv }
                // 数值相同则短的前面（001 < 0001），再退回字典序。
                if ai - i != bj - j { return ai - i < bj - j }
                i = ai
                j = bj
                continue
            }
            if an[i] != bn[j] { return an[i] < bn[j] }
            i += 1
            j += 1
        }
        return an.count < bn.count
    }
}
