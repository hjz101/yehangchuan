import Foundation
import XCTest
@testable import LegadoCore

final class LocalBookServiceTests: XCTestCase {
    /// 无目录切章时，文件末尾的多字节残片曾让内层 while 不再推进游标，
    /// 外层循环原地空转。这里构造一个 512KB 以上、末尾截断 UTF-8 字符的 TXT，
    /// 要求 loadChapters 必须有限时间内返回。
    func testTruncatedMultibyteTailWithoutTocTerminates() async throws {
        var data = Data()
        let line = Data((String(repeating: "A", count: 4_000) + "\n").utf8)
        for _ in 0..<128 { data.append(line) }
        // "😘" 的 UTF-8 只保留前三个字节。
        data.append(contentsOf: [0xF0, 0x9F, 0x98])

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("yh-truncated-\(UUID().uuidString).txt")
        try data.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        let book = Book(bookUrl: url.absoluteString, name: "截断测试")
        let service = LocalBookService()
        let report = try await withThrowingTaskGroup(of: ChapterListReport.self) { group in
            group.addTask { try service.loadChapters(book: book) }
            group.addTask {
                try await Task.sleep(nanoseconds: 5_000_000_000)
                throw LocalBookError.emptyFile
            }
            defer { group.cancelAll() }
            guard let first = try await group.next() else { throw LocalBookError.emptyFile }
            group.cancelAll()
            return first
        }

        XCTAssertFalse(report.chapters.isEmpty)
        XCTAssertEqual(report.chapters.last?.end, Int64(data.count))
    }
}
