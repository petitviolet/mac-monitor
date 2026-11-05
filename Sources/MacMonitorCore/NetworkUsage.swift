import Darwin

public struct NetworkCounters: Equatable, Sendable {
    public let receivedBytes: UInt64
    public let sentBytes: UInt64

    public init(receivedBytes: UInt64, sentBytes: UInt64) {
        self.receivedBytes = receivedBytes
        self.sentBytes = sentBytes
    }

    /// NET_RT_IFLIST2のバッファから、数える対象のインターフェースのカウンタをifm_indexごとに取り出す。
    public static func parseInterfaceList(_ bytes: [UInt8]) -> [UInt16: NetworkCounters] {
        let headerSize = MemoryLayout<if_msghdr>.offset(of: \.ifm_flags)!
        var counters: [UInt16: NetworkCounters] = [:]

        bytes.withUnsafeBytes { buffer in
            var offset = 0
            while offset + headerSize <= buffer.count {
                let length = Int(buffer.loadUnaligned(fromByteOffset: offset, as: UInt16.self))
                guard length > 0, offset + length <= buffer.count else { return }
                defer { offset += length }

                let type = buffer[offset + MemoryLayout<if_msghdr>.offset(of: \.ifm_type)!]
                guard Int32(type) == RTM_IFINFO2, length >= MemoryLayout<if_msghdr2>.size else { continue }

                let message = buffer.loadUnaligned(fromByteOffset: offset, as: if_msghdr2.self)
                let name = interfaceName(in: buffer, messageOffset: offset, messageLength: length)
                guard NetworkInterfaceFilter.isCounted(flags: message.ifm_flags, name: name) else { continue }
                counters[message.ifm_index] = NetworkCounters(
                    receivedBytes: message.ifm_data.ifi_ibytes,
                    sentBytes: message.ifm_data.ifi_obytes
                )
            }
        }
        return counters
    }

    /// if_msghdr2の直後に続くsockaddr_dlから名前を読む。読めないときは空文字を返す。
    private static func interfaceName(in buffer: UnsafeRawBufferPointer, messageOffset: Int, messageLength: Int) -> String {
        let addressOffset = messageOffset + MemoryLayout<if_msghdr2>.size
        let nameOffset = addressOffset + MemoryLayout<sockaddr_dl>.offset(of: \.sdl_data)!
        let messageEnd = messageOffset + messageLength
        guard nameOffset <= messageEnd else { return "" }

        let nameLength = Int(buffer[addressOffset + MemoryLayout<sockaddr_dl>.offset(of: \.sdl_nlen)!])
        guard nameOffset + nameLength <= messageEnd else { return "" }
        return String(decoding: buffer[nameOffset..<(nameOffset + nameLength)], as: UTF8.self)
    }
}

public enum NetworkInterfaceFilter {
    /// トンネル、ブリッジ、仮想NICの通信は物理インターフェースでも数えられるので、合計から除く。
    private static let excludedBaseNames: Set<String> = [
        "utun", "ipsec", "gif", "stf", "awdl", "llw", "bridge", "ap", "anpi", "vmenet", "vmnet", "pktap", "iptap", "XHC"
    ]

    public static func isCounted(flags: Int32, name: String) -> Bool {
        let required = IFF_UP | IFF_RUNNING
        guard flags & required == required, flags & IFF_LOOPBACK == 0 else { return false }
        let baseName = String(name.reversed().drop(while: \.isNumber).reversed())
        return !excludedBaseNames.contains(baseName)
    }
}

public struct NetworkRate: Equatable, Sendable {
    public let receivedBytesPerSecond: UInt64
    public let sentBytesPerSecond: UInt64

    public init(receivedBytesPerSecond: UInt64, sentBytesPerSecond: UInt64) {
        self.receivedBytesPerSecond = receivedBytesPerSecond
        self.sentBytesPerSecond = sentBytesPerSecond
    }

    /// インターフェースごとの差を足すので、増減したインターフェースの累計は速度に混ざらない。
    /// 新しく現れたインターフェースは差を取れないので0として扱う。
    public static func between(
        previous: [UInt16: NetworkCounters],
        current: [UInt16: NetworkCounters],
        elapsedSeconds: Double
    ) -> NetworkRate {
        guard elapsedSeconds > 0 else { return NetworkRate(receivedBytesPerSecond: 0, sentBytesPerSecond: 0) }

        var received: UInt64 = 0
        var sent: UInt64 = 0
        for (index, after) in current {
            guard let before = previous[index] else { continue }
            received += difference(from: before.receivedBytes, to: after.receivedBytes)
            sent += difference(from: before.sentBytes, to: after.sentBytes)
        }
        return NetworkRate(
            receivedBytesPerSecond: UInt64(Double(received) / elapsedSeconds),
            sentBytesPerSecond: UInt64(Double(sent) / elapsedSeconds)
        )
    }

    /// カウンタが巻き戻ったときは0とする。
    private static func difference(from before: UInt64, to after: UInt64) -> UInt64 {
        after >= before ? after - before : 0
    }
}

enum NetworkCountersReader {
    static func read() -> [UInt16: NetworkCounters]? {
        var mib: [Int32] = [CTL_NET, PF_ROUTE, 0, 0, NET_RT_IFLIST2, 0]
        var length = 0
        guard sysctl(&mib, UInt32(mib.count), nil, &length, nil, 0) == 0 else { return nil }

        var buffer = [UInt8](repeating: 0, count: length)
        guard sysctl(&mib, UInt32(mib.count), &buffer, &length, nil, 0) == 0 else { return nil }
        return NetworkCounters.parseInterfaceList(Array(buffer.prefix(length)))
    }
}
