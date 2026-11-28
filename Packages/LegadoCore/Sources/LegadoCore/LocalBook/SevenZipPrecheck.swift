import Foundation
import SWCompression

/// 7z 解压炸弹防护：在任何解压发生之前，按 7z 规范直接解析头部结构做门槛。
///
/// SWCompression 的 `SevenZipContainer.open` 是「先解压、后校验」：
/// - LZMA 解码器虽然受声明值硬约束，但校验发生在整包解完之后；
/// - LZMA2 更进一步：folder 的声明值完全不约束逐块解码，恶意流的块头
///   可以让实际输出超出声明值上百倍（每块最多 2MB 输出 / ~16KB 输入）。
/// 一个几 MB 的压缩包就能把内存打爆，等 `open()` 自己抛 `wrongSize` 已经晚了。
///
/// 因此这里只读头部里的「结构 + 声明大小」，对每条数据流算出**解压输出的硬上限**：
/// - copy：输出 = 压缩大小；
/// - LZMA：解码器在声明值处硬停，输出 ≤ 声明值；
/// - LZMA2：逐块走查块头，输出 = 各块声明之和（精确值）。
/// 全部流的上限之和超过总量上限就拒绝；签名头有效但结构读不懂、或出现了
/// 无法界定内存上限的编码器（deflate/加密/多级链），同样在解压前拒绝 ——
/// 不能出现「本解析器看不懂、SWCompression 却照解」的分叉。
///
/// encoded header（0x17，压缩的 NextHeader）本身就是第一个要解压的东西，
/// 它的压缩流与解压结果都限制在极小的常量内，解出后再对主体流套同一套门槛。
enum SevenZipPrecheck {
    struct Limits {
        /// 全部数据流解压输出上限之和。
        var maximumTotalUncompressed: Int
        /// encoded header（压缩的 NextHeader）允许的压缩流大小。
        var maximumEncodedPackedSize: Int
        /// encoded header 解压结果的大小上限。
        var maximumEncodedUnpackedSize: Int
        /// NextHeader 本身的大小上限（plain header 不解压，但解析也要有界）。
        var maximumNextHeaderSize: Int

        static func comic(maximumTotalUncompressed: Int) -> Limits {
            Limits(
                maximumTotalUncompressed: maximumTotalUncompressed,
                maximumEncodedPackedSize: 1_024 * 1_024,
                maximumEncodedUnpackedSize: 32 * 1_024 * 1_024,
                maximumNextHeaderSize: 16 * 1_024 * 1_024
            )
        }
    }

    enum Outcome: Equatable {
        /// 解析成功且所有门槛通过 —— 之后解压的内存峰值有界。
        case validated
        /// 超出门槛，或签名头有效但结构无法界定 —— 在解压开始前按资源过大拒绝。
        case rejected
        /// 不是 7z（或版本/布局不符）—— 交给 `open()` 抛出准确的错误。
        case unsupported
    }

    static func check(_ data: Data, limits: Limits) -> Outcome {
        // **签名头**（32 字节）：magic 6 + 版本 2 + StartHeaderCRC 4
        // + NextHeaderOffset 8 + NextHeaderSize 8 + NextHeaderCRC 4。
        guard data.count >= 32 else { return .unsupported }
        let magic: [UInt8] = [0x37, 0x7A, 0xBC, 0xAF, 0x27, 0x1C]
        guard Array(data[data.startIndex ..< data.startIndex + 6]) == magic else { return .unsupported }
        // 与 SWCompression 的版本检查保持一致，避免「预检放行、open 报错」的分叉。
        guard data[data.startIndex + 6] == 0, data[data.startIndex + 7] == 4 else { return .unsupported }

        guard let rawOffset = leUInt64(data, at: 12), let rawSize = leUInt64(data, at: 20),
              rawOffset <= UInt64(Int.max), rawSize <= UInt64(Int.max) else { return .unsupported }
        let offset = Int(rawOffset)
        let size = Int(rawSize)
        // 空容器：没有 NextHeader，open() 会返回空列表。
        guard size > 0 else { return .validated }
        guard size <= limits.maximumNextHeaderSize else { return .rejected }
        let headerStart = 32 + offset
        guard headerStart >= 32, headerStart <= data.count, size <= data.count - headerStart else {
            return .unsupported
        }

        let header = data.subdata(in: (data.startIndex + headerStart) ..< (data.startIndex + headerStart + size))
        var cursor = ByteCursor(header)
        switch cursor.byte() {
        case 0x01:
            // plain header：头部本身不解压，直接解析主体流的声明值。
            return streamsOutcome(&cursor, container: data, limits: limits)
        case 0x17:
            // encoded header：先给「解出这份头」本身设门槛，解出后再解析主体流。
            return encodedHeaderOutcome(&cursor, container: data, limits: limits)
        default:
            return .rejected
        }
    }

