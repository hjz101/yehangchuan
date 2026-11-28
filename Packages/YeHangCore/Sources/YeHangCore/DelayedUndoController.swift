import Foundation

/// 「延迟执行 + 可撤销」通用状态机（主题删除 5 秒撤销、后续同类交互共用）。
///
/// 每次 `schedule` 都换一个 UUID token；`cancel` 或再次 `schedule` 会让旧 token 失效，
/// 旧任务醒来时先比对 token 和 `isPending`，因此不会误删已经撤销或已重新排期的目标。
/// 不持有具体业务对象，避免让内核依赖 SwiftUI / App 层模型。
@MainActor
public final class DelayedUndoController {
    private var token = UUID()
    private var task: Task<Void, Never>?

    /// 是否处于可撤销窗口。UI 可用它决定 toast 是否显示。
    public private(set) var isPending: Bool

    public init() {
        isPending = false
    }

    /// 排期一次延迟执行。重复调用会先取消前一次，确保同一时刻只有一个有效 token。
    ///
    /// 用纳秒而不是 `Duration`：包仍支持 iOS 15，而 `Duration` 相关 API 从 iOS 16 才有，
    /// 否则 App 目标编译会在这里失败。
    public func schedule(
        delay: UInt64 = 5_000_000_000,
        onExpire: @escaping @MainActor () -> Void
    ) {
        cancel()
        let issued = UUID()
        token = issued
        isPending = true
        task = Task { @MainActor in
            do {
                try await Task.sleep(nanoseconds: delay)
            } catch {
                return  // 撤销或重新排期时旧任务被取消
            }
            guard token == issued, isPending else { return }
            onExpire()
            isPending = false
            task = nil
        }
    }

    /// 撤销：取消任务并换 token，旧任务即使已经醒来也会因 token 不符直接返回。
    public func cancel() {
        task?.cancel()
        task = nil
        token = UUID()
        isPending = false
    }
}
