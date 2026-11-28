import Foundation
import Observation

// MARK: - Models

enum CloudSyncState: Equatable {
    case idle
    case syncing
    case synced(Date)
    case conflict
    case failed(String)

    var title: String {
        switch self {
        case .idle: "未同步"
        case .syncing: "同步中"
        case .synced: "已同步"
        case .conflict: "有冲突"
        case .failed: "同步失败"
        }
    }

    var symbol: String {
        switch self {
        case .idle: "icloud"
        case .syncing: "arrow.triangle.2.circlepath.icloud"
        case .synced: "checkmark.icloud"
        case .conflict: "exclamationmark.icloud"
        case .failed: "xmark.icloud"
        }
    }
}

enum AccountState: Equatable {
    case guest
    case signedIn(email: String)

    var title: String {
        switch self {
        case .guest: "游客"
        case .signedIn: "已登录"
        }
    }

    var email: String? {
        if case .signedIn(let email) = self { return email }
        return nil
    }
}

struct MockResponse {
    let status: Int
    let milliseconds: Int
    let body: String

    var ok: Bool { (200..<300).contains(status) }
}

struct SourceProbe: Identifiable {
    let id: String
    let name: String
    let ok: Bool
    let milliseconds: Int
    let message: String
}

struct DebugLine: Identifiable {
    let id = UUID()
    let step: String
    let detail: String
    let ok: Bool
    let milliseconds: Int
}

// MARK: - Backend

@MainActor
@Observable
final class MockBackend {
    var isOnline = true
    var latencyScale: Double = 1
    var account: AccountState = .guest
    var syncState: CloudSyncState = .idle
    var lastSyncAt: Date?

    func elapsedMilliseconds(_ base: Int = 160) -> Int {
        Int(Double(base) * latencyScale) + Int.random(in: 20...180)
    }

    /// 演示模式下的「网络调用」：只等待一小段时间，不发任何真实请求。
    /// 不记录日志，也不产生请求计数 —— 同步页会明确标注这是演示。
    func call(_ method: String, _ path: String, base: Int = 160) async -> MockResponse {
        let milliseconds = elapsedMilliseconds(base)
        if isOnline {
            try? await Task.sleep(for: .milliseconds(min(milliseconds, 900)))
        } else {
            try? await Task.sleep(for: .milliseconds(260))
        }
        let status = isOnline ? 200 : 503
        return MockResponse(
            status: status,
            milliseconds: milliseconds,
            body: isOnline ? "ok" : "offline"
        )
    }

    func signIn(email: String) async -> Bool {
        guard isOnline else { return false }
        let response = await call("POST", "/v1/auth/session")
        guard response.ok else { return false }
        let normalized = email.trimmingCharacters(in: .whitespacesAndNewlines)
        account = .signedIn(email: normalized.isEmpty ? "reader@yehangchuan.app" : normalized)
        return true
    }

    func signOut() {
        account = .guest
        syncState = .idle
    }

    /// 演示同步：只改状态，不上传、不下载、不合并任何数据。
    /// 冲突只在用户显式选择「演示冲突流程」时出现，不再随机制造 ——
    /// 随机冲突会让用户以为自己真的有云端数据在打架。
    func sync(forceConflict: Bool = false) async -> CloudSyncState {
        syncState = .syncing
        let response = await call("POST", "/v1/sync/push")
        guard response.ok else {
            let state = CloudSyncState.failed("网络离线，已保留本机数据")
            syncState = state
            return state
        }
        let conflict = forceConflict
        if conflict {
            syncState = .conflict
        } else {
            let now = Date()
            lastSyncAt = now
            syncState = .synced(now)
        }
        return syncState
    }

    func resolveConflict(useLocal: Bool) {
        // 演示的冲突解决只切状态：两份数据从头到尾都只有本机这一份。
        let now = Date()
        lastSyncAt = now
        syncState = .synced(now)
    }

    func loginSource(_ source: BookSource, account: String, password: String) async -> Bool {
        let response = await call("POST", "/source/\(source.id)/login")
        let ok = response.ok && !account.isEmpty && !password.isEmpty
        return ok
    }
}
