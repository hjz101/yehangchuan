import Foundation
import SwiftRAR
import SWCompression
import ZIPFoundation

/// 多格式漫画压缩包读取器：CBZ/ZIP 走 ZIPFoundation 流式读取，
/// CBR/RAR 走 SwiftRAR，7z 走 SWCompression。三者对外是同一套页索引，
/// 都只把「图片条目」纳入页序，不做任何落盘解包。
public struct ComicArchiveSet {
    private enum Backend {
        case zip(ComicArchive)
        case rar(RARReader, [String: RARReader.Entry])
        case sevenZip([String: Data])
    }

    private let backend: Backend
    private let report: ComicBookReport
    private static let maximumContainerSize = 200 * 1_024 * 1_024
    /// 7z 没有「只读头部」的公开 API，`SevenZipContainer.open` 会把所有条目解压出来。
    /// 解压后再按条目声明大小拒绝解压炸弹，避免整本数据继续被复制保留。
    private static let maximumSevenZipUncompressedSize = 1_024 * 1_024 * 1_024

    public init(url: URL) throws {
        try self.init(url: url, pageLimit: ComicArchive.pageLimit, maximumUncompressedSize: Self.maximumSevenZipUncompressedSize)
    }

    init(url: URL, pageLimit: Int, maximumUncompressedSize: Int) throws {
        let ext = url.pathExtension.lowercased()
        let title = url.deletingPathExtension().lastPathComponent
        switch ext {
        case "zip", "cbz":
            let archive = try ComicArchive(url: url)
            backend = .zip(archive)
            report = archive.info
        case "rar", "cbr":
            let reader = try RARReader(source: FileSource(url: url), limits: .default)
            var pages: [String: RARReader.Entry] = [:]
            for entry in reader.entries where ComicArchive.isImage(entry.name) && ComicArchive.safePath(entry.name) {
                guard entry.size <= UInt64(ComicArchive.pageLimit), pages[entry.name] == nil else {
                    throw ComicBookError.resourceTooLarge
                }
                pages[entry.name] = entry
            }
            guard !pages.isEmpty else { throw ComicBookError.noImages }
            backend = .rar(reader, pages)
            report = Self.makeReport(title: title, paths: Array(pages.keys))
        case "7z":
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            guard let size = attributes[.size] as? NSNumber, size.intValue <= Self.maximumContainerSize else {
                throw ComicBookError.resourceTooLarge
            }
            let data = try Data(contentsOf: url, options: .mappedIfSafe)
            let entries = try SevenZipContainer.open(container: data)
            // 先看条目声明的未压缩总量，超过上限直接拒绝，不再逐条保留数据。
            var declaredTotal = 0
            var totalOverflow = false
            for entry in entries where entry.info.type == .regular {
                guard let entrySize = entry.info.size else { continue }
                let (sum, overflow) = declaredTotal.addingReportingOverflow(entrySize)
                declaredTotal = overflow ? Int.max : sum
                totalOverflow = totalOverflow || overflow
            }
            guard !totalOverflow, declaredTotal <= maximumUncompressedSize else {
                throw ComicBookError.resourceTooLarge
            }
            var pages: [String: Data] = [:]
            var retained = 0
            for entry in entries where entry.info.type == .regular && ComicArchive.isImage(entry.info.name)
                && ComicArchive.safePath(entry.info.name) {
                guard pages[entry.info.name] == nil else { continue }
                // 单页超限就跳过这一页，不再让整本漫画失败。
                guard let entrySize = entry.info.size, entrySize <= pageLimit,
                      let bytes = entry.data, bytes.count <= pageLimit else { continue }
                retained += bytes.count
                guard retained <= maximumUncompressedSize else { throw ComicBookError.resourceTooLarge }
                pages[entry.info.name] = bytes
            }
            guard !pages.isEmpty else { throw ComicBookError.noImages }
            backend = .sevenZip(pages)
            report = Self.makeReport(title: title, paths: Array(pages.keys))
        default:
            throw ComicBookError.unsupportedFormat
        }
    }

    public var info: ComicBookReport { report }

    public func pageData(_ page: ComicPage) throws -> Data {
        switch backend {
        case .zip(let archive):
            return try archive.pageData(page)
        case .rar(let reader, let entries):
            guard let entry = entries[page.path] else { throw ComicBookError.missingPage(page.path) }
            return try reader.data(for: entry)
        case .sevenZip(let pages):
            guard let data = pages[page.path] else { throw ComicBookError.missingPage(page.path) }
            return data
        }
    }

    public func thumbnail(_ page: ComicPage, maxPixelSize: Int = 1600) throws -> Data {
        let data = try pageData(page)
        return ComicArchive.downsample(data, maxPixelSize: maxPixelSize) ?? data
    }

    // MARK: 一次性访问

    public static func supports(_ url: URL) -> Bool {
        ["zip", "cbz", "rar", "cbr", "7z"].contains(url.pathExtension.lowercased())
    }

    public static func inspect(url: URL) throws -> ComicBookReport {
        try ComicArchiveSet(url: url).info
    }

    public static func pageData(url: URL, path: String) throws -> Data {
        let book = try ComicArchiveSet(url: url)
        guard let page = book.info.pages.first(where: { $0.path == path }) else {
            throw ComicBookError.missingPage(path)
        }
        return try book.pageData(page)
    }

    public static func thumbnail(url: URL, path: String, maxPixelSize: Int = 1600) throws -> Data {
        let book = try ComicArchiveSet(url: url)
        guard let page = book.info.pages.first(where: { $0.path == path }) else {
            throw ComicBookError.missingPage(path)
        }
        return try book.thumbnail(page, maxPixelSize: maxPixelSize)
    }

    private static func makeReport(title: String, paths: [String]) -> ComicBookReport {
        let ordered = paths.sorted(by: ComicArchive.naturalLess)
        var chapters: [String] = []
        var seen = Set<String>()
        let pages = ordered.enumerated().map { index, path -> ComicPage in
            let parts = path.split(separator: "/", maxSplits: 1)
            let folder = parts.count > 1 ? String(parts[0]) : ""
            let chapter = folder.isEmpty ? "全本" : ComicArchive.cleanChapterName(folder)
            if seen.insert(chapter).inserted { chapters.append(chapter) }
            return ComicPage(index: index, path: path, chapter: chapter)
        }
        return ComicBookReport(title: title, pages: pages, chapterTitles: chapters)
    }
}
