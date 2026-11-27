import Foundation
import Security

/// Keychain 的最小抽象。所有操作都失败安全：Keychain 不可用时返回 nil / 吞掉
/// 写入错误，绝不阻塞 SQLite 这条原有链路 —— 这是「禁止直接删库」的护栏。
public protocol KeychainStoring: Sendable {
    func read(_ key: String) -> String?
    func write(_ key: String, _ value: String)
    func delete(_ key: String)
    /// 列出当前服务下所有键，供对账使用；返回 nil 表示底层不支持枚举。
    func allKeys() -> [String]?
}

/// 系统 Keychain 实现。服务名固定，账号即书源/域名的原始键。
/// 敏感值以 UTF-8 Data 存 `kSecValueData`，可访问级别设为首解锁后、仅本机。
public final class SystemKeychainStore: KeychainStoring, @unchecked Sendable {
    private let service: String
    private let accessibility: CFString

    public init(
        service: String = "com.huaiju.yehangchuan.credentials",
        accessibility: CFString = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
    ) {
        self.service = service
        self.accessibility = accessibility
    }

    public func read(_ key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    public func write(_ key: String, _ value: String) {
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]
        let attrs: [String: Any] = [
            kSecValueData as String: Data(value.utf8),
            kSecAttrAccessible as String: accessibility
        ]
        var add = base
        add.merge(attrs) { _, new in new }
        let status = SecItemAdd(add as CFDictionary, nil)
        if status == errSecDuplicateItem {
            SecItemUpdate(base as CFDictionary, attrs as CFDictionary)
        }
        // 任何其它错误都吞掉：Keychain 是双写的「第二份」，不是唯一副本。
    }

    public func delete(_ key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]
        SecItemDelete(query as CFDictionary)
    }

    public func allKeys() -> [String]? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecReturnAttributes as String: true,
            kSecMatchLimit as String: kSecMatchLimitAll
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let rows = item as? [[String: Any]] else { return nil }
        return rows.compactMap { $0[kSecAttrAccount as String] as? String }
    }
}

/// 测试与「Keychain 不可用」降级用的内存实现，行为与系统实现一致但不落钥匙串。
public final class InMemoryKeychainStore: KeychainStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [String: String] = [:]

    public init() {}

    public func read(_ key: String) -> String? {
        lock.lock()
        defer { lock.unlock() }
        return storage[key]
    }

    public func write(_ key: String, _ value: String) {
        lock.lock()
        storage[key] = value
        lock.unlock()
    }

    public func delete(_ key: String) {
        lock.lock()
        storage.removeValue(forKey: key)
        lock.unlock()
    }

    public func allKeys() -> [String]? {
        lock.lock()
        defer { lock.unlock() }
        return Array(storage.keys)
    }
}
