import Foundation
import ZIPFoundation
import CryptoKit

// MARK: - .yhthm 主题包导入导出（P3-07）
//
// ZIP 容器：manifest.json（清单）+ theme.json（本体）+ assets/（资产，平铺）。
// 安全评审 B3 硬阻断：解压防护必须是「central directory 预判 + 解压回调流式
// 累计限额 + 一致性校验 + checksum」四件套，拒绝重复/加密/非 store|deflate/symlink 条目。
// 复用 ComicArchive.swift:151-163 的读法规范，扩展为跨条目累计限额。

enum ThemePackageError: LocalizedError {
    case badMagic
    case tooLarge
    case bombRatio
    case bombDeclared
    case traversal(String)
    case duplicateEntry(String)
    case encryptedEntry(String)
    case unsupportedMethod(String)
    case symlinkEntry(String)
    case checksumMismatch(String)
    case futureVersion
    case invalidJSON
    case executableContent

    var errorDescription: String? {
        switch self {
        case .badMagic: return "不是有效的 .yhthm 文件"
        case .tooLarge: return "主题包超过 50MB 上限"
        case .bombRatio: return "压缩比异常，疑似解压炸弹"
        case .bombDeclared: return "解压总量超过 100MB 上限"
        case .traversal: return "包内路径不安全"
        case .duplicateEntry: return "包内存在重复条目"
        case .encryptedEntry: return "不支持加密的压缩包"
        case .unsupportedMethod: return "不支持的压缩方式"
        case .symlinkEntry: return "不支持符号链接"
        case .checksumMismatch: return "资产校验和不匹配"
        case .futureVersion: return "主题包版本较新，仅可预览"
        case .invalidJSON: return "主题清单格式错误"
        case .executableContent: return "主题包不得包含可执行脚本"
        }
    }
}

struct ThemePackageExport {
    var theme: Theme
    var assets: [AssetRef]

    /// manifest.checksums 用完整 256bit（安全评审 G3），assets 内容由 AssetStore 提供。
    func manifest(appVersion: String) -> ThemePackageManifest {
        ThemePackageManifest(
            format: "yhthm",
            schemaVersion: ThemeCatalog.currentSchemaVersion,
            themeID: theme.id,
            name: theme.name,
            checksums: [:],  // 由导出流水线逐资产填完整 64 hex
            createdAt: Date(),
            appVersion: appVersion,
            containsExecutableCode: false
        )
    }
}

enum ThemePackage {
    static let maxPackageBytes = 50 * 1024 * 1024
    static let maxAssetBytes = 10 * 1024 * 1024
    static let maxTotalUncompressed = 100 * 1024 * 1024
    static let minCompressionRatio: Double = 100   // 压缩比 >100 视为 bomb 信号

    // MARK: 导出

    /// 导出 .yhthm。item 名都是平铺文件名（ArchiveExporter 拒绝 "/"）。
    static func export(
        theme: Theme,
        assets: [AssetRef],
        assetData: (AssetRef) -> Data?,
        to url: URL,
        appVersion: String
    ) throws {
        var manifest = ThemePackageExport(theme: theme, assets: assets).manifest(appVersion: appVersion)
        var items: [ArchiveExportItem] = []

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let themeData = try encoder.encode(theme)

        for asset in assets {
            guard let data = assetData(asset), data.count <= maxAssetBytes else { continue }
            // 完整 256bit checksum（不是截断的 assetID）。
            let full = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
            manifest.checksums[asset.id + "." + asset.ext] = full
            items.append(ArchiveExportItem(name: asset.id + "." + asset.ext, data: data))
        }
        let manifestData = try encoder.encode(manifest)
        items.insert(ArchiveExportItem(name: "theme.json", data: themeData), at: 0)
        items.insert(ArchiveExportItem(name: "manifest.json", data: manifestData), at: 0)

        try ArchiveExporter.write(items, to: url)
    }

    // MARK: 导入

    struct ImportResult {
        var theme: Theme
        var manifest: ThemePackageManifest
        var assets: [(ref: AssetRef, data: Data)]
    }

