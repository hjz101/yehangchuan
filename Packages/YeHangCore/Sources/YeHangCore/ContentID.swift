import CryptoKit
import Foundation

/// 内容寻址的稳定 ID。
///
/// 段落 ID 由「章节 ID + 段落文本摘要 + 该文本在本章第几次出现」算出，
/// 不用段号：删掉一章开头的重复标题、插入或重排段落时，
/// 其余段落的 ID 全部不变，书签与阅读位置不会在背后指错地方。
public enum ContentID {
    /// 段落 ID。同名段落（正文里重复的一句话）靠 occurrence 区分。
    public static func paragraph(chapterID: String, text: String, occurrence: Int) -> String {
        digest(components: ["p", chapterID, version(text), String(occurrence)])
    }

    /// 章节 ID。用「书 ID + 序号 + 标题」定身份，不使用时间戳或随机数，
    /// 这样同一本书重新导入后章节 ID 不变。
    public static func chapter(bookID: String, index: Int, title: String) -> String {
        digest(components: ["c", bookID, String(index), title])
    }

    /// 任意组件拼接后的摘要。组件带长度前缀，避免 "a:b"+"c" 与 "a"+"b:c" 撞车。
    public static func digest(components: [String]) -> String {
        var bytes = Data()
        for component in components {
            let value = Data(component.utf8)
            var length = UInt64(value.count).bigEndian
            withUnsafeBytes(of: &length) { bytes.append(contentsOf: $0) }
            bytes.append(value)
        }
        return hex(SHA256.hash(data: bytes))
    }

    /// 文本内容的版本号：同一段文字改字后版本必变，用于判断锚点是否仍精确。
    public static func version(_ text: String) -> String {
        digest(components: ["v", text])
    }

    static func hex<Bytes: Sequence>(_ bytes: Bytes) -> String where Bytes.Element == UInt8 {
        let digits = Array("0123456789abcdef".utf8)
        var result: [UInt8] = []
        result.reserveCapacity(bytes.underestimatedCount * 2)
        for byte in bytes {
            result.append(digits[Int(byte >> 4)])
            result.append(digits[Int(byte & 0x0F)])
        }
        return String(decoding: result, as: UTF8.self)
    }

    /// 给一组段落分配 ID，同文多次出现时递增 occurrence。
    public static func paragraphIDs(chapterID: String, paragraphs: [String]) -> [String] {
        var occurrences: [String: Int] = [:]
        return paragraphs.map { text in
            let version = self.version(text)
            let occurrence = occurrences[version, default: 0]
            occurrences[version] = occurrence + 1
            return paragraph(chapterID: chapterID, text: text, occurrence: occurrence)
        }
    }
}
