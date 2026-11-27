import Foundation
import XCTest
@testable import LegadoCore

/// 私网闸门是所有引擎请求的唯一判定点：JS 桥、首请求、重定向每一跳都过它。
/// 这里钉住三件事：未注入时的兜底、App 注入后以注入为准、请求检查会抛错。
final class PrivateHostGateTests: XCTestCase {
    override func setUp() {
        super.setUp()
        PrivateHostGate.resetForTesting()
    }

    override func tearDown() {
        PrivateHostGate.resetForTesting()
        super.tearDown()
    }

    func testFallbackBlocksLocalhostAndPrivateRanges() {
        XCTAssertTrue(PrivateHostGate.shouldBlock("localhost"))
        XCTAssertTrue(PrivateHostGate.shouldBlock("127.0.0.1"))
        XCTAssertTrue(PrivateHostGate.shouldBlock("10.0.0.5"))
        XCTAssertTrue(PrivateHostGate.shouldBlock("192.168.1.20"))
        XCTAssertTrue(PrivateHostGate.shouldBlock("172.16.4.9"))
    }

    func testFallbackAllowsPublicHostsAndNil() {
        XCTAssertFalse(PrivateHostGate.shouldBlock("example.com"))
        XCTAssertFalse(PrivateHostGate.shouldBlock("8.8.8.8"))
        XCTAssertFalse(PrivateHostGate.shouldBlock(nil))
    }

    func testInjectedPredicateReplacesFallback() {
        PrivateHostGate.configure { $0 == "blocked.example" }
        XCTAssertTrue(PrivateHostGate.shouldBlock("BLOCKED.EXAMPLE"))
        // 注入后完全按 App 的口径走，兜底规则不再叠加。
        XCTAssertFalse(PrivateHostGate.shouldBlock("127.0.0.1"))
    }

    func testRequestCheckThrowsForBlockedHost() {
        PrivateHostGate.configure { $0 == "blocked.example" }
        let request = URLRequest(url: URL(string: "https://blocked.example/chapter")!)
        XCTAssertThrowsError(try PrivateHostGate.check(request)) { error in
            guard case PrivateHostError.blocked(let host) = error else {
                return XCTFail("期望 blocked 错误，实际是 \(error)")
            }
            XCTAssertEqual(host, "blocked.example")
        }
    }

    func testRequestCheckAllowsPublicHost() {
        PrivateHostGate.configure { $0 == "blocked.example" }
        let request = URLRequest(url: URL(string: "https://example.com/search")!)
        XCTAssertNoThrow(try PrivateHostGate.check(request))
    }
}
