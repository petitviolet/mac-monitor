import Darwin

public enum ProcessSortKey: Hashable, Sendable {
    case cpu
    case memory
}

public enum ProcessRanking {
    /// includedPIDsを渡すと、そこに含まれるものに絞ってから上位を取る。nilは絞り込まないことを表す。
    public static func top(
        _ entries: [ProcessEntry],
        by key: ProcessSortKey,
        limit: Int,
        includedPIDs: Set<pid_t>? = nil
    ) -> [ProcessEntry] {
        let candidates = includedPIDs.map { included in entries.filter { included.contains($0.pid) } } ?? entries
        let sorted = candidates.sorted { lhs, rhs in
            switch key {
            case .cpu where lhs.cpuPercent != rhs.cpuPercent:
                return lhs.cpuPercent > rhs.cpuPercent
            case .memory where lhs.rssKB != rhs.rssKB:
                return lhs.rssKB > rhs.rssKB
            default:
                return lhs.pid < rhs.pid
            }
        }
        return Array(sorted.prefix(limit))
    }
}
