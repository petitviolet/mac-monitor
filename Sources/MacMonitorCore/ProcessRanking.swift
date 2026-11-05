public enum ProcessSortKey: Hashable, Sendable {
    case cpu
    case memory
}

public enum ProcessRanking {
    public static func top(_ entries: [ProcessEntry], by key: ProcessSortKey, limit: Int) -> [ProcessEntry] {
        let sorted = entries.sorted { lhs, rhs in
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
