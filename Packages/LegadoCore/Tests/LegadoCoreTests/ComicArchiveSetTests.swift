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
}
