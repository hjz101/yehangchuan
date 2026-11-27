import Foundation

/// 私网拦截的唯一判定闸门。
///
/// 书源的规则里可能出现与 `bookSourceUrl` 不同的域名，JS 里也会拼出新地址，
/// 所以判定必须放在传输层：任何经过 LegadoCore 的请求（包括 `java.ajax`
/// 这类同步 JS 网络调用与重定向的每一跳）都要过这一道闸。
///
/// App 在启动时注入自己的判定（含用户显式放行集合），使界面与传输层
/// 共用同一份口径；未注入时不擅自放行，按最保守的基础规则拒绝常见私网地址。
public enum PrivateHostGate {
    private final class Storage: @unchecked Sendable {
        private let lock = NSLock()
        private var predicate: (@Sendable (String) -> Bool)?

        func configure(_ value: @escaping @Sendable (String) -> Bool) {
            lock.withLock { predicate = value }
        }

        func current() -> (@Sendable (String) -> Bool)? {
            lock.withLock { predicate }
        }

        func reset() {
            lock.withLock { predicate = nil }
        }
    }

    private static let storage = Storage()

    /// 由 App 注入判定。返回 true 表示该主机应被拦截。
    public static func configure(_ check: @escaping @Sendable (String) -> Bool) {
        storage.configure(check)
    }

    /// 仅供测试清空注入的判定，避免用例之间互相污染。
    internal static func resetForTesting() { storage.reset() }

    /// 判定一个主机是否应被拦截。
    public static func shouldBlock(_ rawHost: String?) -> Bool {
        guard let rawHost, !rawHost.isEmpty else { return false }
        let host = rawHost.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        if let predicate = storage.current() { return predicate(host) }
        return fallbackBlocks(host)
    }

    /// 对请求做拦截检查，私网地址直接抛错。
    public static func check(_ request: URLRequest) throws {
        guard let host = request.url?.host, shouldBlock(host) else { return }
        throw PrivateHostError.blocked(host)
    }

    /// App 未注入判定时的兜底规则：只覆盖最明确的本机与私网段，
    /// 真正的完整判定（进制写法、IPv6、白名单等）由 App 注入的实现负责。
    private static func fallbackBlocks(_ host: String) -> Bool {
        if host == "localhost" || host.hasSuffix(".localhost") { return true }
        if host.hasSuffix(".local") || host.hasSuffix(".internal") { return true }
        let parts = host.split(separator: ".", omittingEmptySubsequences: false).compactMap { UInt8($0) }
        guard parts.count == 4 else { return false }
        if parts[0] == 0 || parts[0] == 127 || parts[0] == 10 { return true }
        if parts[0] == 192, parts[1] == 168 { return true }
        if parts[0] == 172, (16...31).contains(parts[1]) { return true }
        if parts[0] == 169, parts[1] == 254 { return true }
        if parts[0] == 100, (64...127).contains(parts[1]) { return true }
        return false
    }
}

public enum PrivateHostError: LocalizedError {
    case blocked(String)

    public var errorDescription: String? {
        switch self {
        case .blocked(let host): "已拦截私网地址：\(host)"
        }
    }
}