    // MARK: - 签名头字段

    private static func leUInt64(_ data: Data, at offset: Int) -> UInt64? {
        guard offset >= 0, offset + 8 <= data.count else { return nil }
        var value: UInt64 = 0
        for i in 0..<8 {
            value |= UInt64(data[data.startIndex + offset + i]) << (8 * UInt64(i))
        }
        return value
    }

    // MARK: - NextHeader：plain / encoded

    /// 光标位于 plain header 类型字节之后（0x02 ArchiveProperties / 0x04 MainStreamsInfo / 0x05 FilesInfo）。
    private static func streamsOutcome(
        _ cursor: inout ByteCursor, container: Data, limits: Limits
    ) -> Outcome {
        while true {
            switch cursor.peek() {
            case 0x02:
                cursor.byte()
                guard skipArchiveProperties(&cursor) else { return .rejected }
            case 0x04:
                cursor.byte()
                guard let streams = parseStreamsInfo(&cursor) else { return .rejected }
                return gate(streams, container: container, limits: limits)
            case 0x05:
                // 只有空文件/目录（没有数据流）：无解压峰值可言。
                return .validated
            case 0x03:
                // additionalStreamsInfo：无法界定，拒绝；
                // open() 里同样会抛 additionalStreamsNotSupported。
                return .rejected
            default:
                // 头部被截断或属性无法识别：无法界定，拒绝。
                return .rejected
            }
        }
    }

    /// 光标位于 encoded header 的 StreamsInfo 处。解出头本身有严格的大小门槛，
    /// 解出后按 plain header 的规则继续把关主体流。
    private static func encodedHeaderOutcome(
        _ cursor: inout ByteCursor, container: Data, limits: Limits
    ) -> Outcome {
        guard let streams = parseStreamsInfo(&cursor), streams.count == 1 else { return .rejected }
        let folder = streams[0]
        guard folder.packedSize <= limits.maximumEncodedPackedSize,
              folder.declaredOut <= limits.maximumEncodedUnpackedSize else { return .rejected }

        let packed = container.subdata(
            in: (container.startIndex + folder.packedOffset) ..< (container.startIndex + folder.packedOffset + folder.packedSize)
        )
        let decoded: Data
        switch folder.coderID {
        case [0x00]:
            decoded = packed
        case [0x21]:
            // 公开的 LZMA2 入口要求流首是字典大小字节。
            guard folder.properties.count == 1 else { return .rejected }
            var input = Data([folder.properties[0]])
            input.append(packed)
            do { decoded = try LZMA2.decompress(data: input) } catch { return .rejected }
        case [0x03, 0x01, 0x01]:
            // 公开的 LZMA 入口吃「LZMA alone」格式：合成 13 字节头。
            guard folder.properties.count == 5 else { return .rejected }
            var input = Data(folder.properties)
            var size = UInt64(folder.declaredOut)
            for _ in 0..<8 {
                input.append(UInt8(truncatingIfNeeded: size))
                size >>= 8
            }
            input.append(packed)
            do { decoded = try LZMA.decompress(data: input) } catch { return .rejected }
        default:
            return .rejected
        }
        guard decoded.count == folder.declaredOut else { return .rejected }

        var inner = ByteCursor(decoded)
        guard inner.byte() == 0x01 else { return .rejected }
        return streamsOutcome(&inner, container: container, limits: limits)
    }

