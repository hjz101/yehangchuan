import Foundation

/// 旧快照迁移。
///
/// 旧格式是一个 JSON：书架、书源、摘录、设置、书签、阅读位置、分组，
/// 外加 `customChapters`（书 ID → 整本书的章节正文）。
///
/// 迁移做三件事，任何一件失败都不写盘：
/// 1. 把 `customChapters` 从索引里摘出来，逐章转成 `StoredChapter`；
/// 2. 段落 ID 从「章ID-p序号」换成内容寻址，避免以后删首行时书签错位；
/// 3. 索引加 `version`，其余分区原样保留（不认识的分区也留着，不丢字段）。
public enum LegacySnapshotMigration {
    public struct Result: Sendable {
        public var index: LibraryIndex
        /// 书 ID → 章节。调用方逐本调用 `LibraryStorage.saveChapters`。
        public var chapters: [String: [StoredChapter]]
        /// 迁移中的非致命问题（某章没有段落、某书章节为空等），要显示给用户。
        public var warnings: [String]
        /// 旧版段落 ID → 新段落 ID（按书）。书签与阅读位置用它重写。
        public var paragraphIDMap: [String: [String: String]]
    }

    /// 迁移入口。`data` 是旧 `snapshot.json` 的原始字节。
    public static func migrate(_ data: Data) throws -> Result {
        let value: JSONValue
        do {
            value = try JSONDecoder().decode(JSONValue.self, from: data)
        } catch {
            throw MigrationError.unreadable
        }
        guard var sections = value.objectValue else { throw MigrationError.notAnObject }

        // 已经是新格式：原样交回，章节正文已在独立文件里。
        var index = try readIndex(from: sections)
        let legacyChapters = sections.removeValue(forKey: "customChapters")
        index.sections = sections

        var chapters: [String: [StoredChapter]] = [:]
        var warnings: [String] = []
        var paragraphIDMap: [String: [String: String]] = [:]

        if let legacyChapters {
            guard let books = legacyChapters.objectValue else {
                throw MigrationError.malformedChapters
            }
            for (bookID, chaptersValue) in books {
                guard let list = chaptersValue.arrayValue else {
                    warnings.append("《\(bookID)》的章节数据格式不对，已跳过。")
                    continue
                }
                var converted: [StoredChapter] = []
                var map: [String: String] = [:]
                for (order, item) in list.enumerated() {
                    guard let object = item.objectValue,
                          let chapterID = object["id"]?.stringValue,
                          let title = object["title"]?.stringValue else {
                        warnings.append("《\(bookID)》第 \(order + 1) 章缺少 ID 或标题，已跳过。")
                        continue
                    }
                    let networkURL = object["networkURL"]?.stringValue
                    let rawParagraphs = object["paragraphs"]?.arrayValue ?? []
                    var texts: [String] = []
                    var oldIDs: [String] = []
                    var attachments: [JSONValue?] = []
                    for paragraph in rawParagraphs {
                        guard let dictionary = paragraph.objectValue,
                              let text = dictionary["text"]?.stringValue else { continue }
                        texts.append(text)
                        oldIDs.append(dictionary["id"]?.stringValue ?? "")
                        // 除 id / text 之外的字段（段评等）原样搬走。
                        var rest = dictionary
                        rest.removeValue(forKey: "id")
                        rest.removeValue(forKey: "text")
                        attachments.append(rest.isEmpty ? nil : .object(rest))
                    }

                    let newIDs = ContentID.paragraphIDs(chapterID: chapterID, paragraphs: texts)
                    for (old, new) in zip(oldIDs, newIDs) where !old.isEmpty {
                        map[old] = new
                    }
                    converted.append(
                        StoredChapter(
                            id: chapterID,
                            title: title,
                            order: order,
                            paragraphs: zip(newIDs, texts).enumerated().map { offset, pair in
                                StoredChapter.Paragraph(id: pair.0, text: pair.1, attachments: attachments[offset])
                            },
                            networkURL: networkURL
                        )
                    )
                }
                if converted.isEmpty {
                    warnings.append("《\(bookID)》迁移后没有可用章节，正文未搬移。")
                } else {
                    chapters[bookID] = converted
                }
                paragraphIDMap[bookID] = map
            }
            if chapters.isEmpty, !warnings.isEmpty {
                throw MigrationError.noUsableChapters(warnings)
            }
        }

        // 只有真的搬了正文才改写清单：否则重跑迁移会把已有清单清空，
        // App 随后就找不到章节文件，等于把书库抹掉。
        if legacyChapters != nil {
            index.booksWithChapters = chapters.keys.sorted()
        }
        return Result(
            index: index,
            chapters: chapters,
            warnings: warnings,
            paragraphIDMap: paragraphIDMap
        )
    }

