import Foundation
import CloudKit

// MARK: - 二期主题跨端同步（P5-03）
//
// 默认关闭；每主题一条 CKRecord（YeHangThemeCatalog），含 payload(CKAsset) + assets。
// 本机优先：远端 updatedAt <= 本地则跳过；> 本地进入冲突解决（P5-04）。
// CloudKit 不可用不影响本机主题。

struct ThemeSyncService {
    static let shared = ThemeSyncService()

    private let database: CKContainer
    private static let recordType = "YeHangThemeCatalog"

    init(container: CKContainer = .default()) {
        self.database = container
    }

    struct SyncRecord: Sendable {
        var themeID: String
        var name: String
        var schemaVersion: Int
        var updatedAt: Date
        var deviceID: String
        var payload: Data
        var assetIDs: [String]
        var assets: [Data]
        var deletedAt: Date?
    }

    // MARK: Push

    /// 上传主题。assetIDs 列表用于去重谓词（CKQuery 无法按 CKAsset 内容查询）。
    func push(
        theme: Theme,
        payload: Data,
        assets: [(id: String, data: Data)],
        deviceID: String
    ) async throws {
        let record = CKRecord(recordType: Self.recordType, recordID: CKRecord.ID(recordName: theme.id))

        // 先按 assetID 去重上传资产（远端已有则跳过）。
        let existing = try await remoteAssetIDs()
        var assetAssets: [CKAsset] = []
        var uploadedIDs: [String] = []
        for asset in assets {
            guard !existing.contains(asset.id) else {
                uploadedIDs.append(asset.id)
                continue
            }
            guard asset.data.count <= 10 * 1024 * 1024 else { continue }
            let file = FileManager.default.temporaryDirectory
                .appendingPathComponent("theme-asset-\(asset.id).bin")
            try asset.data.write(to: file)
            assetAssets.append(CKAsset(fileURL: file))
            uploadedIDs.append(asset.id)
        }

        let payloadFile = FileManager.default.temporaryDirectory
            .appendingPathComponent("theme-\(theme.id).json")
        try payload.write(to: payloadFile)

        record["themeID"] = theme.id
        record["name"] = theme.name
        record["schemaVersion"] = theme.schemaVersion
        record["updatedAt"] = theme.updatedAt
        record["deviceID"] = deviceID
        record["assetIDs"] = uploadedIDs
        record["payload"] = CKAsset(fileURL: payloadFile)
        record["assets"] = assetAssets.isEmpty ? nil : assetAssets
        record["deletedAt"] = nil

        _ = try await database.privateCloudDatabase.modifyRecords(saving: [record], deleting: [])
    }

    // MARK: Pull

    /// 拉取全部记录。返回需本地处理的项（新增/冲突/墓碑）。
    func pull() async throws -> [SyncRecord] {
        let query = CKQuery(recordType: Self.recordType, predicate: NSPredicate(value: true))
        let result = try await database.privateCloudDatabase.records(matching: query)
        var out: [SyncRecord] = []
        for (_, recordResult) in result.matchResults {
            guard let record = try? recordResult.get() else { continue }
            guard let themeID = record["themeID"] as? String else { continue }
            var payload = Data()
            if let asset = record["payload"] as? CKAsset, let url = asset.fileURL {
                payload = (try? Data(contentsOf: url)) ?? Data()
            }
            var assets: [Data] = []
            if let assetList = record["assets"] as? [CKAsset] {
                for asset in assetList {
                    if let url = asset.fileURL, let data = try? Data(contentsOf: url) {
                        assets.append(data)
                    }
                }
            }
            out.append(SyncRecord(
                themeID: themeID,
                name: record["name"] as? String ?? "同步主题",
                schemaVersion: record["schemaVersion"] as? Int ?? 1,
                updatedAt: record["updatedAt"] as? Date ?? Date(),
                deviceID: record["deviceID"] as? String ?? "",
                payload: payload,
                assetIDs: record["assetIDs"] as? [String] ?? [],
                assets: assets,
                deletedAt: record["deletedAt"] as? Date
            ))
        }
        return out
    }

    /// 墓碑删除（保留 30 天清理）。
    func tombstone(themeID: String) async throws {
        guard let record = try? await database.privateCloudDatabase.record(
            for: CKRecord.ID(recordName: themeID)
        ) else { return }
        record["deletedAt"] = Date()
        _ = try await database.privateCloudDatabase.modifyRecords(saving: [record], deleting: [])
    }

    private func remoteAssetIDs() async throws -> Set<String> {
        let query = CKQuery(recordType: Self.recordType, predicate: NSPredicate(value: true))
        let result = try await database.privateCloudDatabase.records(matching: query)
        var ids = Set<String>()
        for (_, recordResult) in result.matchResults {
            guard let record = try? recordResult.get(),
                  let assetIDs = record["assetIDs"] as? [String] else { continue }
            ids.formUnion(assetIDs)
        }
        return ids
    }
}
