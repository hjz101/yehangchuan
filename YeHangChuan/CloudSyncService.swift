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
        let file = FileManager.default.temporaryDirectory
            .appendingPathComponent("yehang-cloud-\(UUID().uuidString).json")
        try data.write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }
        let record = CKRecord(
            recordType: Self.recordType,
            recordID: CKRecord.ID(recordName: Self.recordName)
        )
        record["payload"] = CKAsset(fileURL: file)
        record["updatedAt"] = Date()
        _ = try await database.privateCloudDatabase.modifyRecords(saving: [record], deleting: [])
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