    /// 读出索引字段，兼容「已有 version」和「没有 version」两种输入。
    private static func readIndex(from sections: [String: JSONValue]) throws -> LibraryIndex {
        if let version = sections["version"]?.intValue {
            guard version <= LibraryIndex.currentVersion else {
                throw MigrationError.fromFuture(version)
            }
            var index = LibraryIndex(version: version)
            index.booksWithChapters = sections["booksWithChapters"]?.arrayValue?.compactMap(\.stringValue) ?? []
            return index
        }
        // 没有 version：这是第一代格式，按 v1 处理。
        return LibraryIndex(version: LibraryIndex.currentVersion)
    }

    /// 把书签与阅读位置里的旧段落 ID 换成新 ID。
    ///
    /// 旧版 `paragraphID` 是「章ID-p序号」，章节内容一变就指错。
    /// 迁移时能映射的映射，映射不到的留空 —— 宁可退化成「回到本章开头」，
    /// 也不要保留一个假锚点让用户跳到不相干的段落。
    ///
    /// 这里直接在原始 JSON 上改 `paragraphID` 一个键，不用强类型 struct 转码：
    /// 强类型只声明部分字段时，重新编码会把 `chapterTitle`、`offset`、
    /// `progress`、`updatedAt` 这些没声明的字段悄悄丢掉。
    public static func remapAnchorIDs(
        in index: inout LibraryIndex,
        using paragraphIDMap: [String: [String: String]],
        warnings: inout [String]
    ) throws {
        if case .object(var positions)? = index.sections["positions"] {
            var dropped = 0
            for (bookID, value) in positions {
                guard let map = paragraphIDMap[bookID],
                      case .object(var position) = value,
                      let current = position["paragraphID"]?.stringValue, !current.isEmpty else { continue }
                if let mapped = map[current] {
                    position["paragraphID"] = .string(mapped)
                } else {
                    position["paragraphID"] = .string("")
                    dropped += 1
                }
                positions[bookID] = .object(position)
            }
            index.sections["positions"] = .object(positions)
            if dropped > 0 {
                warnings.append("有 \(dropped) 本书的阅读位置指向已不存在的段落，已退回该章开头。")
            }
        }

        if case .array(var bookmarks)? = index.sections["bookmarks"] {
            var dropped = 0
            for offset in bookmarks.indices {
                guard case .object(var bookmark) = bookmarks[offset],
                      let bookID = bookmark["bookID"]?.stringValue,
                      let map = paragraphIDMap[bookID],
                      let current = bookmark["paragraphID"]?.stringValue else { continue }
                if let mapped = map[current] {
                    bookmark["paragraphID"] = .string(mapped)
                } else {
                    // 映射不到就删掉这个键：界面会回退到按页定位，
                    // 留一个假 ID 反而会跳到不相干的段落。
                    bookmark.removeValue(forKey: "paragraphID")
                    dropped += 1
                }
                bookmarks[offset] = .object(bookmark)
            }
            index.sections["bookmarks"] = .array(bookmarks)
            if dropped > 0 {
                warnings.append("有 \(dropped) 条书签的段落已不存在，已改为按页定位。")
            }
        }
    }

}

public enum MigrationError: Error, LocalizedError, Equatable, Sendable {
    case unreadable
    case notAnObject
    case malformedChapters
    case noUsableChapters([String])
    case fromFuture(Int)

    public var errorDescription: String? {
        switch self {
        case .unreadable:
            "旧书架文件无法读取，原文件已保留。"
        case .notAnObject:
            "旧书架文件结构不认识，原文件已保留。"
        case .malformedChapters:
            "旧书架文件里的章节数据损坏，原文件已保留。"
        case .noUsableChapters(let warnings):
            "旧书架里没有可用的章节正文。\(warnings.joined(separator: " "))"
        case .fromFuture(let version):
            "书架数据的版本（\(version)）比当前 App 新，请先升级 App。"
        }
    }
}
