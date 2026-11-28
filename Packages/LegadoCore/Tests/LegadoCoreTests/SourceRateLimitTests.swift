import XCTest
@testable import LegadoCore

final class SourceRateLimitTests: XCTestCase {
    func testHugeIntervalIsClamped() throws {
        let limit = try XCTUnwrap(SourceRateLimit(rawValue: "1/99999999999999"))
        XCTAssertEqual(limit.intervalMilliseconds, SourceRateLimit.maximumIntervalMilliseconds)
    }

    func testWindowWaitNeverExceedsOneDay() {
        let limit = SourceRateLimit(rawValue: "1/99999999999999")!
        var window = SourceRateWindow()
        XCTAssertEqual(window.reserve(now: 1_000, limit: limit), 0)
        let wait = window.reserve(now: 1_001, limit: limit)
        XCTAssertEqual(wait, SourceRateLimit.maximumIntervalMilliseconds - 1)
        let nanoseconds = UInt64(wait).multipliedReportingOverflow(by: 1_000_000)
        XCTAssertFalse(nanoseconds.overflow)
    }
}
