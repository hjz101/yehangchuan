import Foundation
import Observation

// MARK: - Backup models

/// 备份可以包含的内容。三个选项对应设置页里的三个开关，
/// 也是备份文件里 `scopes` 字段的取值，用来在列表里如实说明这份备份装了什么。
enum BackupScope: String, CaseIterable, Identifiable, Codable, Sendable {
    case sources = "书源"
    case library = "书籍 · 进度 · 摘录"
    case preferences = "阅读偏好"

    var id: String { rawValue }

    var title: String { rawValue }

    var toggleLabel: String {
        switch self {
        case .sources: "包含书源"
        case .library: "包含书籍与进度"
        case .preferences: "包含阅读偏好"
        }
    }
}

/// 一条备份的元信息。`id` 就是磁盘上的文件名，因此列表与文件一一对应。
struct BackupRecord: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let createdAt: Date
    let byteCount: Int
    let scopes: [BackupScope]

    var displayName: String {
        let suffix = ".qibackup"
        return name.hasSuffix(suffix) ? String(name.dropLast(suffix.count)) : name
    }

    var sizeLabel: String {
        ByteCountFormatter.string(fromByteCount: Int64(byteCount), countStyle: .file)
    }

    var includesLabel: String {
        scopes.isEmpty ? "空备份" : scopes.map(\.title).joined(separator: " · ")
    }
}

/// 落盘的备份文件结构：元信息 + 数据载荷。
struct BackupPackage: Codable, Sendable {
    var name: String
    var createdAt: Date
    var scopes: [BackupScope]
    var payload: BackupPayload
}

/// 备份载荷。字段全部可选：没勾选的那一块不写进文件，
/// 恢复时也就不会被空值覆盖掉用户现有的数据。
struct BackupPayload: Codable, Sendable {
    var sources: [BookSource]?
    var books: [Book]?
    var positions: [String: ReadingPosition]?
    var bookmarks: [Bookmark]?
    var customChapters: [String: [Chapter]]?
    var excerpts: [Excerpt]?
    var readerSettings: ReaderSnapshot?
    var eyeCare: EyeCareSettings?
    var appearance: AppAppearance?
    var goalMinutes: Int?
    var groups: [String]?
    /// P3-08：主题纳入 .preferences scope。资产 base64 内嵌（JSONEncoder 自动），
    /// 总上限 20MB；超限只备 catalog，不备资产（恢复时提示用 .yhthm 手动导出）。
    var themeCatalog: ThemeCatalog?
    var themeAssets: [String: Data]?
}

// MARK: - Backup storage

/// 备份目录读写。文件放在 Application Support/YeHangChuan/Backups 下，
/// 列表直接从目录扫描得出，不再维护一份会跟磁盘对不上的内存记录。
@MainActor
@Observable
final class BackupCenter {
    private(set) var backups: [BackupRecord] = []
    private(set) var isBusy = false

    @ObservationIgnored private let directory: URL?

    init() {
        let manager = FileManager.default
        let base = manager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        var folder = base?.appendingPathComponent("YeHangChuan", isDirectory: true)
        folder?.appendPathComponent("Backups", isDirectory: true)
        if let folder {
            try? manager.createDirectory(at: folder, withIntermediateDirectories: true)
        }
        directory = folder
        Task { await refresh() }
    }

    func refresh() async {
        guard let directory else {
            backups = []
            return
        }
        let records = await Task.detached(priority: .utility) {
            Self.scan(directory)
        }.value
        backups = records
    }

    @discardableResult
    func create(name: String, scopes: Set<BackupScope>, payload: BackupPayload) async -> BackupRecord? {
        guard let directory else { return nil }
        isBusy = true
        defer { isBusy = false }

        let now = Date()
        let base = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let stem = base.isEmpty ? "夜航船" : base
        let ordered = BackupScope.allCases.filter { scopes.contains($0) }
        let package = BackupPackage(
            name: "\(stem)_\(Self.stamp(now)).qibackup",
            createdAt: now,
            scopes: ordered,
            payload: payload
        )
        guard let data = try? JSONEncoder().encode(package) else { return nil }

        let record = BackupRecord(
            id: package.name,
            name: package.name,
            createdAt: package.createdAt,
            byteCount: data.count,
            scopes: ordered
        )
        let url = directory.appendingPathComponent(package.name)
        let written = await Task.detached(priority: .utility) {
            do {
                try data.write(to: url, options: .atomic)
                return true
            } catch {
                return false
            }
        }.value
        guard written else { return nil }

        await refresh()
        return record
    }

    func load(_ record: BackupRecord) async -> BackupPackage? {
        guard let directory else { return nil }
        let url = directory.appendingPathComponent(record.id)
        return await Task.detached(priority: .userInitiated) {
            guard let data = try? Data(contentsOf: url) else { return nil }
            return try? JSONDecoder().decode(BackupPackage.self, from: data)
        }.value
    }

    func delete(_ record: BackupRecord) async {
        guard let directory else { return }
        let url = directory.appendingPathComponent(record.id)
        await Task.detached(priority: .utility) {
            try? FileManager.default.removeItem(at: url)
        }.value
        await refresh()
    }

    // MARK: Private

    nonisolated private static func scan(_ directory: URL) -> [BackupRecord] {
        let manager = FileManager.default
        guard let names = try? manager.contentsOfDirectory(atPath: directory.path) else { return [] }

        return names
            .filter { $0.hasSuffix(".qibackup") }
            .compactMap { name -> BackupRecord? in
                let url = directory.appendingPathComponent(name)
                guard let data = try? Data(contentsOf: url),
                      let package = try? JSONDecoder().decode(BackupPackage.self, from: data) else {
                    // 文件损坏或解不开时仍列出来，标成「空备份」让用户能发现并删除。
                    let attributes = try? manager.attributesOfItem(atPath: url.path)
                    let size = (attributes?[.size] as? NSNumber)?.intValue ?? 0
                    let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?
                        .contentModificationDate ?? Date()
                    return BackupRecord(
                        id: name,
                        name: name,
                        createdAt: modified,
                        byteCount: size,
                        scopes: []
                    )
                }
                return BackupRecord(
                    id: name,
                    name: package.name,
                    createdAt: package.createdAt,
                    byteCount: data.count,
                    scopes: package.scopes
                )
            }
            .sorted { $0.createdAt > $1.createdAt }
    }

    nonisolated private static func stamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd_HHmmss"
        return formatter.string(from: date)
    }
}
