import Foundation
import CoreText

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

// MARK: - 导入字体注册（P2-04）
//
// 决策②：App 不内置任何第三方字体；只注册用户从文件 App 导入、落在
// ThemeStore Assets/ 的字体资产。作用域 .process（每次启动重注册，不污染系统）。
// 技术评审 B：注册必须在 catalog 解码取得 assetIDs 之后触发（ThemeApplicator 叶子），
// 不在 App.init() —— 那时 @State store 尚未触发 AppStore.init，拿不到资产清单。

enum FontRegistry {
    /// 每个已成功注册的 assetID → 真实 PostScript 名（CoreText 与 SwiftUI 共用此名）。
    private(set) static var registered: [String: String] = [:]

    /// 在 catalog 解码完成后调用（ThemeApplicator 首次 appear）。
    /// 只做 .process 注册，失败逐个回退、不阻塞冷启动。
    static func registerAll(assets: [AssetRef], assetURL: (AssetRef) -> URL?) {
        registered.removeAll()
        registeredURLs.removeAll()
        for asset in assets where asset.kind == .font {
            guard let url = assetURL(asset) else { continue }
            register(asset: asset, url: url)
        }
    }

    @discardableResult
    static func register(asset: AssetRef, url: URL) -> Bool {
        guard asset.ext == "ttf" || asset.ext == "otf" else { return false }
        guard FileManager.default.fileExists(atPath: url.path) else { return false }

        let urls = [url] as CFArray
        // .process 作用域：不写系统字体库，不影响其他 App。
        let ok = CTFontManagerRegisterFontsForURLs(urls, .process, nil)
        guard ok, let name = postScriptName(for: url) else { return false }
        registered[asset.id] = name
        if !registeredURLs.contains(url) { registeredURLs.append(url) }
        return true
    }

    /// 提取真实 PostScript 名。SwiftUI Font.custom 与 CoreText CTFont 用同一个名字，
    /// 避免「预览一种字、分页排另一种」。
    static func postScriptName(for url: URL) -> String? {
        let descriptors = CTFontManagerCreateFontDescriptorsFromURL(url as CFURL) as? [CTFontDescriptor]
        guard let descriptors, let first = descriptors.first else { return nil }
        let font = CTFontCreateWithFontDescriptor(first, 12, nil)
        let name = CTFontCopyPostScriptName(font)
        return (name as String?).flatMap { $0.isEmpty ? nil : $0 }
    }

    /// 解析字体族：导入字体注册成功 → 用 PostScript 名；失败 → 系统 design 回退。
    /// 回退链：imported(失败) → system(原 design) → system.default，绝不空白。
    static func resolvedName(for family: FontFamilySpec) -> (postScript: String?, systemDesign: FontDesignSpec) {
        switch family {
        case let .imported(assetID, postScriptName):
            if let registeredName = registered[assetID], !registeredName.isEmpty {
                return (registeredName, .default)
            }
            // 已记录的名字但本次注册失败：仍尝试按名字取（系统可能已缓存）。
            return (postScriptName.isEmpty ? nil : postScriptName, .default)
        case let .system(design):
            return (nil, design)
        }
    }

    /// CoreText 字体：阅读正文排版用。与 SwiftUI Font.custom 共用 PostScript 名。
    static func ctFont(for family: FontFamilySpec, size: CGFloat) -> CTFont {
        let resolved = resolvedName(for: family)
        if let name = resolved.postScript {
            return CTFontCreateWithName(name as CFString, size, nil)
        }
        return CTFontCreateWithName(systemPostScript(for: resolved.systemDesign) as CFString, size, nil)
    }

    /// 系统 design 对应的 PostScript 名（Apple 系统字体，非第三方）。
    static func systemPostScript(for design: FontDesignSpec) -> String {
        switch design {
        case .serif: return "Songti-SC-Regular"
        case .rounded: return "PingFangSC-Regular"
        case .monospaced: return "Menlo-Regular"
        case .default: return "PingFangSC-Regular"
        }
    }

    /// 卸载本进程注册的所有字体（测试/重置用）。
    static func unregisterAll() {
        CTFontManagerUnregisterFontsForURLs(registeredURLs as CFArray, .process, nil)
        registered.removeAll()
    }

    private(set) static var registeredURLs: [URL] = []
}
