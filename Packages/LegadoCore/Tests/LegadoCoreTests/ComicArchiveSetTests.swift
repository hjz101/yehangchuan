import XCTest
@testable import LegadoCore

final class ComicArchiveSetTests: XCTestCase {
    func testRecognisesAllComicFormats() {
        for ext in ["zip", "cbz", "rar", "cbr", "7z"] {
            XCTAssertTrue(ComicArchiveSet.supports(URL(string: "file:///tmp/comic.\(ext)")!))
        }
        XCTAssertFalse(ComicArchiveSet.supports(URL(string: "file:///tmp/comic.txt")!))
    }

    func testSevenZipFixtureUsesNaturalPageOrder() throws {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "comic", withExtension: "7z", subdirectory: "Fixtures"))
        let report = try ComicArchiveSet.inspect(url: url)
        XCTAssertEqual(report.pageCount, 2)
        XCTAssertEqual(report.chapterTitles, ["第1话"])
        XCTAssertEqual(report.pages.map(\.path), ["第1话/page-2.png", "第1话/page-10.png"])
        let data = try ComicArchiveSet.pageData(url: url, path: report.pages[0].path)
        XCTAssertEqual(data.prefix(4), Data([0x89, 0x50, 0x4E, 0x47]))
    }

    func testSevenZipSkipsOversizedPageInsteadOfFailingWholeBook() throws {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "comic", withExtension: "7z", subdirectory: "Fixtures"))
        XCTAssertThrowsError(
            try ComicArchiveSet(url: url, pageLimit: 1, maximumUncompressedSize: Int.max)
        ) { error in
            guard case ComicBookError.noImages = error else {
                return XCTFail("单页超限应跳过该页而不是整本失败，实际为 \(error)")
            }
        }
    }

    func testSevenZipRejectsExcessiveUncompressedTotal() throws {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "comic", withExtension: "7z", subdirectory: "Fixtures"))
        XCTAssertThrowsError(
            try ComicArchiveSet(url: url, pageLimit: ComicArchive.pageLimit, maximumUncompressedSize: 1)
        ) { error in
            guard case ComicBookError.resourceTooLarge = error else {
                return XCTFail("解压总量超限应拒绝，实际为 \(error)")
            }
        }
    }
}
