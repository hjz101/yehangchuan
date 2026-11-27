import XCTest
import ZIPFoundation
@testable import LegadoCore

final class ArchiveExportTests: XCTestCase {
    private enum TestError: Error { case missing }

    func testZipRoundTrip() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ArchiveExportTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("export.zip")
        let json = Data(#"{"books":[]}"#.utf8)
        let notes = Data("# 摘录".utf8)

        try ArchiveExporter.write([
            .init(name: "books.json", data: json),
            .init(name: "notes.md", data: notes)
        ], to: url)

        let archive = try Archive(url: url, accessMode: .read)
        let entries = Dictionary(uniqueKeysWithValues: archive.compactMap { entry -> (String, Entry)? in
            guard entry.type == .file else { return nil }
            return (entry.path, entry)
        })
        XCTAssertEqual(Set(entries.keys), ["books.json", "notes.md"])
        func contents(of name: String) throws -> Data {
            guard let entry = entries[name] else { throw TestError.missing }
            var data = Data()
            _ = try archive.extract(entry) { data.append($0) }
            return data
        }
        XCTAssertEqual(try contents(of: "books.json"), json)
        XCTAssertEqual(try contents(of: "notes.md"), notes)
    }

    func testRejectsTraversalAndDuplicates() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ArchiveExportTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("bad.zip")

        for name in ["../evil.txt", "a/b.txt", ""] {
            XCTAssertThrowsError(try ArchiveExporter.write([.init(name: name, data: Data("x".utf8))], to: url)) { error in
                guard case ArchiveExportError.invalidName = error else {
                    return XCTFail("expected invalidName for \(name), got \(error)")
                }
            }
        }
        XCTAssertThrowsError(try ArchiveExporter.write([
            .init(name: "a.txt", data: Data("1".utf8)),
            .init(name: "a.txt", data: Data("2".utf8))
        ], to: url)) { error in
            guard case ArchiveExportError.invalidName = error else {
                return XCTFail("expected invalidName for duplicate, got \(error)")
            }
        }
        XCTAssertThrowsError(try ArchiveExporter.write([], to: url)) { error in
            guard case ArchiveExportError.empty = error else {
                return XCTFail("expected empty, got \(error)")
            }
        }
    }
}
