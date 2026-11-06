import Darwin

/// プロセス一覧の並び順。どちらも多い順で、上位30件の選び方そのものになる。
public enum ProcessSortKey: Hashable, Sendable {
    case cpu
    case memory

    /// 見出しを押したときの並び順。少ない順の30件は役に立たないので、同じ見出しを押しても向きは変えない。
    /// clickedがnilなのは、並べ替えに使わない見出しを押したとき。
    public static func afterHeaderClick(_ clicked: ProcessSortKey?, current: ProcessSortKey) -> ProcessSortKey {
        clicked ?? current
    }
}

public enum ProcessRanking {
    /// includedPIDsとqueryの両方で絞ってから上位を取る。includedPIDsのnilと空のqueryは絞り込まないことを表す。
    /// queryは名前とlaunchPWDsの起動時のPWDに部分一致させる。
    public static func top(
        _ entries: [ProcessEntry],
        by key: ProcessSortKey,
        limit: Int,
        includedPIDs: Set<pid_t>? = nil,
        query: String = "",
        launchPWDs: [pid_t: String] = [:]
    ) -> [ProcessEntry] {
        let needle = ProcessSearch.normalized(query)
        let candidates = entries.filter { entry in
            if let includedPIDs, !includedPIDs.contains(entry.pid) { return false }
            guard let needle else { return true }
            return ProcessSearch.matches(name: entry.name, launchPWD: launchPWDs[entry.pid], needle: needle)
        }
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
