import XCTest
@testable import LegadoCore

final class ReadingActivityTests: XCTestCase {
    private var calendar: Calendar!
    private var today: Date!

    override func setUp() {
        super.setUp()
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        self.calendar = calendar
        today = calendar.startOfDay(for: Date())
    }

    func testAccumulatesByDayAndBook() {
        let service = ReadingActivityService()
        let now = Int64(today.timeIntervalSince1970 * 1_000)
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today)!

        var records = service.addingReadTime(
            30 * 60_000, deviceID: "local", bookName: "甲", now: now, to: [], calendar: calendar
        )
        records = service.addingReadTime(
            15 * 60_000, deviceID: "local", bookName: "甲",
            now: Int64(yesterday.timeIntervalSince1970 * 1_000), to: records, calendar: calendar
        )
        records = service.addingReadTime(
            12 * 60_000, deviceID: "local", bookName: "乙", now: now, to: records, calendar: calendar
        )

        XCTAssertEqual(records.count, 2)
        let a = records.first { $0.bookName == "甲" }!
        XCTAssertEqual(a.readTime, 45 * 60_000)
        XCTAssertEqual(a.dailyReadTimes[ReadingActivityService.dayKey(for: today, calendar: calendar)], 30 * 60_000)
        XCTAssertEqual(a.dailyReadTimes[ReadingActivityService.dayKey(for: yesterday, calendar: calendar)], 15 * 60_000)
    }

    func testStatisticsTodayStreakAndRecentDays() {
        let service = ReadingActivityService()
        let now = Int64(today.timeIntervalSince1970 * 1_000)
        var records = [] as [ReadRecord]
        for offset in 0..<3 {
            let date = calendar.date(byAdding: .day, value: -offset, to: today)!
            records = service.addingReadTime(
                Int64(20 + offset) * 60_000, deviceID: "local", bookName: "甲",
                now: Int64(date.timeIntervalSince1970 * 1_000), to: records, calendar: calendar
            )
        }

        let stats = service.statistics(records, now: today, calendar: calendar)
        XCTAssertEqual(stats.todayReadTime, 20 * 60_000)
        XCTAssertEqual(stats.currentStreak, 3)
        XCTAssertEqual(stats.bookCount, 1)
        XCTAssertEqual(stats.recentDays.count, 7)
        XCTAssertEqual(stats.recentDays.last?.readTime, 20 * 60_000)
    }

    func testZeroElapsedAndEmptyNameAreIgnored() {
        let service = ReadingActivityService()
        let now = Int64(today.timeIntervalSince1970 * 1_000)
        XCTAssertTrue(service.addingReadTime(
            0, deviceID: "local", bookName: "甲", now: now, to: [], calendar: calendar
        ).isEmpty)
        XCTAssertTrue(service.addingReadTime(
            60_000, deviceID: "local", bookName: "", now: now, to: [], calendar: calendar
        ).isEmpty)
    }

    func testFileRepositoryRoundTrip() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ReadingActivityTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let repo = FileReadingActivityRepository(
            bookmarksURL: root.appendingPathComponent("bookmarks.json"),
            recordsURL: root.appendingPathComponent("records.json")
        )
        let service = ReadingActivityService()
        let records = service.addingReadTime(
            42 * 60_000, deviceID: "local", bookName: "甲",
            now: Int64(today.timeIntervalSince1970 * 1_000), to: [], calendar: calendar
        )

        try await repo.saveReadRecords(records)
        let loaded = try await repo.loadReadRecords()
        XCTAssertEqual(loaded, records)
    }
}
