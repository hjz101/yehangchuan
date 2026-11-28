import XCTest
@testable import YeHangCore

/// 主题库「删除后 5 秒可撤销」的状态机验证。
/// 这里用 40/120 毫秒的短延时替代 5 秒，断言的是同一套 token + cancel 语义。
@MainActor
final class DelayedUndoControllerTests: XCTestCase {
    func testExpiryFiresExactlyOnceAndClearsPending() async throws {
        let controller = DelayedUndoController()
        var expired = 0
        controller.schedule(delay: .milliseconds(40)) { expired += 1 }

        XCTAssertTrue(controller.isPending)
        try await Task.sleep(nanoseconds: 100_000_000) // 100ms
        XCTAssertEqual(expired, 1)
        XCTAssertFalse(controller.isPending)

        try await Task.sleep(nanoseconds: 80_000_000)
        XCTAssertEqual(expired, 1, "到期回调只允许执行一次")
    }

    func testCancelBeforeExpiryPreventsDeletion() async throws {
        let controller = DelayedUndoController()
        var expired = false
        controller.schedule(delay: .milliseconds(60)) { expired = true }

        XCTAssertTrue(controller.isPending)
        controller.cancel()
        XCTAssertFalse(controller.isPending)

        try await Task.sleep(nanoseconds: 140_000_000)
        XCTAssertFalse(expired, "撤销后旧任务不得删除目标")
    }

    func testRescheduleInvalidatesEarlierToken() async throws {
        let controller = DelayedUndoController()
        var expired = 0
        controller.schedule(delay: .milliseconds(40)) { expired += 1 } // 旧任务
        controller.schedule(delay: .milliseconds(160)) { expired += 10 } // 新任务

        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertEqual(expired, 0, "旧 token 到期时不得触发")

        try await Task.sleep(nanoseconds: 140_000_000)
        XCTAssertEqual(expired, 10, "只应执行最新 token 的回调")
        XCTAssertFalse(controller.isPending)
    }
}
