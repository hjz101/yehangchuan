import XCTest
@testable import LegadoCore

/// 7z 解压炸弹防护的预检解析器测试。
/// 手工按 7z 规范拼头部字节，验证各类结构下的判定结果。
final class SevenZipPrecheckTests: XCTestCase {
    private let oneGB = 1_073_741_824

    // MARK: 字节构造

    /// 7z Number 编码（real_u64）。
    private func numberBytes(_ v: Int) -> [UInt8] {
        precondition(v >= 0)
        var value = UInt64(v)
        if value < 0x80 { return [UInt8(truncatingIfNeeded: value)] }
        var extra = 1
        while value >> (8 * UInt64(extra)) >= (UInt64(1) << UInt64(8 - extra)) { extra += 1 }
        precondition(extra <= 8, "测试不需要这么大的数")
        var first = UInt8(0)
        for _ in 0..<extra { first = (first >> 1) | 0x80 }
        first |= UInt8(truncatingIfNeeded: value >> (8 * UInt64(extra)))
        var bytes = [first]
        var low = value
        for _ in 0..<extra {
            bytes.append(UInt8(truncatingIfNeeded: low))
            low >>= 8
        }
        return bytes
    }

    private func le64(_ v: UInt64) -> [UInt8] {
        (0..<8).map { UInt8(truncatingIfNeeded: v >> (8 * UInt64($0))) }
    }

    /// 签名头（32 字节）+ NextHeader + 可选的流数据。
    /// NextHeader 紧跟签名头（offset = 0）；packPos 由调用方给出
    ///（一般 = NextHeader 的长度，即流数据在签名头之后的偏移）。
    private func makeContainer(nextHeader: [UInt8], packed: [UInt8] = [], packPos: Int? = nil) -> Data {
        var data: [UInt8] = [0x37, 0x7A, 0xBC, 0xAF, 0x27, 0x1C, 0x00, 0x04]
        data.append(contentsOf: [0, 0, 0, 0])                       // StartHeaderCRC（预检不校验）
        data.append(contentsOf: le64(0))                            // NextHeaderOffset
        data.append(contentsOf: le64(UInt64(nextHeader.count)))
        data.append(contentsOf: [0, 0, 0, 0])                       // NextHeaderCRC（预检不校验）
        data.append(contentsOf: nextHeader)
        data.append(contentsOf: packed)
        return Data(data)
    }

    /// plain header：0x01 + MainStreamsInfo（单 coder folder × numFolders）。
    /// packPos 自动取头部总长（packed 数据紧跟在头部后面）。
    private func streamsHeader(
        packSize: Int, coderFlags: UInt8, coderID: [UInt8],
        props: [UInt8] = [], unpackSize: Int, numFolders: Int = 1
    ) -> [UInt8] {
        func build(_ packPos: Int) -> [UInt8] {
            var b: [UInt8] = [0x01, 0x04]
            b += [0x06] + numberBytes(packPos) + numberBytes(numFolders) + [0x09]
            for _ in 0..<numFolders { b += numberBytes(packSize) }
            b += [0x00]
            b += [0x07, 0x0B] + numberBytes(numFolders) + [0x00]
            for _ in 0..<numFolders {
                b += numberBytes(1) + [coderFlags] + coderID
                if coderFlags & 0x20 != 0 { b += numberBytes(props.count) + props }
            }
            b += [0x0C]
            for _ in 0..<numFolders { b += numberBytes(unpackSize) }
            b += [0x00]
            return b
        }
        var packPos = 0
        for _ in 0..<3 { packPos = build(packPos).count }
        return build(packPos)
    }

    /// LZMA2 块流（数据内容无所谓，预检只走查块头）。
    private func lzma2Stream(chunks: [(unpacked: Int, compressed: Int)]) -> [UInt8] {
        var b: [UInt8] = []
        for chunk in chunks {
            let unpackMinus1 = chunk.unpacked - 1
            let compMinus1 = chunk.compressed - 1
            b += [UInt8(0x80 | ((unpackMinus1 >> 16) & 0x1F)),
                  UInt8((unpackMinus1 >> 8) & 0xFF), UInt8(unpackMinus1 & 0xFF),
                  UInt8((compMinus1 >> 8) & 0xFF), UInt8(compMinus1 & 0xFF)]
            b += [UInt8](repeating: 0, count: chunk.compressed)
        }
        b.append(0x00)
        return b
    }

    // MARK: 真实文件

