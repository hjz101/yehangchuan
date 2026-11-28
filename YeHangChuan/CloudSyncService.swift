import CloudKit
import Foundation

/// 真实 iCloud 私有数据库同步。
///
/// 没有登录 iCloud 账号或未开启 iCloud capability 时，CKContainer 会返回
/// notAuthenticated / networkUnavailable 等错误；界面如实展示，不谎称同步成功。
/// 上传用 CKAsset 而不是 CKRecord 的 Data 字段，避免快照稍大就被 CloudKit 拒绝。
struct CloudSyncService {
    static let shared = CloudSyncService()

    private let database: CKContainer
    private static let recordType = "YeHangSnapshot"
    private static let recordName = "YeHangSnapshot"

    init(container: CKContainer = .default()) {
        self.database = container
    }

    func upload(_ data: Data) async throws {
        let recordID = CKRecord.ID(recordName: Self.recordName)
        // 先取回云端已有记录（带 changeTag）再改字段保存；直接 new 一个同名
        // record 在默认 .ifServerRecordUnchanged 策略下会被服务端拒绝。
        let record: CKRecord
        do {
            record = try await database.privateCloudDatabase.record(for: recordID)
        } catch let error as CKError where error.code == .unknownItem {
            record = CKRecord(recordType: Self.recordType, recordID: recordID)
        }
        let file = FileManager.default.temporaryDirectory
            .appendingPathComponent("yehang-cloud-\(UUID().uuidString).json")
        try data.write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }
        record["payload"] = CKAsset(fileURL: file)
        record["updatedAt"] = Date()
        // 逐条校验保存结果：任一失败都抛错，界面不得静默提示成功。
        try await database.privateCloudDatabase.saveChecked([record])
    }

    func download() async throws -> Data? {
        let record: CKRecord
        do {
            record = try await database.privateCloudDatabase.record(
                for: CKRecord.ID(recordName: Self.recordName)
            )
        } catch let error as CKError where error.code == .unknownItem {
            return nil
        }
        guard let asset = record["payload"] as? CKAsset, let url = asset.fileURL else { return nil }
        return try Data(contentsOf: url)
    }
}

extension CKDatabase {
    /// 逐条检查 modifyRecords 的保存/删除结果：任何一条失败都抛出该条错误，
    /// 避免把服务端拒绝当成同步成功。
    func saveChecked(_ records: [CKRecord], deleting recordIDs: [CKRecord.ID] = []) async throws {
        let result = try await modifyRecords(saving: records, deleting: recordIDs)
        for saveResult in result.saveResults.values {
            if case let .failure(error) = saveResult { throw error }
        }
        for deleteResult in result.deleteResults.values {
            if case let .failure(error) = deleteResult { throw error }
        }
    }
}
