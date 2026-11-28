import Foundation
import Observation
import SwiftUI

// MARK: - ThemeStore 独立持久化（P0-05）
//
// 目录：Application Support/YeHangChuan/Themes/
//   themes.json（提交点）+ themes.prev.json（仅当前可读时轮转）
//   themes.corrupt-<ts>.json + theme-decode-error.txt（留档）
//   Assets/<sha256-32>.{png,ttf,...}
// 写入：先资产后索引；索引 .atomic + .sortedKeys；sequence 防旧覆盖；200ms 合并。
// backend 三态：.legacy / .dualWrite / .themeStore，可一键回退。

@MainActor
@Observable
final class ThemeStore {
    enum Backend: String, Codable, Sendable {
        case legacy, dualWrite, themeStore
    }

    static let shared = ThemeStore()

    var catalog: ThemeCatalog
    var backend: Backend = .legacy
    /// 读 prev 恢复时的用户可见标记（运维评审 C3）。
    var recoveredFromPrevious = false
    /// 解码失败原因（同时写 theme-decode-error.txt）。
    var decodeError: String?

    private let root: URL
    private let fileManager = FileManager.default
    private var sequence = 0
    private var lastWrittenSequence = 0
    private var writeTask: Task<Void, Never>?
    private var didBootstrap = false
    /// 逐主题恢复时资产索引无法解析：先按只读状态启动，用户主动修改前不落盘，
    /// 避免把空 assets 写回、抹掉导入字体/背景图的引用。
    private var assetsIndexUnreadable = false

    init(root: URL? = nil) {
        if let root { self.root = root }
        else {
            let base = FileManager.default.urls(
                for: .applicationSupportDirectory, in: .userDomainMask
            )[0].appendingPathComponent("YeHangChuan", isDirectory: true)
            self.root = base.appendingPathComponent("Themes", isDirectory: true)
        }
        self.catalog = ThemeCatalog(
            schemaVersion: ThemeCatalog.currentSchemaVersion,
            activeThemeID: BuiltinThemes.defaultID,
            themes: BuiltinThemes.all,
            assets: [],
            skippedThemes: nil,
            pendingDelete: []
        )
    }

    // MARK: 路径

    var indexURL: URL { root.appendingPathComponent("themes.json") }
    var prevURL: URL { root.appendingPathComponent("themes.prev.json") }
    var assetsDir: URL { root.appendingPathComponent("Assets", isDirectory: true) }

    func assetURL(id: String, ext: String) -> URL? {
        guard AssetRef.isValidAssetID(id),
              AssetRef.allowedExtensions.contains(ext.lowercased()) else { return nil }
        return assetsDir.appendingPathComponent("\(id).\(ext.lowercased())")
    }

    // MARK: 启动同步读取

    /// 同步读 JSON（几十 KB / 几十毫秒），不解码图片/字体。
    /// 任何失败都 catch 到底、回落内置默认，绝不阻塞首帧或崩溃（B5）。
    func bootstrap() {
        guard !didBootstrap else { return }
        didBootstrap = true
        ensureDirectories()
        do {
            try loadCatalog()
        } catch {
            decodeError = "主题读取失败：\(error.localizedDescription)"
            writeDecodeError(decodeError!)
            catalog = defaultCatalog()
        }
    }

    private func defaultCatalog() -> ThemeCatalog {
        ThemeCatalog(
            schemaVersion: ThemeCatalog.currentSchemaVersion,
            activeThemeID: BuiltinThemes.defaultID,
            themes: BuiltinThemes.all,
            assets: [],
            skippedThemes: nil,
            pendingDelete: []
        )
    }

    private func ensureDirectories() {
        try? fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        try? fileManager.createDirectory(at: assetsDir, withIntermediateDirectories: true)
    }

