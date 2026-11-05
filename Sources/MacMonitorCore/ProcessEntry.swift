import Darwin

public struct ProcessEntry: Equatable, Identifiable, Sendable {
    public let pid: pid_t
    public let ppid: pid_t
    public let cpuPercent: Double
    public let rssKB: UInt64
    public let user: String
    public let name: String

    public var id: pid_t { pid }
    public var rssBytes: UInt64 { bytes(fromKilobytes: rssKB) }

    public init(pid: pid_t, ppid: pid_t, cpuPercent: Double, rssKB: UInt64, user: String, name: String) {
        self.pid = pid
        self.ppid = ppid
        self.cpuPercent = cpuPercent
        self.rssKB = rssKB
        self.user = user
        self.name = name
    }
}

/// psのrssの単位はKB。
func bytes(fromKilobytes kilobytes: UInt64) -> UInt64 {
    kilobytes * 1024
}
