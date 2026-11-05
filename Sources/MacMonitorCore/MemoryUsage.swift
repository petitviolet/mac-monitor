import Darwin

public struct VMPageCounts: Equatable, Sendable {
    public let internalPages: UInt64
    public let purgeablePages: UInt64
    public let wiredPages: UInt64
    public let compressorPages: UInt64

    public init(internalPages: UInt64, purgeablePages: UInt64, wiredPages: UInt64, compressorPages: UInt64) {
        self.internalPages = internalPages
        self.purgeablePages = purgeablePages
        self.wiredPages = wiredPages
        self.compressorPages = compressorPages
    }
}

public struct MemoryUsage: Equatable, Sendable {
    public let totalBytes: UInt64
    public let appBytes: UInt64
    public let wiredBytes: UInt64
    public let compressedBytes: UInt64
    /// 合計からアプリ、wired、圧縮を引いた残り。再利用できるファイルキャッシュもここに入る。
    public let freeBytes: UInt64

    public var usedFraction: Double {
        guard totalBytes > 0 else { return 0 }
        let used = appBytes + wiredBytes + compressedBytes
        return min(1, Double(used) / Double(totalBytes))
    }

    public static func make(pages: VMPageCounts, pageSize: UInt64, totalBytes: UInt64) -> MemoryUsage {
        let appPages = pages.internalPages - min(pages.purgeablePages, pages.internalPages)
        let app = appPages * pageSize
        let wired = pages.wiredPages * pageSize
        let compressed = pages.compressorPages * pageSize
        let used = app + wired + compressed
        return MemoryUsage(
            totalBytes: totalBytes,
            appBytes: app,
            wiredBytes: wired,
            compressedBytes: compressed,
            freeBytes: totalBytes - min(used, totalBytes)
        )
    }
}

enum MemoryUsageReader {
    private static let host = mach_host_self()

    static func read() -> MemoryUsage? {
        guard let total = readTotalBytes() else { return nil }

        var stats = vm_statistics64_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.stride / MemoryLayout<integer_t>.stride)
        let result = withUnsafeMutablePointer(to: &stats) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(host, HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }

        let pages = VMPageCounts(
            internalPages: UInt64(stats.internal_page_count),
            purgeablePages: UInt64(stats.purgeable_count),
            wiredPages: UInt64(stats.wire_count),
            compressorPages: UInt64(stats.compressor_page_count)
        )
        return MemoryUsage.make(pages: pages, pageSize: UInt64(vm_kernel_page_size), totalBytes: total)
    }

    private static func readTotalBytes() -> UInt64? {
        var total: UInt64 = 0
        var length = MemoryLayout<UInt64>.size
        guard sysctlbyname("hw.memsize", &total, &length, nil, 0) == 0 else { return nil }
        return total
    }
}
