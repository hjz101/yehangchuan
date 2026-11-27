import Foundation

/// 凭据后端阶段。迁移默认停在 `.dualWrite`：SQLite 仍是权威副本、绝不删除，
/// Keychain 作为第二份随写。只有对账通过后才会被切到 `.keychainPreferred`。
/// 任一步出问题，切回 `.sqlite` 即完全回到迁移前的行为（回滚开关）。
public enum CredentialBackend: String, Sendable {
    case sqlite
    case dualWrite
    case keychainPreferred
}

/// 全局凭据配置。线程安全，可在运行时切换后端以便回滚，无需重启 App。
public final class CredentialSettings: @unchecked Sendable {
    public static let shared = CredentialSettings()

    private let lock = NSLock()
    private var _backend: CredentialBackend = .dualWrite
    private var _keychain: any KeychainStoring = SystemKeychainStore()

    public init() {}

    public var backend: CredentialBackend {
        get { lock.lock(); defer { lock.unlock() }; return _backend }
        set { lock.lock(); _backend = newValue; lock.unlock() }
    }

    public var keychain: any KeychainStoring {
        get { lock.lock(); defer { lock.unlock() }; return _keychain }
        set { lock.lock(); _keychain = newValue; lock.unlock() }
    }

    /// 一次性同时替换后端与 Keychain 实现，避免测试里两步之间被别的线程读到中间态。
    public func configure(backend: CredentialBackend, keychain: any KeychainStoring) {
        lock.lock()
        _backend = backend
        _keychain = keychain
        lock.unlock()
    }
}

/// 对账结果。 migrating 前后逐键比对，只有 `missing == 0 && mismatch == 0`
/// 才允许把后端从 `.dualWrite` 切到 `.keychainPreferred`。
public struct CredentialReconciliation: Sendable {
    public var checked: Int = 0
    /// SQLite 有、Keychain 缺的键。
    public var missing: [String] = []
    /// 两边都有但值不一致的键。
    public var mismatch: [String] = []

    public var isClean: Bool { missing.isEmpty && mismatch.isEmpty }
}
