import CoreGraphics
import ImageIO
import XCTest
import ZIPFoundation
@testable import LegadoCore

final class ComicArchiveTests: XCTestCase {
    private enum FixtureError: Error { case unavailable }

    // MARK: - Fixtures

    private func makePNG(width: Int, height: Int) throws -> Data {
        guard let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { throw FixtureError.unavailable }
        context.setFillColor(red: 0.2, green: 0.4, blue: 0.6, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        guard let image = context.makeImage() else { throw FixtureError.unavailable }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, "public.png" as CFString, 1, nil) else {
            throw FixtureError.unavailable
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw FixtureError.unavailable }
        return output as Data
    }

    private func makeZip(
        named name: String = "comic.zip",
        entries: [(path: String, type: Entry.EntryType, data: Data)]
    ) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ComicArchiveTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent(name)
        let archive = try Archive(url: url, accessMode: .create)
        for entry in entries {
            try archive.addEntry(with: entry.path, type: entry.type, uncompressedSize: Int64(entry.data.count)) { _, _ in
                entry.data
            }
        }
        return url
    }

    // MARK: - Tests

    func testNaturalPageOrderAndFolderChapters() throws {
        let image = try makePNG(width: 8, height: 8)
        let url = try makeZip(entries: [
            ("第1话/page-10.png", .file, image),
            ("第1话/page-2.png", .file, image),
            ("第2话/001.png", .file, image),
            ("第2话/2.png", .file, image),
            ("notes.txt", .file, Data("not a page".utf8))
        ])
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        let report = try ComicArchive.inspect(url: url)
        XCTAssertEqual(report.pageCount, 4)
        XCTAssertEqual(report.chapterTitles, ["第1话", "第2话"])
        XCTAssertEqual(report.pages.map(\.path), [
            "第1话/page-2.png", "第1话/page-10.png", "第2话/001.png", "第2话/2.png"
        ])
        XCTAssertEqual(report.pages.map(\.chapter), ["第1话", "第1话", "第2话", "第2话"])
        XCTAssertEqual(try ComicArchive.pageData(url: url, path: report.pages[0].path), image)
    }

    func testRootLevelImagesUseSingleChapter() throws {
        let image = try makePNG(width: 8, height: 8)
        let url = try makeZip(entries: [
            ("cover.jpg", .file, image),
            ("page2.jpg", .file, image)
        ])
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        let report = try ComicArchive.inspect(url: url)
        XCTAssertEqual(report.chapterTitles, ["全本"])
        XCTAssertEqual(report.pages.map(\.path), ["cover.jpg", "page2.jpg"])
    }

    func testRejectsZipSlipAndSymlink() throws {
        let image = try makePNG(width: 8, height: 8)
        let slip = try makeZip(named: "slip.zip", entries: [
            ("page.png", .file, image),
            ("../evil.png", .file, image)
        ])
        defer { try? FileManager.default.removeItem(at: slip.deletingLastPathComponent()) }
        XCTAssertThrowsError(try ComicArchive.inspect(url: slip)) { error in
            guard case ComicBookError.invalidArchive = error else {
                return XCTFail("expected invalidArchive, got \(error)")
            }
        }

        let linked = try makeZip(named: "linked.zip", entries: [
            ("page.png", .file, image),
            ("link.png", .symlink, Data("../evil.png".utf8))
        ])
        defer { try? FileManager.default.removeItem(at: linked.deletingLastPathComponent()) }
        // symlink 被跳过（而不是当成页面），剩下 page.png 仍可正常读取。
        let report = try ComicArchive.inspect(url: linked)
        XCTAssertEqual(report.pages.map(\.path), ["page.png"])
    }

    func testNoImagesAndUnsupportedFormat() throws {
        let empty = try makeZip(named: "empty.zip", entries: [
            ("notes.txt", .file, Data("nothing".utf8))
        ])
        defer { try? FileManager.default.removeItem(at: empty.deletingLastPathComponent()) }
        XCTAssertThrowsError(try ComicArchive.inspect(url: empty)) { error in
            guard case ComicBookError.noImages = error else {
                return XCTFail("expected noImages, got \(error)")
            }
        }

        let wrong = empty.deletingLastPathComponent().appendingPathComponent("book.txt")
        XCTAssertThrowsError(try ComicArchive.inspect(url: wrong)) { error in
            guard case ComicBookError.unsupportedFormat = error else {
                return XCTFail("expected unsupportedFormat, got \(error)")
            }
        }
    }

    func testThumbnailDownsamplesToJPEG() throws {
        let image = try makePNG(width: 400, height: 400)
        let url = try makeZip(entries: [("page.png", .file, image)])
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        let report = try ComicArchive.inspect(url: url)
        let thumbnail = try ComicArchive.thumbnail(url: url, path: report.pages[0].path, maxPixelSize: 64)
        XCTAssertLessThan(thumbnail.count, image.count)
        XCTAssertEqual(thumbnail.prefix(3), Data([0xFF, 0xD8, 0xFF])) // JPEG magic
        XCTAssertEqual(try ComicArchive.pageData(url: url, path: report.pages[0].path), image)
    }

    func testServiceFacadeAndFileSizeLimit() throws {
        let image = try makePNG(width: 8, height: 8)
        let url = try makeZip(entries: [("page.png", .file, image)])
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        let service = LocalBookService.live()
        XCTAssertTrue(LocalBookService.supportsComic(url))
        let report = try service.inspectComic(at: url)
        XCTAssertEqual(report.pageCount, 1)
        XCTAssertEqual(try service.loadComicPage(at: url, path: report.pages[0].path), image)

        let tiny = LocalBookService(maximumFileSize: 8)
        XCTAssertThrowsError(try tiny.inspectComic(at: url)) { error in
            guard case LocalBookError.oversized = error else {
                return XCTFail("expected oversized, got \(error)")
            }
        }
    }
}