    private func loadCatalog() throws {
        var data: Data?
        var usedPrev = false
        if fileManager.fileExists(atPath: indexURL.path),
           let d = try? Data(contentsOf: indexURL) {
            data = d
        } else if fileManager.fileExists(atPath: prevURL.path),
                  let d = try? Data(contentsOf: prevURL) {
            data = d
            usedPrev = true
        }

        guard let data else {
            // 首次启动：无文件，用内置默认并立即落盘一次。
            catalog = defaultCatalog()
            try persistCatalog(catalog)
            return
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        do {
            var loaded = try decoder.decode(ThemeCatalog.self, from: data)
            if loaded.schemaVersion > ThemeCatalog.currentSchemaVersion {
                // 未来版本只读降级：绝不写盘、不留档、不覆盖。
                decodeError = "主题版本较新（\(loaded.schemaVersion)），只读降级"
                catalog = loaded
                return
            }
            if loaded.schemaVersion < ThemeCatalog.currentSchemaVersion {
                loaded = ThemeCatalog.migrate(loaded, from: loaded.schemaVersion)
            }
            // 内置主题按 builtinRevision 刷新（未 customized 才覆盖）。
            loaded = refreshBuiltins(in: loaded)
            // 兼容历史数据：旧版把主题 id 截成 32 位，而 activeThemeID 仍是完整 UUID。
            _ = restoreTruncatedActiveThemeID(in: &loaded)
            // activeThemeID 指向坏主题/不存在 → 回退内置默认并提示。
            if !loaded.themes.contains(where: { $0.id == loaded.activeThemeID }) {
                loaded.activeThemeID = BuiltinThemes.defaultID
                decodeError = "当前主题不可用，已回退默认"
            }
            catalog = loaded
            recoveredFromPrevious = usedPrev
            if usedPrev {
                // 从 prev 恢复后立即重写主索引，恢复正常提交点。
                try persistCatalog(loaded)
            }
        } catch {
            // 整份 catalog 解码失败：先试逐主题兜底（单个坏主题不该丢掉整座主题库）。
            if let partiallyRecovered = decodeCatalogPerTheme(data, decoder: decoder) {
                var recovered = refreshBuiltins(in: partiallyRecovered)
                _ = restoreTruncatedActiveThemeID(in: &recovered)
                catalog = recovered
                decodeError = assetsIndexUnreadable
                    ? "主题资产索引无法解析，已只读恢复（下次修改前不覆盖原文件）"
                    : "部分主题损坏，已跳过并记录"
                writeDecodeError(decodeError!)
                return
            }
            // 仍失败：改名留档 + 写 decode-error.txt，再尝试 prev。
            quarantineCorruptFile(data)
            decodeError = "主题索引损坏：\(error.localizedDescription)"
            writeDecodeError(decodeError!)
            if fileManager.fileExists(atPath: prevURL.path),
               let prevData = try? Data(contentsOf: prevURL),
               let recovered = try? decoder.decode(ThemeCatalog.self, from: prevData) {
                catalog = refreshBuiltins(in: recovered)
                recoveredFromPrevious = true
                try persistCatalog(catalog)
            } else {
                catalog = defaultCatalog()
            }
        }
    }

    /// 整份 catalog 解码失败时的最后兜底：从原始 JSON 字典里逐个解主题，
    /// 好的留下、坏的记入 skippedThemes（沿用 Snapshot 逐分区兜底惯例）。
    /// 同时尽量解出 assets（能解多少解多少），避免下次写盘丢掉资产引用。
    private func decodeCatalogPerTheme(_ data: Data, decoder: JSONDecoder) -> ThemeCatalog? {
        guard let raw = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let rawThemes = raw["themes"] as? [[String: Any]] else { return nil }
        var good: [Theme] = []
        var skipped: [String] = []
        for rawTheme in rawThemes {
            guard let themeData = try? JSONSerialization.data(withJSONObject: rawTheme),
                  let theme = try? decoder.decode(Theme.self, from: themeData) else {
                skipped.append((rawTheme["id"] as? String) ?? "(unknown)")
                continue
            }
            good.append(theme)
        }
        guard !good.isEmpty else { return nil }

        var assets: [AssetRef] = []
        if let rawAssets = raw["assets"] as? [[String: Any]] {
            for rawAsset in rawAssets {
                guard let assetData = try? JSONSerialization.data(withJSONObject: rawAsset),
                      let ref = try? decoder.decode(AssetRef.self, from: assetData),
                      AssetRef.isValidAssetID(ref.id) else { continue }
                assets.append(ref)
            }
        } else if raw["assets"] != nil {
            // 结构损坏（assets 不是数组）：标记只读恢复，别用空索引覆盖原文件。
            assetsIndexUnreadable = true
        }

        return ThemeCatalog(
            schemaVersion: (raw["schemaVersion"] as? Int) ?? 1,
            activeThemeID: (raw["activeThemeID"] as? String) ?? BuiltinThemes.defaultID,
            themes: good,
            assets: assets,
            skippedThemes: skipped,
            pendingDelete: []
        )
    }

    private func refreshBuiltins(in catalog: ThemeCatalog) -> ThemeCatalog {
        var result = catalog
        for (index, theme) in result.themes.enumerated() where theme.builtin && !theme.customized {
            if let builtin = BuiltinThemes.theme(withID: theme.id),
               builtin.builtinRevision > theme.builtinRevision {
                result.themes[index] = builtin
            }
        }
        // 内置主题缺失时补齐（新版本新增预设）。
        let existing = Set(result.themes.map(\.id))
        for builtin in BuiltinThemes.all where !existing.contains(builtin.id) {
            result.themes.append(builtin)
        }
        return result
    }

    /// 兼容历史数据：旧版本曾把主题 id 截断成 32 位（assetID 上限），
    /// 而 Snapshot 里的 activeThemeID 仍是完整 UUID。精确匹配失败时，
    /// 用 activeThemeID 的前 32 位与 themes 中 id 做前缀匹配，唯一命中即恢复完整 id。
    /// 返回是否发生了修复；不直接落盘，交给下一次正常写入持久化。
    @discardableResult
    private func restoreTruncatedActiveThemeID(in catalog: inout ThemeCatalog) -> Bool {
        let activeThemeID = catalog.activeThemeID
        guard activeThemeID.count > ThemeLimits.assetID,
              !catalog.themes.contains(where: { $0.id == activeThemeID }) else { return false }
        let truncated = String(activeThemeID.prefix(ThemeLimits.assetID))
        let matches = catalog.themes.indices.filter { catalog.themes[$0].id == truncated }
        guard matches.count == 1, let index = matches.first else { return false }
        catalog.themes[index].id = activeThemeID
        // 以该主题为 base 的其他自定义主题同步指向完整 id。
        for i in catalog.themes.indices where catalog.themes[i].base == truncated {
            catalog.themes[i].base = activeThemeID
        }
        return true
    }

    // MARK: 写

    /// 请求写（200ms 合并）。sequence 递增防旧覆盖。
    func requestWrite() {
        backend = .themeStore
        // 用户主动修改：退出只读恢复，允许把当前 catalog 落盘。
        assetsIndexUnreadable = false
        sequence += 1
        writeTask?.cancel()
        let captured = sequence
        writeTask = Task { [weak self] in
            guard let self else { return }
            do { try await Task.sleep(for: .milliseconds(200)) } catch { return }
            await self.flushIfNeeded(sequence: captured)
        }
    }

    /// 立即落盘（进后台 / 退出路径调用）。
    func flush() {
        writeTask?.cancel()
        writeTask = nil
        Task { await self.flushIfNeeded(sequence: self.sequence) }
    }

    private func flushIfNeeded(sequence captured: Int) async {
        // 只读恢复且用户尚未修改：不写盘，保住原文件里可能仍可用的资产索引。
        guard !assetsIndexUnreadable else { return }
        guard captured >= lastWrittenSequence else { return }  // 旧写丢弃
        do {
            try persistCatalog(catalog)
            lastWrittenSequence = captured
            // 索引提交成功后才清理孤儿（M1：全量引用集 + 二次核对）。
            cleanOrphansIfNeeded()
        } catch {
            decodeError = "主题写入失败：\(error.localizedDescription)"
            writeDecodeError(decodeError!)
            // 失败不消费 sequence：下次 flush 可重试。
        }
    }

    private func persistCatalog(_ catalog: ThemeCatalog) throws {
        ensureDirectories()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(catalog)

        // 轮转 prev：仅当前主索引可读时（原子写 + 读回核对）。
        if fileManager.fileExists(atPath: indexURL.path),
           let current = try? Data(contentsOf: indexURL),
           (try? JSONDecoder().decode(ThemeCatalog.self, from: current)) != nil {
            try current.write(to: prevURL, options: .atomic)
        }

        try data.write(to: indexURL, options: .atomic)
    }

    // MARK: 孤儿清理（运维/安全评审 G4：pending-delete + 二次核对 + 串行）

    private func cleanOrphansIfNeeded() {
        // 只处理宽限期已过的 pending-delete 项，且删除前重读 catalog 二次确认引用集。
        guard !catalog.pendingDelete.isEmpty else { return }
        let referenced = Set(catalog.assets.map(\.id))
        var remaining: [ThemeCatalog.PendingDelete] = []
        let grace: TimeInterval = 24 * 3600
        for item in catalog.pendingDelete {
            if Date().timeIntervalSince(item.markedAt) < grace {
                remaining.append(item)
                continue
            }
            if referenced.contains(item.assetID) { continue }  // 又被引用：出队
            // 删除前二次核对：重读当前索引（防止并发写已重新引用）。
            if let disk = try? Data(contentsOf: indexURL),
               let current = try? JSONDecoder().decode(ThemeCatalog.self, from: disk),
               current.assets.contains(where: { $0.id == item.assetID }) {
                remaining.append(item)
                continue
            }
            if let url = assetURL(id: item.assetID, ext: item.ext) {
                try? fileManager.removeItem(at: url)
            }
            // 兼容旧记录（ext 默认 png）：扫其余白名单扩展名兜底。
            for otherExt in AssetRef.allowedExtensions where otherExt != item.ext {
                if let url = assetURL(id: item.assetID, ext: otherExt) {
                    try? fileManager.removeItem(at: url)
                }
            }
        }
        catalog.pendingDelete = remaining
    }

    /// 标记资产待删除（供编辑器删主题时调用，不立即删）。
    func markPendingDelete(assetIDs: [String]) {
        let now = Date()
        for id in assetIDs where AssetRef.isValidAssetID(id) {
            if !catalog.pendingDelete.contains(where: { $0.assetID == id }) {
                catalog.pendingDelete.append(
                    ThemeCatalog.PendingDelete(assetID: id, markedAt: now)
                )
            }
        }
        requestWrite()
    }

    // MARK: 删除自定义主题（回收其独占资产）

    /// 主题直接引用的资产 id：背景图、加载图、导入字体。
    static func referencedAssetIDs(in theme: Theme) -> Set<String> {
        var ids = Set<String>()
        func collectBackdrop(_ backdrop: BackgroundSpec?) {
            if case let .image(asset, _, _)? = backdrop, AssetRef.isValidAssetID(asset) {
                ids.insert(asset)
            }
        }
        collectBackdrop(theme.backdrop)
        collectBackdrop(theme.loading.background)
        if let artwork = theme.loading.artworkAsset, AssetRef.isValidAssetID(artwork) {
            ids.insert(artwork)
        }
        for family in [theme.typography.uiFamily, theme.typography.titleFamily] {
            if case let .imported(assetID, _) = family, AssetRef.isValidAssetID(assetID) {
                ids.insert(assetID)
            }
        }
        return ids
    }

    /// 删除自定义主题：收集它引用的资产，只回收其他主题（含内置）都不再引用的，
    /// 修正 activeThemeID 后落盘并触发孤儿清理，避免图片/字体永久残留。
    func deleteTheme(_ id: String) {
        guard let theme = catalog.themes.first(where: { $0.id == id }), !theme.builtin else {
            return
        }
        let ownedAssets = Self.referencedAssetIDs(in: theme)
        let remaining = catalog.themes.filter { $0.id != id }
        var stillReferenced = Set<String>()
        for other in remaining {
            stillReferenced.formUnion(Self.referencedAssetIDs(in: other))
        }
        let reclaimable = ownedAssets.subtracting(stillReferenced)

        catalog.themes = remaining
        // 先从索引中摘掉独占资产，孤儿清理才不会因「仍被引用」而跳过。
        catalog.assets.removeAll { reclaimable.contains($0.id) }
        if catalog.activeThemeID == id {
            catalog.activeThemeID = BuiltinThemes.defaultID
        }
        markPendingDelete(assetIDs: Array(reclaimable))
        flush()
    }

    // MARK: 坏文件留档与诊断

    private func quarantineCorruptFile(_ data: Data) {
        let ts = Int(Date().timeIntervalSince1970)
        let url = root.appendingPathComponent("themes.corrupt-\(ts).json")
        try? data.write(to: url, options: .atomic)
    }

    private func writeDecodeError(_ message: String) {
        let url = root.appendingPathComponent("theme-decode-error.txt")
        let line = "\(ISO8601DateFormatter().string(from: Date())) \(message)\n"
        if let existing = try? String(contentsOf: url, encoding: .utf8) {
            try? (existing + line).write(to: url, atomically: true, encoding: .utf8)
        } else {
            try? line.write(to: url, atomically: true, encoding: .utf8)
        }
    }

    // MARK: 查询与切换

    var activeTheme: Theme {
        catalog.themes.first { $0.id == catalog.activeThemeID }
            ?? BuiltinThemes.theme(withID: BuiltinThemes.defaultID)
            ?? Theme(name: "默认")
    }

    func resolvedTokens(scheme: ColorScheme = .light) -> ThemeTokens {
        ThemeEngine.resolve(theme: activeTheme, scheme: scheme)
    }

    func selectTheme(id: String) {
        guard catalog.themes.contains(where: { $0.id == id }) else { return }
        catalog.activeThemeID = id
        requestWrite()
    }

    /// dualWrite 影子写通道就位（P0-05 只落影子逻辑；对账门禁后移到 P1-01 后）。
    func shadowWrite(catalog: ThemeCatalog) {
        guard backend == .dualWrite else { return }
        // 影子写与主流写共用同一份 catalog 编码路径，对账脚本在 P1-01 后执行。
        try? persistCatalog(catalog)
    }

    func switchBackend(_ newBackend: Backend) {
        backend = newBackend
    }
}