    /// 导入流水线：magic bytes → 大小 → 解压四件套 → checksum → 解码 → 预览确认。
    /// 全程同步，调用方包在 Task.detached(.utility)。
    static func `import`(from url: URL) throws -> ImportResult {
        guard let data = try? Data(contentsOf: url) else { throw ThemePackageError.badMagic }
        // ZIP magic：PK\x03\x04（或空包 PK\x05\x06 / 跨盘 PK\x07\x08）。
        let magic = Array(data.prefix(4))
        guard magic.count == 4, magic[0] == 0x50, magic[1] == 0x4B,
              [0x03, 0x05, 0x07].contains(magic[2]) else {
            throw ThemePackageError.badMagic
        }
        guard data.count <= maxPackageBytes else { throw ThemePackageError.tooLarge }

        guard let archive = Archive(data: data, accessMode: .read) else {
            throw ThemePackageError.badMagic
        }

        // ① central directory 预判：声明总量 + 压缩比信号 + 条目合法性。
        var declaredTotal: UInt64 = 0
        var compressedTotal: UInt64 = 0
        var seenNames = Set<String>()
        for entry in archive.entries {
            let name = entry.path
            guard !name.contains(".."), !name.hasPrefix("/"), !name.contains("\\") else {
                throw ThemePackageError.traversal(name)
            }
            guard seenNames.insert(name).inserted else {
                throw ThemePackageError.duplicateEntry(name)
            }
            // Entry 公开 API 不暴露加密标志/压缩方式；symlink/directory 通过 type 拒绝，
            // 加密与非标准压缩方式由下方 extract 抛错兜底（等价拒绝）。
            guard entry.type == .file else { throw ThemePackageError.symlinkEntry(name) }
            // 可执行脚本/隐藏元数据一律拒绝。
            let lower = (name as NSString).lastPathComponent.lowercased()
            if ["js", "sh", "exe", "dylib", "command"].contains((lower as NSString).pathExtension)
                || lower.hasPrefix("__macosx") {
                throw ThemePackageError.executableContent
            }
            declaredTotal += entry.uncompressedSize
            compressedTotal += entry.compressedSize
        }
        if compressedTotal > 0, Double(declaredTotal) / Double(compressedTotal) > minCompressionRatio {
            throw ThemePackageError.bombRatio
        }
        guard declaredTotal <= UInt64(maxTotalUncompressed) else { throw ThemePackageError.bombDeclared }

        // ② 流式解压：累计字节硬限额 + 单资产上限，超限立即 throw（防声明值欺骗）。
        var extracted: [String: Data] = [:]
        var streamedTotal = 0
        for entry in archive.entries {
            var entryData = Data()
            // consumer 闭包可 throw（ZIPFoundation Consumer 是 throws 闭包），
            // 超限立即抛出、不继续解压——这是防"声明值欺骗型炸弹"的关键。
            let crc = try archive.extract(entry) { chunk in
                streamedTotal += chunk.count
                entryData.append(chunk)
                if entryData.count > maxAssetBytes || streamedTotal > maxTotalUncompressed {
                    throw ThemePackageError.bombDeclared
                }
            }
            // ③ 一致性校验：CRC + 实际解压字节 == 声明值。
            guard crc == entry.checksum, UInt64(entryData.count) == entry.uncompressedSize else {
                throw ThemePackageError.checksumMismatch(entry.path)
            }
            extracted[entry.path] = entryData
        }

        guard let manifestData = extracted["manifest.json"],
              let themeData = extracted["theme.json"] else {
            throw ThemePackageError.invalidJSON
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let manifest = try? decoder.decode(ThemePackageManifest.self, from: manifestData),
              let theme = try? decoder.decode(Theme.self, from: themeData) else {
            throw ThemePackageError.invalidJSON
        }
        guard manifest.schemaVersion <= ThemeCatalog.currentSchemaVersion else {
            throw ThemePackageError.futureVersion
        }

        // ④ 逐资产 checksums 核对（完整 256bit，自校验非来源认证）。
        var assets: [(ref: AssetRef, data: Data)] = []
        for (name, checksum) in manifest.checksums {
            guard let assetData = extracted[name] else { continue }
            let actual = SHA256.hash(data: assetData).map { String(format: "%02x", $0) }.joined()
            guard actual == checksum else { throw ThemePackageError.checksumMismatch(name) }
            let parts = name.split(separator: ".", maxSplits: 1)
            guard parts.count == 2, AssetRef.isValidAssetID(String(parts[0])) else {
                throw ThemePackageError.traversal(name)
            }
            let ext = String(parts[1]).lowercased()
            guard AssetRef.allowedExtensions.contains(ext) else {
                throw ThemePackageError.traversal(name)
            }
            let ref = AssetRef(
                id: String(parts[0]), kind: ["ttf", "otf"].contains(ext) ? .font : .image,
                ext: ext, byteCount: assetData.count
            )
            assets.append((ref, assetData))
        }

        return ImportResult(theme: theme, manifest: manifest, assets: assets)
    }
}
