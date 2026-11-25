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

struct MockRequestLog: Identifiable {
    let id = UUID()
    let method: String
    let path: String
    let status: Int
    let milliseconds: Int
    let at: Date
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

struct MockFileItem: Identifiable {
    let id = UUID()
    let name: String
    let detail: String
    let symbol: String
}

struct MockRole: Identifiable {
    let id = UUID()
    let name: String
    let voice: String
    let lines: Int
}

// MARK: - Backend

@MainActor
@Observable
final class MockBackend {
    var isOnline = true
    var latencyScale: Double = 1
    var requestCount = 0
    var logs: [MockRequestLog] = []
    var account: AccountState = .guest
    var syncState: CloudSyncState = .idle
    var lastSyncAt: Date?

    var cacheChapterMB = 12.4
    var cacheImageMB = 48.6
    var cacheAudioMB = 36.2
    var downloadProgress: Double = 0
    var isDownloading = false
    var lastDownloadLabel = "未开始"

    var files: [MockFileItem] = [
        MockFileItem(name: "夜航船.txt", detail: "UTF-8 · 1.8 MB", symbol: "doc.plaintext"),
        MockFileItem(name: "山海拾遗.epub", detail: "14 章 · 4.2 MB", symbol: "book.closed"),
        MockFileItem(name: "星港来信.zip", detail: "28 页图片 · 62 MB", symbol: "doc.zipper"),
        MockFileItem(name: "潮汐电台.m4a", detail: "05:40 · 8.4 MB", symbol: "waveform")
    ]

    func elapsedMilliseconds(_ base: Int = 160) -> Int {
        Int(Double(base) * latencyScale) + Int.random(in: 20...180)
    }

    func call(_ method: String, _ path: String, base: Int = 160) async -> MockResponse {
        let milliseconds = elapsedMilliseconds(base)
        if isOnline {
            try? await Task.sleep(for: .milliseconds(min(milliseconds, 900)))
        } else {
            try? await Task.sleep(for: .milliseconds(260))
        }
        requestCount += 1
        let status = isOnline ? 200 : 503
        logs.insert(
            MockRequestLog(
                method: method,
                path: path,
                status: status,
                milliseconds: milliseconds,
                at: Date()
            ),
            at: 0
        )
        if logs.count > 40 { logs.removeLast(logs.count - 40) }
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

    func sync(forceConflict: Bool = false) async -> CloudSyncState {
        syncState = .syncing
        let response = await call("POST", "/v1/sync/push")
        guard response.ok else {
            let state = CloudSyncState.failed("网络离线，已保留本机数据")
            syncState = state
            return state
        }
        let conflict = forceConflict || Int.random(in: 0..<12) == 0
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
        let now = Date()
        lastSyncAt = now
        syncState = .synced(now)
    }

    func probe(_ source: BookSource) async -> SourceProbe {
        let response = await call("GET", "/source/\(source.id)/ping", base: 220)
        let ok = source.enabled && response.ok && !source.host.contains("timeout")
        let message: String
        if !source.enabled {
            message = "已停用，跳过检测"
        } else if !isOnline {
            message = "本地网关离线"
        } else if ok {
            message = "搜索 / 详情 / 正文规则可解析"
        } else {
            message = "连接超时，请检查站点或规则"
        }
        return SourceProbe(
            id: source.id,
            name: source.name,
            ok: ok,
            milliseconds: response.milliseconds,
            message: message
        )
    }

    func batchProbe(_ sources: [BookSource]) async -> [SourceProbe] {
        var results: [SourceProbe] = []
        for source in sources {
            results.append(await probe(source))
        }
        return results
    }

    func loginSource(_ source: BookSource, account: String, password: String) async -> Bool {
        let response = await call("POST", "/source/\(source.id)/login")
        let ok = response.ok && !account.isEmpty && !password.isEmpty
        return ok
    }

    func debug(_ source: BookSource, query: String) async -> [DebugLine] {
        let steps = ["搜索", "详情", "目录", "正文"]
        var lines: [DebugLine] = []
        for (index, step) in steps.enumerated() {
            let response = await call("GET", "/source/\(source.id)/\(step)", base: 120 + index * 40)
            let ok = response.ok && index < (isOnline ? 4 : 1)
            let detail: String
            switch step {
            case "搜索": detail = ok ? "命中 3 条：\(query.isEmpty ? "长风" : query)" : "未返回结果"
            case "详情": detail = ok ? "书名、作者、简介字段完整" : "详情规则未匹配"
            case "目录": detail = ok ? "解析 28 章 · 最新章节可读" : "目录为空"
            default: detail = ok ? "正文 1,284 字 · 已去除广告" : "正文规则超时"
            }
            lines.append(DebugLine(step: step, detail: detail, ok: ok, milliseconds: response.milliseconds))
        }
        return lines
    }

    func download(book: Book, count: Int) async -> Int {
        isDownloading = true
        downloadProgress = 0
        lastDownloadLabel = "正在预下载《\(book.title)》"
        for index in 1...max(count, 1) {
            try? await Task.sleep(for: .milliseconds(180))
            downloadProgress = Double(index) / Double(max(count, 1))
        }
        cacheChapterMB += Double(count) * 0.18
        isDownloading = false
        lastDownloadLabel = "\(book.title) · \(count) 章已缓存"
        return count
    }

    func clearCache(_ kind: String) -> Double {
        var freed: Double = 0
        switch kind {
        case "章节": freed = cacheChapterMB; cacheChapterMB = 0
        case "图片": freed = cacheImageMB; cacheImageMB = 0
        case "音频": freed = cacheAudioMB; cacheAudioMB = 0
        default:
            freed = cacheChapterMB + cacheImageMB + cacheAudioMB
            cacheChapterMB = 0; cacheImageMB = 0; cacheAudioMB = 0
        }
        return freed
    }

    func analyzeRoles(_ text: String) -> [MockRole] {
        [
            MockRole(name: "旁白", voice: "温柔女声", lines: max(text.count / 90, 12)),
            MockRole(name: "年轻旅人", voice: "清亮少年", lines: 18),
            MockRole(name: "卖布老人", voice: "沉稳长者", lines: 9)
        ]
    }

    func testTTS(voice: String, speed: Double) async -> MockResponse {
        await call("POST", "/v1/tts?voice=\(voice)&speed=\(String(format: "%.1f", speed))")
    }

    func testAI(provider: String, model: String) async -> MockResponse {
        await call("POST", "/v1/ai/\(provider)/\(model)/health", base: 320)
    }

    func testNetwork() async -> MockResponse {
        await call("GET", "/v1/network/diagnose", base: 280)
    }

    func searchCovers(_ query: String) async -> [String] {
        let response = await call("GET", "/v1/covers?q=\(query)")
        guard response.ok else { return [] }
        return ["暮色船坞", "旧纸纹理", "山海蓝", "灯火航线"].map { "\(query) · \($0)" }
    }
}