    // MARK: - StreamsInfo（PackInfo + UnpackInfo）

    struct ParsedFolder {
        /// 空 id 表示「结构读得懂但策略上无法界定」的多级/多流 folder，门槛直接拒绝。
        let coderID: [UInt8]
        let properties: [UInt8]
        /// 该流的压缩数据在容器内的绝对偏移（含 32 字节签名头）。
        let packedOffset: Int
        let packedSize: Int
        /// 声明的解压大小（单输出流）。
        let declaredOut: Int
    }

    /// 解析 `[0x06 PackInfo] 0x07 UnpackInfo`，在 SubStreamsInfo 之前停下
    /// （门槛只需要 folder 级别的声明值，子流划分与文件名无关紧要）。
    /// 返回 nil 表示结构怪异，本解析器无法界定，调用方一律拒绝。
    private static func parseStreamsInfo(_ cursor: inout ByteCursor) -> [ParsedFolder]? {
        var packPos = 0
        var packSizes: [Int] = []
        if cursor.peek() == 0x06 {
            cursor.byte()
            guard let pos = cursor.intNumber(), pos >= 0, pos <= Int.max - 32,
                  let numPack = cursor.intNumber(), numPack >= 0, numPack <= 65_536 else { return nil }
            packPos = pos
            packLoop: while true {
                switch cursor.peek() {
                case 0x09:
                    cursor.byte()
                    for _ in 0..<numPack {
                        guard let size = cursor.intNumber(), size >= 0 else { return nil }
                        packSizes.append(size)
                    }
                case 0x0A:
                    cursor.byte()
                    guard cursor.skipDefinedCRCs(count: numPack) else { return nil }
                case 0x00:
                    _ = cursor.byte()
                    guard packSizes.count == numPack else { return nil }
                    break packLoop
                default:
                    // 截断或无法识别的属性。
                    return nil
                }
            }
        }

        guard cursor.byte() == 0x07,
              cursor.byte() == 0x0B,
              let numFolders = cursor.intNumber(), numFolders >= 0, numFolders <= 4_096,
              cursor.byte() == 0 else { return nil }

        var rawFolders: [RawFolder] = []
        for _ in 0..<numFolders {
            guard let (next, folder) = parseFolder(cursor) else { return nil }
            cursor = next
            rawFolders.append(folder)
        }
        guard cursor.byte() == 0x0C else { return nil }

        var declared: [[Int]] = []
        for folder in rawFolders {
            var sizes: [Int] = []
            for _ in 0..<folder.totalOut {
                guard let size = cursor.intNumber(), size >= 0 else { return nil }
                sizes.append(size)
            }
            declared.append(sizes)
        }

        var folders: [ParsedFolder] = []
        var packIndex = 0
        var packedOffset = 32 + packPos
        for (index, folder) in rawFolders.enumerated() {
            guard packIndex + folder.numPacked <= packSizes.count else { return nil }
            let packedSize = packSizes[packIndex ..< (packIndex + folder.numPacked)].reduce(0, +)
            packIndex += folder.numPacked
            let offset = packedOffset
            packedOffset += packedSize

            let isSimple = folder.coders.count == 1
                && folder.totalIn == 1 && folder.totalOut == 1 && folder.numPacked == 1
            if isSimple, declared[index].count == 1 {
                folders.append(ParsedFolder(
                    coderID: folder.coders[0].id,
                    properties: folder.coders[0].properties,
                    packedOffset: offset,
                    packedSize: packedSize,
                    declaredOut: declared[index][0]
                ))
            } else {
                // 多级 coder（BCJ、加密等）：对漫画毫无意义，且内存上限无法界定。
                folders.append(ParsedFolder(
                    coderID: [], properties: [], packedOffset: offset, packedSize: packedSize, declaredOut: 0
                ))
            }
        }
        guard packIndex == packSizes.count else { return nil }
        return folders
    }

    private struct RawCoder {
        var id: [UInt8]
        var properties: [UInt8]
    }

