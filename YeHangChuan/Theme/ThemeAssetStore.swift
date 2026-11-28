import Foundation
import CryptoKit

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

// MARK: - 主题资产内容寻址存储（P3-01）
//
// 资产一律以 sha256 前 32 hex 命名，引用只存 assetID（绝不存绝对路径）。
// 写入：.part → 读回核对 sha256 → .atomic rename；先资产后索引（索引是提交点）。
// 图片降采样最长边 2048；>20MB 或 >6000px 拒绝。统一缓存避免 30+ 处各自解码 OOM。
// 孤儿清理在 ThemeStore 里做（pending-delete + 二次核对，运维评审 G4）。

final class ThemeAssetStore {
    static let shared = ThemeAssetStore()

    let directory: URL
    private let fileManager = FileManager.default
    private let cache = NSCache<NSString, CachedImage>()
    private let queue = DispatchQueue(label: "yehangchuan.theme.assets", qos: .utility)

    /// 图片降采样缓存项（内存，可随 didReceiveMemoryWarning 丢弃重建）。
    final class CachedImage {
        let data: Data
        init(data: Data) { self.data = data }
    }

    init(directory: URL? = nil) {
        if let directory {
            self.directory = directory
        } else {
            let base = FileManager.default.urls(
                for: .applicationSupportDirectory, in: .userDomainMask
            )[0].appendingPathComponent("YeHangChuan/Themes/Assets", isDirectory: true)
            self.directory = base
        }
        try? fileManager.createDirectory(at: self.directory, withIntermediateDirectories: true)
        cache.countLimit = 12          // 2048² RGBA ≈ 16MB/张，12 张 ≈ 192MB 上限
        cache.totalCostLimit = 192 * 1024 * 1024
    }

    // MARK: 写入

    enum ImportError: LocalizedError {
        case tooLarge(Int)
        case pixelTooLarge(Int)
        case badExtension(String)
        case checksumMismatch
        case decodeFailed

        var errorDescription: String? {
            switch self {
            case .tooLarge: return "资产超过 20MB 上限"
            case .pixelTooLarge: return "图片边长超过 6000px"
            case .badExtension: return "不支持的资产格式"
            case .checksumMismatch: return "资产校验失败"
            case .decodeFailed: return "图片无法解码"
            }
        }
    }

    /// 导入资产，返回 AssetRef。同步执行（业务层包在 Task.detached(.utility)）。
    @discardableResult
    func importAsset(data: Data, ext: String) throws -> AssetRef {
        let lower = ext.lowercased()
        guard AssetRef.allowedExtensions.contains(lower) else {
            throw ImportError.badExtension(ext)
        }
        guard data.count <= 20 * 1024 * 1024 else {
            throw ImportError.tooLarge(data.count)
        }

        var payload = data
        var pixelWidth: Int?
        var pixelHeight: Int?

        // 图片降采样到最长边 2048。
        if isImage(lower) {
            guard let image = decodeImage(data) else { throw ImportError.decodeFailed }
            let w = Int(image.size.width)
            let h = Int(image.size.height)
            guard w <= 6000, h <= 6000 else {
                throw ImportError.pixelTooLarge(max(w, h))
            }
            pixelWidth = w
            pixelHeight = h
            if max(w, h) > 2048 {
                let scale = 2048.0 / Double(max(w, h))
                let target = CGSize(width: Double(w) * scale, height: Double(h) * scale)
                guard let resized = resize(image, to: target),
                      let encoded = encodeImage(resized, ext: lower) else {
                    throw ImportError.decodeFailed
                }
                payload = encoded
            }
        }

        let digest = SHA256.hash(data: payload)
        let fullHex = digest.map { String(format: "%02x", $0) }.joined()
        let assetID = String(fullHex.prefix(32))

        // 已存在同内容资产：直接返回引用（去重）。
        let finalURL = directory.appendingPathComponent("\(assetID).\(lower)")
        if fileManager.fileExists(atPath: finalURL.path) {
            return AssetRef(
                id: assetID, kind: isFont(lower) ? .font : .image, ext: lower,
                byteCount: payload.count, pixelWidth: pixelWidth, pixelHeight: pixelHeight
            )
        }

        // .part → 读回核对 → .atomic rename。
        let partURL = directory.appendingPathComponent("\(assetID).\(lower).part")
        try payload.write(to: partURL, options: .atomic)
        guard let written = try? Data(contentsOf: partURL),
              SHA256.hash(data: written).map({ String(format: "%02x", $0) }).joined() == fullHex else {
            try? fileManager.removeItem(at: partURL)
            throw ImportError.checksumMismatch
        }
        try fileManager.moveItem(at: partURL, to: finalURL)

        return AssetRef(
            id: assetID, kind: isFont(lower) ? .font : .image, ext: lower,
            byteCount: payload.count, pixelWidth: pixelWidth, pixelHeight: pixelHeight
        )
    }

    // MARK: 读取

    func url(for ref: AssetRef) -> URL? {
        guard AssetRef.isValidAssetID(ref.id),
              AssetRef.allowedExtensions.contains(ref.ext) else { return nil }
        return directory.appendingPathComponent("\(ref.id).\(ref.ext)")
    }

    func url(assetID: String, ext: String) -> URL? {
        guard AssetRef.isValidAssetID(assetID),
              AssetRef.allowedExtensions.contains(ext) else { return nil }
        return directory.appendingPathComponent("\(assetID).\(ext)")
    }

    /// 降采样缓存读取（避免 30+ 处各自解码）。
    func cachedImageData(for ref: AssetRef) -> Data? {
        guard let url = url(for: ref) else { return nil }
        let key = "\(ref.id).\(ref.ext)" as NSString
        if let cached = cache.object(forKey: key) { return cached.data }
        guard let data = try? Data(contentsOf: url) else { return nil }
        cache.setObject(CachedImage(data: data), forKey: key, cost: data.count)
        return data
    }

    func clearCache() { cache.removeAllObjects() }

    // MARK: 删除（由 ThemeStore 的 pending-delete 调用）

    func remove(assetID: String, ext: String) {
        guard let url = url(assetID: assetID, ext: ext) else { return }
        try? fileManager.removeItem(at: url)
        cache.removeObject(forKey: "\(assetID).\(ext)" as NSString)
    }

    // MARK: 私有工具

    private func isImage(_ ext: String) -> Bool {
        ["png", "jpg", "jpeg", "heic", "webp"].contains(ext)
    }

    private func isFont(_ ext: String) -> Bool {
        ["ttf", "otf"].contains(ext)
    }

    private func decodeImage(_ data: Data) -> PlatformImage? {
        #if canImport(UIKit)
        return UIImage(data: data)
        #else
        return NSImage(data: data)
        #endif
    }

    private func resize(_ image: PlatformImage, to size: CGSize) -> PlatformImage? {
        #if canImport(UIKit)
        UIGraphicsImageRenderer(size: size).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
        #else
        let result = NSImage(size: size)
        result.lockFocus()
        image.draw(in: NSRect(origin: .zero, size: size))
        result.unlockFocus()
        return result
        #endif
    }

    private func encodeImage(_ image: PlatformImage, ext: String) -> Data? {
        #if canImport(UIKit)
        if ext == "png" { return image.pngData() }
        return image.jpegData(compressionQuality: 0.82)
        #else
        guard let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff) else { return nil }
        if ext == "png" { return bitmap.representation(using: .png, properties: [:]) }
        return bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.82])
        #endif
    }
}

#if canImport(UIKit)
private typealias PlatformImage = UIImage
#else
private typealias PlatformImage = NSImage
#endif
