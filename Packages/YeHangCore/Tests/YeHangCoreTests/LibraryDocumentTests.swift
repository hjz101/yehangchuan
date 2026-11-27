import Foundation
import XCTest
@testable import YeHangCore

final class LibraryDocumentTests: XCTestCase {
    private var root: URL!
    private var storage: LibraryStorage!

    override func setUpWithError() throws {
        try super.setUpWithError()
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("yh-doc-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        storage = LibraryStorage(root: root)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
        try super.tearDownWithError()
    }

    private func chapter(_ id: String, order: Int, texts: [String]) -> StoredChapter {
        StoredChapter(
            id: id,
            title: "第 \(order + 1) 章",
            order: order,
            paragraphs: texts.map { StoredChapter.Paragraph(id: "\(id)-\($0)", text: $0) }
        )
    }

    // MARK: 写

    /// 保存一次的完整往返：索引分区与正文都要读得回来，且顺序按 order。
    func testWriteThenReadRoundTripsSectionsAndChapters() throws {
        let plan = LibraryWritePlan(
            sections: ["books": .array([.object(["id": .string("b1")])])],
            chapters: [
                "b1": [chapter("c1", order: 1, texts: ["后"]), chapter("c0", order: 0, texts: ["先"])]
            ],
            replacedBooks: ["b1"],
            booksWithChapters: ["b1"]
        )

        let written = try LibraryDocumentWriter.write(plan, to: storage)
        XCTAssertEqual(written.version, LibraryIndex.currentVersion)
        XCTAssertEqual(written.sections["books"]?.arrayValue?.count, 1)
        XCTAssertFalse(written.sections.keys.contains("customChapters"), "正文不能回到索引里")

        let document = try readDocument()
        XCTAssertEqual(document.chapters["b1"]?.map(\.id), ["c0", "c1"])
        XCTAssertTrue(document.failures.isEmpty)
    }

    /// 增量写：只写动过的那本书，其他书的正文原样保留。
    /// 翻一页只重编码一本，这是分书存储的意义所在。
    func testWritingOneBookLeavesOthersUntouched() throws {
        try LibraryDocumentWriter.write(
            LibraryWritePlan(
                sections: ["books": .array([])],
                chapters: ["a": [chapter("a0", order: 0, texts: ["甲"])]],
                replacedBooks: ["a"],
                booksWithChapters: ["a"]
            ),
            to: storage
        )
        let before = try storage.chapters(bookID: "a")

        try LibraryDocumentWriter.write(
            LibraryWritePlan(
                sections: ["books": .array([])],
                chapters: ["b": [chapter("b0", order: 0, texts: ["乙"])]],
                booksWithChapters: ["a", "b"]
            ),
            to: storage
        )

        XCTAssertEqual(try storage.chapters(bookID: "a"), before)
        XCTAssertEqual(try storage.chapters(bookID: "b").count, 1)
    }

    /// 整本替换必须把旧章节从清单里摘掉，否则换源后目录会翻倍。
    func testReplacingBookDropsOldChapters() throws {
        try storage.saveChapters(
            [chapter("old0", order: 0, texts: ["旧一"]), chapter("old1", order: 1, texts: ["旧二"])],
            bookID: "b1"
        )
        try libraryWrite(chapters: ["b1": [chapter("new0", order: 0, texts: ["新"])]], replace: ["b1"])

        XCTAssertEqual(try storage.chapters(bookID: "b1").map(\.id), ["new0"])
    }

    /// 换源替换正文后，旧章节对象应被写入器回收，不该一直占着磁盘。
    func testWriterReclaimsOrphanObjectsAfterReplace() throws {
        try libraryWrite(
            chapters: ["b1": [chapter("old", order: 0, texts: ["旧内容"])]],
            replace: ["b1"]
        )
        let objects = storage.bookDirectory("b1").appendingPathComponent("objects", isDirectory: true)
        func objectCount() throws -> Int {
            try FileManager.default.contentsOfDirectory(atPath: objects.path).count
        }
        XCTAssertEqual(try objectCount(), 1)

        try libraryWrite(
            chapters: ["b1": [chapter("new", order: 0, texts: ["全新内容"])]],
            replace: ["b1"]
        )
        XCTAssertEqual(try objectCount(), 1, "旧对象应被回收，只留新内容那一个")
        XCTAssertEqual(try storage.chapters(bookID: "b1").map(\.id), ["new"])
    }

    /// 增量写不该悄悄删掉没提到的章节：它是「补充」，不是「替换」。
    func testSavingChaptersKeepsChaptersNotMentioned() throws {
        try storage.saveChapters(
            [chapter("c0", order: 0, texts: ["正文"]), chapter("c1", order: 1, texts: ["正文二"])],
            bookID: "b1"
        )
        // 只有第一章被重新拉取正文
        try storage.saveChapters([chapter("c0", order: 0, texts: ["改过的正文"])], bookID: "b1")

        let chapters = try storage.chapters(bookID: "b1")
        XCTAssertEqual(chapters.map(\.id), ["c0", "c1"], "没提到的章节必须还在")
        XCTAssertEqual(chapters[0].paragraphs.map(\.text), ["改过的正文"])
    }

    // MARK: 删

    /// 删书之后，索引不能再指向它，磁盘上也不该留正文。
    func testRemovedBookIsDeletedAfterIndexIsWritten() throws {
        try libraryWrite(chapters: ["b1": [chapter("c0", order: 0, texts: ["正文"])]], replace: ["b1"], listed: ["b1"])
        XCTAssertTrue(FileManager.default.fileExists(atPath: storage.bookDirectory("b1").path))

        try LibraryDocumentWriter.write(
            LibraryWritePlan(
                sections: ["books": .array([])],
                booksWithChapters: [],
                removedBooks: ["b1"]
            ),
            to: storage
        )

        XCTAssertFalse(FileManager.default.fileExists(atPath: storage.bookDirectory("b1").path))
        let document = try readDocument()
        XCTAssertNil(document.chapters["b1"])
    }

    // MARK: 读的容错

    /// 一本书的正文坏了，别的书必须照常读出来，坏的那本要留下原因。
    /// 整座书库因为一章读不到而变空，是绝不可接受的。
    func testBrokenBookDoesNotTakeDownTheLibrary() throws {
        try libraryWrite(
            chapters: [
                "good": [chapter("g0", order: 0, texts: ["完好"])],
                "bad": [chapter("d0", order: 0, texts: ["会坏"])]
            ],
            replace: ["good", "bad"],
            listed: ["bad", "good"]
        )
        // 删掉坏书的正文对象，模拟磁盘损坏
        let objects = storage.bookDirectory("bad").appendingPathComponent("objects")
        for url in try FileManager.default.contentsOfDirectory(at: objects, includingPropertiesForKeys: nil) {
            try FileManager.default.removeItem(at: url)
        }

        let document = try readDocument()
        XCTAssertEqual(document.chapters["good"]?.count, 1)
        XCTAssertNil(document.chapters["bad"])
        XCTAssertNotNil(document.failures["bad"], "读不出来的书必须留下原因")
    }

    /// 新版本写的数据，旧 App 不能猜着读。
    func testFutureIndexVersionIsRejected() throws {
        var index = LibraryIndex()
        index.version = LibraryIndex.currentVersion + 1
        try storage.saveIndex(index)

        XCTAssertThrowsError(try LibraryDocumentReader.read(from: storage)) { error in
            XCTAssertEqual(error as? LibraryStorageError, .unsupportedVersion(LibraryIndex.currentVersion + 1))
        }
    }

    func testMissingIndexMeansFirstLaunch() throws {
        XCTAssertNil(try readDocumentOrNil())
    }

    // MARK: 索引本身

    /// 索引里不放正文：这是「书架消失」那类问题的根因。
    func testIndexContainsNoChapterBodies() throws {
        try libraryWrite(chapters: ["b1": [chapter("c0", order: 0, texts: ["很长的正文"])]], replace: ["b1"], listed: ["b1"])

        let raw = try Data(contentsOf: storage.indexURL)
        let text = String(decoding: raw, as: UTF8.self)
        XCTAssertFalse(text.contains("很长的正文"), "索引里不该出现正文")
        XCTAssertFalse(text.contains("customChapters"))
    }

    /// 每次保存都写全量索引，但索引里只有元数据 —— 翻页写回不该随书库变大而变慢。
    func testIndexSizeStaysFlatAsChaptersGrow() throws {
        try libraryWrite(chapters: ["b1": [chapter("c0", order: 0, texts: ["正文"])]], replace: ["b1"], listed: ["b1"])
        let small = try Data(contentsOf: storage.indexURL).count

        var many: [StoredChapter] = []
        for index in 0..<200 {
            many.append(chapter("c\(index)", order: index, texts: ["正文\(index)"]))
        }
        try storage.replaceChapters(many, bookID: "b1")
        try LibraryDocumentWriter.write(
            LibraryWritePlan(sections: ["books": .array([])], booksWithChapters: ["b1"]),
            to: storage
        )
        let large = try Data(contentsOf: storage.indexURL).count

        XCTAssertEqual(small, large, "章节增加到 200 章，索引大小不应变化")
    }

    // MARK: 索引损坏与回退

    /// 索引写坏了必须退回上一版，而不是当作「没有书架」。
    /// 用户的感受差别很大：看到上次的内容 vs 看到空书架。
    func testCorruptIndexFallsBackToPreviousIndex() throws {
        try LibraryDocumentWriter.write(
            LibraryWritePlan(
                sections: ["books": .array([.object(["id": .string("b1")])])],
                chapters: ["b1": [chapter("c0", order: 0, texts: ["正文"])]],
                replacedBooks: ["b1"],
                booksWithChapters: ["b1"]
            ),
            to: storage
        )
        // 再存一次，这次 library.json 会被轮换成 library.prev.json
        try LibraryDocumentWriter.write(
            LibraryWritePlan(
                sections: ["books": .array([])],
                chapters: [:],
                booksWithChapters: ["b1"]
            ),
            to: storage
        )

        try Data("这不是 JSON".utf8).write(to: storage.indexURL)

        let result = try LibraryDocumentReader.read(from: storage)
        guard case .loaded(let document) = result else {
            return XCTFail("应当退回上一版索引，实际 \(result)")
        }
        XCTAssertTrue(document.recoveredFromPreviousIndex)
        XCTAssertEqual(document.index.sections["books"]?.arrayValue?.count, 1, "读到的是上一版内容")
    }

    /// 两份都坏了才报损坏 —— 这时调用方才知道该留档并降级到旧快照。
    func testBothIndexesCorruptReportsCorruption() throws {
        try libraryWrite(chapters: ["b1": [chapter("c0", order: 0, texts: ["正文"])]], replace: ["b1"])
        try Data("坏".utf8).write(to: storage.indexURL)
        try Data("也坏".utf8).write(to: storage.previousIndexURL)

        guard case .corrupt = try LibraryDocumentReader.read(from: storage) else {
            return XCTFail("两份索引都坏了，必须报损坏")
        }
    }

    /// 轮换不能把好的上一版顶掉：否则一次坏索引就等于没有回退点。
    func testSavingOverCorruptIndexKeepsPreviousGoodIndex() throws {
        try libraryWrite(chapters: ["b1": [chapter("c0", order: 0, texts: ["正文"])]], replace: ["b1"])
        try libraryWrite(chapters: ["b1": [chapter("c0", order: 0, texts: ["正文二"])]], replace: ["b1"])
        let goodPrevious = try Data(contentsOf: storage.previousIndexURL)

        try Data("坏".utf8).write(to: storage.indexURL)
        // 现在再存一次：当前索引读不懂，不该被当成「上一版」写下去。
        try LibraryDocumentWriter.write(
            LibraryWritePlan(sections: ["books": .array([])], booksWithChapters: ["b1"]),
            to: storage
        )

        XCTAssertEqual(
            try Data(contentsOf: storage.previousIndexURL),
            goodPrevious,
            "上一版必须还是那份好的"
        )
    }

    /// 数据比本 App 新时不能留档、不能覆盖：那是更新版 App 正在用的数据。
    func testFutureVersionIsNotQuarantined() throws {
        var index = LibraryIndex()
        index.version = LibraryIndex.currentVersion + 1
        try storage.saveIndex(index)

        XCTAssertThrowsError(try LibraryDocumentReader.read(from: storage))
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: storage.indexURL.path),
            "版本太新时绝不能改名留档"
        )
    }

    // MARK: 读的便捷封装

    private func readDocument() throws -> LibraryDocument {
        switch try LibraryDocumentReader.read(from: storage) {
        case .loaded(let document): return document
        case .none: throw CocoaError(.fileNoSuchFile)
        case .corrupt(let reason): throw CocoaError(.fileReadCorruptFile, userInfo: [NSLocalizedDescriptionKey: reason])
        }
    }

    private func readDocumentOrNil() throws -> LibraryDocument? {
        if case .loaded(let document) = try LibraryDocumentReader.read(from: storage) { return document }
        return nil
    }

    private func libraryWrite(
        chapters: [String: [StoredChapter]],
        replace: Set<String> = [],
        listed: [String] = []
    ) throws {
        try LibraryDocumentWriter.write(
            LibraryWritePlan(
                sections: ["books": .array([])],
                chapters: chapters,
                replacedBooks: replace,
                booksWithChapters: listed.isEmpty ? chapters.keys.sorted() : listed
            ),
            to: storage
        )
    }
}
