import Darwin

public struct ProcessAggregate: Equatable, Sendable {
    public let cpuPercent: Double
    public let rssKB: UInt64
    public let processCount: Int

    public var rssBytes: UInt64 { bytes(fromKilobytes: rssKB) }

    public init(cpuPercent: Double, rssKB: UInt64, processCount: Int) {
        self.cpuPercent = cpuPercent
        self.rssKB = rssKB
        self.processCount = processCount
    }
}

public enum ProcessTree {
    /// 親子の索引を1回だけ作り、複数の根についてまとめて合算する。一覧にない根は結果に入らない。
    /// psの結果は別々の瞬間の値が混ざるので、ppidが循環していても1プロセスを1回だけ数える。
    public static func aggregates(rootPIDs: [pid_t], entries: [ProcessEntry]) -> [pid_t: ProcessAggregate] {
        let byPID = Dictionary(entries.map { ($0.pid, $0) }, uniquingKeysWith: { first, _ in first })
        let childrenByParent = Dictionary(grouping: entries, by: \.ppid)

        var result: [pid_t: ProcessAggregate] = [:]
        for rootPID in rootPIDs where byPID[rootPID] != nil {
            var visited: Set<pid_t> = []
            var pending = [rootPID]
            var cpu = 0.0
            var rss: UInt64 = 0
            while let pid = pending.popLast() {
                guard visited.insert(pid).inserted, let entry = byPID[pid] else { continue }
                cpu += entry.cpuPercent
                rss += entry.rssKB
                pending += (childrenByParent[pid] ?? []).map(\.pid)
            }
            result[rootPID] = ProcessAggregate(cpuPercent: cpu, rssKB: rss, processCount: visited.count)
        }
        return result
    }
}
