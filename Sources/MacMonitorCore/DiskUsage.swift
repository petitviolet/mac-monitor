import Foundation

public struct DiskUsage: Equatable, Sendable {
    public let totalBytes: UInt64
    public let availableBytes: UInt64

    public init(totalBytes: UInt64, availableBytes: UInt64) {
        self.totalBytes = totalBytes
        self.availableBytes = availableBytes
    }

    public var usedBytes: UInt64 { totalBytes - min(availableBytes, totalBytes) }

    public var usedFraction: Double {
        totalBytes == 0 ? 0 : Double(usedBytes) / Double(totalBytes)
    }
}

enum DiskUsageReader {
    private static let rootVolume = URL(fileURLWithPath: "/")

    static func read() -> DiskUsage? {
        let keys: Set<URLResourceKey> = [.volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey]
        // URLはリソース値をキャッシュするので、毎回コピーを作ってキャッシュされた値を使わないようにする。
        var url = rootVolume
        url.removeAllCachedResourceValues()
        guard let values = try? url.resourceValues(forKeys: keys),
              let total = values.volumeTotalCapacity,
              let available = values.volumeAvailableCapacityForImportantUsage,
              total >= 0, available >= 0 else { return nil }
        return DiskUsage(totalBytes: UInt64(total), availableBytes: UInt64(available))
    }
}