    func testFixtureValidatedAndArchiveStillOpens() throws {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "comic", withExtension: "7z", subdirectory: "Fixtures"))
        let data = try Data(contentsOf: url)
        XCTAssertEqual(
            SevenZipPrecheck.check(data, limits: .comic(maximumTotalUncompressed: oneGB)),
            .validated
        )
        XCTAssertNoThrow(try ComicArchiveSet(url: url))
    }

    // MARK: plain header

    func testRejectsPlainHeaderLZMABomb() {
        // 声明 8GB 的 LZMA folder：LZMA 解码器会在声明值处硬停，
        // 所以必须在解压前按声明值拒绝。
        let header = streamsHeader(
            packSize: 1024, coderFlags: 0x23, coderID: [0x03, 0x01, 0x01],
            props: [0x00, 0x00, 0x80, 0x00, 0x00], unpackSize: 8_589_934_592
        )
        XCTAssertEqual(
            SevenZipPrecheck.check(makeContainer(nextHeader: header), limits: .comic(maximumTotalUncompressed: oneGB)),
            .rejected
        )
    }

    func testPlainHeaderWithinLimitValidated() {
        let header = streamsHeader(
            packSize: 1024, coderFlags: 0x23, coderID: [0x03, 0x01, 0x01],
            props: [0x00, 0x00, 0x80, 0x00, 0x00], unpackSize: 2048
        )
        XCTAssertEqual(
            SevenZipPrecheck.check(makeContainer(nextHeader: header), limits: .comic(maximumTotalUncompressed: oneGB)),
            .validated
        )
    }

    func testCopyFolderBoundedByPackedSize() {
        // copy：输出 = 压缩大小；声明值再大也按真实压缩量算。
        let header = streamsHeader(
            packSize: 512, coderFlags: 0x01, coderID: [0x00], unpackSize: 1_000_000_000
        )
        XCTAssertEqual(
            SevenZipPrecheck.check(makeContainer(nextHeader: header), limits: .comic(maximumTotalUncompressed: oneGB)),
            .validated
        )
    }

    // MARK: LZMA2 块走查

    func testLZMA2WithinDeclaredLimitValidated() {
        // 两块各 1MB 输出，总量 2MB，远低于上限。
        let packed = lzma2Stream(chunks: [(1_048_576, 16), (1_048_576, 16)])
        let header = streamsHeader(
            packSize: packed.count, coderFlags: 0x21, coderID: [0x21],
            props: [0x18], unpackSize: 2 * 1_048_576
        )
        XCTAssertEqual(
            SevenZipPrecheck.check(makeContainer(nextHeader: header, packed: packed), limits: .comic(maximumTotalUncompressed: oneGB)),
            .validated
        )
    }

    func testLZMA2ChunkInflationBeyondLimitRejected() {
        // folder 声明 2MB（合法），但块头实际累加到 12MB：
        // LZMA2 不受 folder 声明值约束，必须按块头清点后拒绝。
        let chunks = Array(repeating: (unpacked: 2 * 1_048_576, compressed: 11), count: 6)
        let packed = lzma2Stream(chunks: chunks)
        let header = streamsHeader(
            packSize: packed.count, coderFlags: 0x21, coderID: [0x21],
            props: [0x18], unpackSize: 2 * 1_048_576
        )
        XCTAssertEqual(
            SevenZipPrecheck.check(
                makeContainer(nextHeader: header, packed: packed),
                limits: .comic(maximumTotalUncompressed: 10_000_000)
            ),
            .rejected
        )
    }

    func testLZMA2WithoutEndMarkerRejected() {
        var packed = lzma2Stream(chunks: [(0x1000, 16)])
        packed.removeLast() // 去掉结束标记
        let header = streamsHeader(
            packSize: packed.count, coderFlags: 0x21, coderID: [0x21],
            props: [0x18], unpackSize: 0x1000
        )
        XCTAssertEqual(
            SevenZipPrecheck.check(makeContainer(nextHeader: header, packed: packed), limits: .comic(maximumTotalUncompressed: oneGB)),
            .rejected
        )
    }

    // MARK: encoded header（0x17）

    /// encoded header（0x17）：单个 copy coder，压缩数据 = inner（紧跟头部之后）。
    /// packPos 定点迭代到与头部实际长度一致。
    private func encodedHeader(inner: [UInt8]) -> [UInt8] {
        func build(_ packPos: Int) -> [UInt8] {
            var b: [UInt8] = [0x17]
            b += [0x06] + numberBytes(packPos) + numberBytes(1) + [0x09] + numberBytes(inner.count) + [0x00]
            b += [0x07, 0x0B] + numberBytes(1) + [0x00]
            b += numberBytes(1) + [0x01, 0x00]          // 单 coder，copy
            b += [0x0C] + numberBytes(inner.count)
            b += [0x00]
            return b
        }
        var packPos = 0
        for _ in 0..<3 { packPos = build(packPos).count }
        return build(packPos)
    }

    func testEncodedHeaderDecodeThenGate() {
        // 解出的头声明合法大小：放行。
        let inner = streamsHeader(
            packSize: 1024, coderFlags: 0x23, coderID: [0x03, 0x01, 0x01],
            props: [0x00, 0x00, 0x80, 0x00, 0x00], unpackSize: 2048
        )
        let container = makeContainer(nextHeader: encodedHeader(inner: inner), packed: inner)
        XCTAssertEqual(
            SevenZipPrecheck.check(container, limits: .comic(maximumTotalUncompressed: oneGB)),
            .validated
        )
    }

    func testEncodedHeaderInnerBombRejected() {
        // 解出的头才是炸弹：仍要在解压主体前拒绝。
        let inner = streamsHeader(
            packSize: 1024, coderFlags: 0x23, coderID: [0x03, 0x01, 0x01],
            props: [0x00, 0x00, 0x80, 0x00, 0x00], unpackSize: 8_589_934_592
        )
        let container = makeContainer(nextHeader: encodedHeader(inner: inner), packed: inner)
        XCTAssertEqual(
            SevenZipPrecheck.check(container, limits: .comic(maximumTotalUncompressed: oneGB)),
            .rejected
        )
    }

    func testEncodedHeaderOversizedStreamRejected() {
        // 头部压缩流本身超过 1MB 门槛：直接拒绝。
        let inner = [UInt8](repeating: 0x41, count: 2 * 1_024 * 1_024)
        let container = makeContainer(nextHeader: encodedHeader(inner: inner), packed: inner)
        XCTAssertEqual(
            SevenZipPrecheck.check(container, limits: .comic(maximumTotalUncompressed: oneGB)),
            .rejected
        )
    }

    // MARK: 结构与边界

    func testEmptyNextHeaderIsValidated() {
        var data: [UInt8] = [0x37, 0x7A, 0xBC, 0xAF, 0x27, 0x1C, 0x00, 0x04]
        data.append(contentsOf: [0, 0, 0, 0])
        data.append(contentsOf: le64(0))
        data.append(contentsOf: le64(0))
        data.append(contentsOf: [0, 0, 0, 0])
        XCTAssertEqual(
            SevenZipPrecheck.check(Data(data), limits: .comic(maximumTotalUncompressed: oneGB)),
            .validated
        )
    }

    func testOversizedNextHeaderRejected() {
        var header: [UInt8] = [0x01, 0x04, 0x06]
        header += numberBytes(0) + numberBytes(1) + [0x09] + numberBytes(1) + [0x00]
        header.append(0x99) // 之后是垃圾，但 NextHeader 声明成 17MB
        var data: [UInt8] = [0x37, 0x7A, 0xBC, 0xAF, 0x27, 0x1C, 0x00, 0x04]
        data.append(contentsOf: [0, 0, 0, 0])
        data.append(contentsOf: le64(0))
        data.append(contentsOf: le64(17 * 1_024 * 1_024))
        data.append(contentsOf: [0, 0, 0, 0])
        data.append(contentsOf: header)
        XCTAssertEqual(
            SevenZipPrecheck.check(Data(data), limits: .comic(maximumTotalUncompressed: oneGB)),
            .rejected
        )
    }

    func testMultiCoderFolderRejected() {
        // BCJ + LZMA 之类的多级链：内存上限无法界定，直接拒绝。
        var b: [UInt8] = [0x01, 0x04]
        b += [0x06] + numberBytes(0) + numberBytes(1) + [0x09] + numberBytes(2048) + [0x00]
        b += [0x07, 0x0B] + numberBytes(1) + [0x00]
        b += numberBytes(2)                          // numCoders = 2
        b += [0x01, 0x04]                            // BCJ x86（单流）
        b += [0x23, 0x03, 0x01, 0x01] + numberBytes(5) + [UInt8](repeating: 0, count: 5)
        b += [0x00, 0x00]                            // 1 组 bind pair
        b += [0x0C] + numberBytes(1024) + numberBytes(1024)
        b += [0x00]
        XCTAssertEqual(
            SevenZipPrecheck.check(makeContainer(nextHeader: b), limits: .comic(maximumTotalUncompressed: oneGB)),
            .rejected
        )
    }

    func testGarbageIsUnsupported() {
        XCTAssertEqual(
            SevenZipPrecheck.check(Data([0x01, 0x02, 0x03]), limits: .comic(maximumTotalUncompressed: oneGB)),
            .unsupported
        )
        XCTAssertEqual(
            SevenZipPrecheck.check(Data("这不是一个 7z 文件".utf8), limits: .comic(maximumTotalUncompressed: oneGB)),
            .unsupported
        )
    }

    func testTruncatedNextHeaderFallsBackToOpen() {
        // NextHeader 声明 64 字节但文件里只有 4 字节：字节真的不存在，
        // SWCompression 同样读不到，不存在「它解我读不懂」的分叉 —— 交回 open() 报错。
        var data: [UInt8] = [0x37, 0x7A, 0xBC, 0xAF, 0x27, 0x1C, 0x00, 0x04]
        data.append(contentsOf: [0, 0, 0, 0])
        data.append(contentsOf: le64(0))
        data.append(contentsOf: le64(64))
        data.append(contentsOf: [0, 0, 0, 0])
        data.append(contentsOf: [0x01, 0x04, 0x06, 0x00])
        XCTAssertEqual(
            SevenZipPrecheck.check(Data(data), limits: .comic(maximumTotalUncompressed: oneGB)),
            .unsupported
        )
    }
}