    private struct RawFolder {
        var coders: [RawCoder]
        var totalIn: Int
        var totalOut: Int
        var numPacked: Int
    }

    private static func parseFolder(_ cursor: ByteCursor) -> (cursor: ByteCursor, value: RawFolder)? {
        var cursor = cursor
        guard let numCoders = cursor.intNumber(), numCoders >= 1, numCoders <= 16 else { return nil }
        var coders: [RawCoder] = []
        var totalIn = 0
        var totalOut = 0
        for _ in 0..<numCoders {
            guard let flags = cursor.byte(), flags & 0xC0 == 0 else { return nil }
            let idSize = Int(flags & 0x0F)
            guard idSize >= 1, let id = cursor.bytes(idSize) else { return nil }
            var numIn = 1
            var numOut = 1
            if flags & 0x10 != 0 {
                guard let valueIn = cursor.intNumber(), valueIn >= 1, valueIn <= 64,
                      let valueOut = cursor.intNumber(), valueOut >= 1, valueOut <= 64 else { return nil }
                numIn = valueIn
                numOut = valueOut
            }
            var properties = [UInt8]()
            if flags & 0x20 != 0 {
                guard let propsSize = cursor.intNumber(), propsSize >= 0, propsSize <= 1_024 * 1_024,
                      let props = cursor.bytes(propsSize) else { return nil }
                properties = [UInt8](props)
            }
            totalIn += numIn
            totalOut += numOut
            guard totalIn <= 64, totalOut <= 64 else { return nil }
            coders.append(RawCoder(id: [UInt8](id), properties: properties))
        }

        let numBindPairs = totalOut - 1
        if numBindPairs > 0 {
            for _ in 0..<numBindPairs {
                guard cursor.intNumber() != nil, cursor.intNumber() != nil else { return nil }
            }
        }
        guard totalIn >= numBindPairs else { return nil }
        let numPacked = totalIn - numBindPairs
        if numPacked != 1 {
            for _ in 0..<numPacked {
                guard cursor.intNumber() != nil else { return nil }
            }
        }
        return (cursor, RawFolder(
            coders: coders, totalIn: totalIn, totalOut: totalOut, numPacked: numPacked
        ))
    }

    // MARK: - 门槛

    private static func gate(
        _ folders: [ParsedFolder], container: Data, limits: Limits
    ) -> Outcome {
        guard !folders.isEmpty else { return .validated }
        var total = 0
        for folder in folders {
            var output = folder.declaredOut
            switch folder.coderID {
            case [0x00]:
                // copy：输出恰好等于压缩大小（声明不符交给 open() 报 wrongSize）。
                output = folder.packedSize
            case [0x03, 0x01, 0x01]:
                // LZMA：解码器在声明值处硬停，声明值即输出上限。
                break
            case [0x21]:
                // LZMA2：folder 声明值不约束逐块解码，必须按块头精确清点。
                guard let counted = lzma2OutputSize(
                    container, offset: folder.packedOffset, size: folder.packedSize
                ) else { return .rejected }
                output = counted
            default:
                // 多级链或 deflate/加密等编码器：内存上限无法界定，拒绝。
                // 漫画压缩包实际只使用 copy / LZMA / LZMA2。
                return .rejected
            }
            guard output >= 0 else { return .rejected }
            let (sum, overflow) = total.addingReportingOverflow(output)
            guard !overflow, sum <= limits.maximumTotalUncompressed else { return .rejected }
            total = sum
        }
        return .validated
    }

