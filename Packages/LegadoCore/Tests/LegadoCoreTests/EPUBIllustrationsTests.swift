import Foundation
import XCTest
import ZIPFoundation
@testable import LegadoCore

final class EPUBIllustrationsTests: XCTestCase {
    private let imageData = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])

    /// 一章「正常图 + 缺失图」、一章「只有缺失图」。
    /// 以前任何一张图取不到都会让 `illustrations(chapter:)` 整章抛错。
    func testMissingImageIsSkippedWithoutFailingChapter() throws {
        let url = try makeEPUB()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        let epub = try EPUBBook(url: url)
        let book = Book(bookUrl: url.absoluteString, name: "插图测试")
        let chapters = try epub.chapters(book: book)
        XCTAssertEqual(chapters.count, 2)

        let illustrations = try epub.illustrations(chapter: chapters[0])
        XCTAssertEqual(illustrations.count, 1)
        XCTAssertEqual(illustrations.first?.caption, "正常图片")
        XCTAssertEqual(illustrations.first?.data, imageData)

        // 整章没有一张可读图片时返回空数组，而不是抛错。
        XCTAssertTrue(try epub.illustrations(chapter: chapters[1]).isEmpty)
    }

    // MARK: - Fixture

    private func makeEPUB() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("EPUBIllustrationsTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("fixture.epub")
        let archive = try Archive(url: url, accessMode: .create)
        let entries: [(String, Data)] = [
            ("mimetype", Data("application/epub+zip".utf8)),
            ("META-INF/container.xml", Data(containerXML.utf8)),
            ("OEBPS/content.opf", Data(packageDocument.utf8)),
            ("OEBPS/text/chapter1.xhtml", Data(chapter1.utf8)),
            ("OEBPS/text/chapter2.xhtml", Data(chapter2.utf8)),
            ("OEBPS/images/ok.png", imageData)
        ]
        for (path, data) in entries {
            try archive.addEntry(with: path, type: .file, uncompressedSize: Int64(data.count)) { _, _ in
                data
            }
        }
        return url
    }

    private var containerXML: String {
        """
        <?xml version="1.0" encoding="UTF-8"?>
        <container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
          <rootfiles>
            <rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/>
          </rootfiles>
        </container>
        """
    }

    private var packageDocument: String {
        """
        <?xml version="1.0" encoding="UTF-8"?>
        <package xmlns="http://www.idpf.org/2007/opf" version="3.0" unique-identifier="bookid">
          <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
            <dc:title>插图测试</dc:title>
            <dc:identifier id="bookid">epub-illustrations-test</dc:identifier>
          </metadata>
          <manifest>
            <item id="chapter1" href="text/chapter1.xhtml" media-type="application/xhtml+xml"/>
            <item id="chapter2" href="text/chapter2.xhtml" media-type="application/xhtml+xml"/>
            <item id="ok" href="images/ok.png" media-type="image/png"/>
          </manifest>
          <spine>
            <itemref idref="chapter1"/>
            <itemref idref="chapter2"/>
          </spine>
        </package>
        """
    }

    private var chapter1: String {
        """
        <?xml version="1.0" encoding="UTF-8"?>
        <html xmlns="http://www.w3.org/1999/xhtml">
          <head><title>第一章</title></head>
          <body>
            <p>正文</p>
            <img src="../images/ok.png" alt="正常图片"/>
            <img src="../images/missing.png" alt="缺失图片"/>
          </body>
        </html>
        """
    }

    private var chapter2: String {
        """
        <?xml version="1.0" encoding="UTF-8"?>
        <html xmlns="http://www.w3.org/1999/xhtml">
          <head><title>第二章</title></head>
          <body>
            <p>正文</p>
            <img src="../images/missing.png" alt="缺失图片"/>
          </body>
        </html>
        """
    }
}
