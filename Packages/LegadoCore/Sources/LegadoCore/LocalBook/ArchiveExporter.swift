import Foundation
import ZIPFoundation

/// 把若干命名文件打成一个真正的 ZIP 容器。
/// 不写中间文件、不解压，主要用于导出 books.json / notes.md / annotations.md 这类小文件组。
public struct ArchiveExportItem: Sendable {
    public let name: String
    public let data: Data

    public init(name: String, data: Data) {
        self.name = name
        self.data = data
    }
}

public enum ArchiveExportError: Error, LocalizedError, Sendable {
    case invalidName(String)
    case empty

    public var errorDescription: String? {
        switch self {
        case .invalidName(let name): "不能打包名为「\(name)」的文件：请使用不含路径分隔词的普通文件名"
        case .empty: "没有可导出的内容"
        }
    }
}

public struct ArchiveExporter: Sendable {
    /// 文件名单向校验：只接受普通文件名，杜绝把导出写成路径穿越。
    public static func write(_ items: [ArchiveExportItem], to url: URL) throws {
        guard !items.isEmpty else { throw ArchiveExportError.empty }
        var seen = Set<String>()
        for item in items {
            let name = item.name
            guard !name.isEmpty, !name.hasPrefix("."),
                  !name.contains("/"), !name.contains("\\"), !name.contains("\0"),
                  seen.insert(name).inserted else {
                throw ArchiveExportError.invalidName(name)
            }
        }
        let manager = FileManager.default
        try manager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? manager.removeItem(at: url)
        let archive = try Archive(url: url, accessMode: .create)
        for item in items {
            let data = item.data
            try archive.addEntry(with: item.name, type: .file, uncompressedSize: Int64(data.count)) { _, _ in data }
        }
    }
}