    /// 走查 LZMA2 块头（不碰块数据），返回整条流的精确解压输出。
    /// 布局与 SWCompression `LZMA2Decoder.dispatch` 一致。
    private static func lzma2OutputSize(_ container: Data, offset: Int, size: Int) -> Int? {
        var cursor = ByteCursor(container, index: offset)
        let end = offset + size
        var output = 0
        while true {
            guard cursor.index < end, let control = cursor.byte() else { return nil }
            switch control {
            case 0:
                return output
            case 1, 2:
                // 非压缩块：2 字节大小（+1），数据原样拷贝。
                guard let b0 = cursor.byte(), let b1 = cursor.byte() else { return nil }
                let dataSize = (Int(b0) << 8) + Int(b1) + 1
                guard cursor.index + dataSize <= end, add(&output, dataSize) else { return nil }
                cursor.index += dataSize
            case 0x80...0xFF:
                guard let b0 = cursor.byte(), let b1 = cursor.byte(),
                      let b2 = cursor.byte(), let b3 = cursor.byte() else { return nil }
                let unpackSize = ((Int(control) & 0x1F) << 16) + (Int(b0) << 8) + Int(b1) + 1
                let compressedSize = (Int(b2) << 8) + Int(b3) + 1
                if (control & 0x60) >> 5 >= 2 {
                    // 重置字典/状态时流里还要带 1 字节编码器属性。
                    guard cursor.byte() != nil else { return nil }
                }
                guard cursor.index + compressedSize <= end, add(&output, unpackSize) else { return nil }
                cursor.index += compressedSize
            default:
                return nil
            }
        }
    }

    private static func add(_ total: inout Int, _ value: Int) -> Bool {
        let (sum, overflow) = total.addingReportingOverflow(value)
        guard !overflow, sum >= 0 else { return false }
        total = sum
        return true
    }

    // MARK: - 次要结构

    private static func skipArchiveProperties(_ cursor: inout ByteCursor) -> Bool {
        while true {
            guard let type = cursor.byte() else { return false }
            if type == 0x00 { return true }
            guard let size = cursor.intNumber(), size >= 0, size <= 16 * 1_024 * 1_024,
                  cursor.bytes(size) != nil else { return false }
        }
    }
}

/// 只读字节游标：所有越界都以返回 nil 表示，绝不崩溃。
private struct ByteCursor {
    let data: Data
    var index: Int

    init(_ data: Data, index: Int = 0) {
        self.data = data
        self.index = index
    }

    mutating func byte() -> UInt8? {
        guard index >= 0, index < data.count else { return nil }
        let value = data[data.startIndex + index]
        index += 1
        return value
    }

    func peek() -> UInt8? {
        guard index >= 0, index < data.count else { return nil }
        return data[data.startIndex + index]
    }

    mutating func bytes(_ count: Int) -> Data? {
        guard count >= 0, index >= 0, index + count <= data.count else { return nil }
        let start = data.startIndex + index
        let value = data.subdata(in: start ..< start + count)
        index += count
        return value
    }

    /// 7z 的 Number 编码（real_u64）：首字节高位是长度标记，低位与后续
    /// 小端字节共同构成数值。0xFF 开头非法。
    mutating func number() -> UInt64? {
        guard let first = byte() else { return nil }
        var mask: UInt8 = 0x80
        var value: UInt64 = 0
        for i in 0..<8 {
            if first & mask == 0 {
                value = UInt64(first & (mask &- 1)) << (8 * UInt64(i))
                for j in 0..<i {
                    guard let b = byte() else { return nil }
                    value |= UInt64(b) << (8 * UInt64(j))
                }
                return value
            }
            mask >>= 1
        }
        return nil
    }

    mutating func intNumber() -> Int? {
        guard let value = number(), value <= UInt64(Int.max) else { return nil }
        return Int(value)
    }

    /// 跳过 0x0A（CRC）属性：AllAreDefined 字节 + 位向量 + 已定义项的 CRC32
    ///（与 SWCompression `defBits` 的布局一致）。只需精确推进游标。
    mutating func skipDefinedCRCs(count: Int) -> Bool {
        guard let allDefined = byte() else { return false }
        var definedCount = 0
        if allDefined != 0 {
            definedCount = count
        } else {
            guard let vector = bytes((count + 7) / 8) else { return false }
            for i in 0..<count {
                let byteValue = vector[vector.startIndex + i / 8]
                if (byteValue >> (7 - UInt8(i % 8))) & 1 == 1 { definedCount += 1 }
            }
        }
        return bytes(4 * definedCount) != nil
    }
}
