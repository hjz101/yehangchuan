import Foundation

/// 书源地址的解析与私网判定。
///
/// 原来的实现直接 `hasPrefix("127.")` 等，很容易被绕过：
/// `https://user@127.0.0.1:8080/x`、`2130706433`、`0177.0.0.1`、
/// `[::1]`、`::ffff:127.0.0.1` 都不是那种朴素前缀能识别的。
/// 这里统一先归一化成纯主机串，再逐条判断。
enum URLHost {
    /// 取出便于展示与去重的主机串：去掉 scheme、用户信息、端口与路径，
    /// 去掉 IPv6 的方括号，小写。空串表示解析不出主机。
    static func normalize(_ raw: String) -> String {
        var value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return "" }

        // 去掉 scheme（含 //）
        if let range = value.range(of: "://") {
            value = String(value[range.upperBound...])
        }
        // 去掉路径、查询与片段
        if let end = value.firstIndex(where: { $0 == "/" || $0 == "?" || $0 == "#" }) {
            value = String(value[..<end])
        }
        // 去掉 userinfo
        if let at = value.lastIndex(of: "@") {
            value = String(value[value.index(after: at)...])
        }
        // 去掉端口：IPv6 的冒号都在方括号里，所以先判方括号
        if value.hasPrefix("[") {
            if let close = value.firstIndex(of: "]") {
                value = String(value[value.index(after: value.startIndex)..<close])
            }
        } else if let colon = value.lastIndex(of: ":"), value.filter({ $0 == ":" }).count == 1 {
            value = String(value[..<colon])
        }

        // 去掉首尾的点和空白（FQDN 结尾常带一个点）
        value = value.trimmingCharacters(in: CharacterSet(charactersIn: "."))
        return value.lowercased()
    }

    /// 是否为本机 / 局域网 / 链路本地等「默认不该访问」的地址。
    static func isPrivate(_ raw: String) -> Bool {
        let host = normalize(raw)
        guard !host.isEmpty else { return true }

        if host == "localhost" || host.hasSuffix(".localhost") { return true }
        if host.hasSuffix(".local") || host.hasSuffix(".internal") { return true }

        // IPv6
        if host.contains(":") {
            return isPrivateIPv6(host)
        }

        // IPv4（含十进制 / 八进制 / 十六进制写法）
        if let octets = ipv4Octets(host) {
            return isPrivateIPv4(octets)
        }

        // 单标签主机名（不含点且不是合法 IP）通常是内网机器名
        if !host.contains(".") { return true }

        return false
    }

    // MARK: - IPv4

    /// 把各种 IPv4 写法解析成四段 0...255。
    /// 支持 `127.0.0.1`、`2130706433`、`0x7f000001`、`0177.0.0.1`、`127.1` 等。
    private static func ipv4Octets(_ host: String) -> [UInt32]? {
        let parts = host.split(separator: ".", omittingEmptySubsequences: false)
        guard (1...4).contains(parts.count) else { return nil }

        var numbers: [UInt32] = []
        for part in parts {
            guard !part.isEmpty else { return nil }
            guard let parsed = parseIPv4Part(String(part)) else { return nil }
            numbers.append(parsed)
        }

        switch numbers.count {
        case 4:
            guard numbers.allSatisfy({ $0 < 256 }) else { return nil }
            return numbers
        case 3:
            // a.b.c  -> a.b.(c 占低 16 位)
            guard numbers[0] < 256, numbers[1] < 256, numbers[2] < 65_536 else { return nil }
            return [numbers[0], numbers[1], numbers[2] >> 8, numbers[2] & 0xFF]
        case 2:
            // a.b -> a.(b 占低 24 位)
            guard numbers[0] < 256, numbers[1] < 16_777_216 else { return nil }
            return [numbers[0], numbers[1] >> 16, (numbers[1] >> 8) & 0xFF, numbers[1] & 0xFF]
        case 1:
            // UInt32 解析成功即已在合法范围内，无需再判上限
            let value = numbers[0]
            return [value >> 24, (value >> 16) & 0xFF, (value >> 8) & 0xFF, value & 0xFF]
        default:
            return nil
        }
    }

    private static func parseIPv4Part(_ text: String) -> UInt32? {
        if text.lowercased().hasPrefix("0x") {
            return UInt32(text.dropFirst(2), radix: 16)
        }
        if text.count > 1, text.hasPrefix("0") {
            return UInt32(text.dropFirst(), radix: 8)
        }
        return UInt32(text, radix: 10)
    }

    private static func isPrivateIPv4(_ octets: [UInt32]) -> Bool {
        let a = octets[0], b = octets[1]
        if a == 0 { return true }                       // 0.0.0.0/8
        if a == 127 { return true }                     // 回环
        if a == 10 { return true }                      // A 类私网
        if a == 192, b == 168 { return true }           // C 类私网
        if a == 172, (16...31).contains(b) { return true }   // B 类私网
        if a == 169, b == 254 { return true }           // 链路本地
        if a == 100, (64...127).contains(b) { return true }  // 运营商级 NAT
        if a >= 224 { return true }                     // 组播 / 保留
        return false
    }

    // MARK: - IPv6

    private static func isPrivateIPv6(_ host: String) -> Bool {
        let value = host.split(separator: "%").first.map(String.init) ?? host  // 去掉 scope id

        if value == "::1" || value == "::" { return true }

        // IPv4 映射/兼容写法
        if let mapped = ipv4MappedOctets(value) {
            return isPrivateIPv4(mapped)
        }

        guard let firstGroup = value.split(separator: ":").first(where: { !$0.isEmpty }) else {
            return true    // 形如 :: 的写法已在上方处理，其余解析不了的一律拒绝
        }
        guard let prefix = UInt32(firstGroup, radix: 16) else { return true }

        if prefix & 0xFE00 == 0xFC00 { return true }    // fc00::/7 唯一本地地址
        if prefix & 0xFFC0 == 0xFE80 { return true }    // fe80::/10 链路本地
        if prefix & 0xFF00 == 0xFF00 { return true }    // ff00::/8 组播
        return false
    }

    private static func ipv4MappedOctets(_ value: String) -> [UInt32]? {
        // ::ffff:127.0.0.1 或 ::ffff:7f00:1
        let lower = value.lowercased()
        guard lower.hasPrefix("::ffff:") else { return nil }
        let tail = String(lower.dropFirst("::ffff:".count))

        if tail.contains(".") {
            return ipv4Octets(tail)
        }
        let groups = tail.split(separator: ":")
        guard groups.count == 2,
              let high = UInt32(groups[0], radix: 16),
              let low = UInt32(groups[1], radix: 16),
              high < 65_536, low < 65_536 else { return nil }
        return [high >> 8, high & 0xFF, low >> 8, low & 0xFF]
    }
}
