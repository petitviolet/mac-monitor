import Foundation

public enum AppSortKey: Hashable, Sendable {
    case name
    case cpu
    case memory

    /// 最初に押したときの向き。名前は昇順、CPUとメモリは多い順にする。
    var startsAscending: Bool { self == .name }
}

public struct AppSortOrder: Hashable, Sendable {
    public let key: AppSortKey
    public let ascending: Bool

    public init(key: AppSortKey, ascending: Bool) {
        self.key = key
        self.ascending = ascending
    }

    public static let initial = AppSortOrder(key: .name, ascending: true)

    /// 同じ見出しを押したら向きを逆にし、別の見出しならその見出しの最初の向きにする。
    public func afterHeaderClick(_ clicked: AppSortKey) -> AppSortOrder {
        clicked == key
            ? AppSortOrder(key: key, ascending: !ascending)
            : AppSortOrder(key: clicked, ascending: clicked.startsAscending)
    }
}

public enum AppRanking {
    /// 同値のときは名前の昇順、それも同じならPIDの昇順で並べ、更新のたびに行が入れ替わらないようにする。
    /// 合算のないアプリはCPUとメモリを最も少ないものとして扱う。
    public static func sorted<Item>(
        _ items: [Item],
        by order: AppSortOrder,
        pid: (Item) -> pid_t,
        name: (Item) -> String,
        aggregate: (Item) -> ProcessAggregate?
    ) -> [Item] {
        items.sorted { lhs, rhs in
            let primary = compare(lhs, rhs, key: order.key, name: name, aggregate: aggregate)
            if primary != .orderedSame {
                return order.ascending ? primary == .orderedAscending : primary == .orderedDescending
            }
            let byName = name(lhs).localizedStandardCompare(name(rhs))
            if order.key != .name, byName != .orderedSame {
                return byName == .orderedAscending
            }
            return pid(lhs) < pid(rhs)
        }
    }

    private static func compare<Item>(
        _ lhs: Item,
        _ rhs: Item,
        key: AppSortKey,
        name: (Item) -> String,
        aggregate: (Item) -> ProcessAggregate?
    ) -> ComparisonResult {
        switch key {
        case .name:
            return name(lhs).localizedStandardCompare(name(rhs))
        case .cpu:
            return compareValues(aggregate(lhs).map(\.cpuPercent), aggregate(rhs).map(\.cpuPercent))
        case .memory:
            return compareValues(aggregate(lhs).map(\.rssKB), aggregate(rhs).map(\.rssKB))
        }
    }

    private static func compareValues<Value: Comparable>(_ lhs: Value?, _ rhs: Value?) -> ComparisonResult {
        switch (lhs, rhs) {
        case let (left?, right?):
            return left < right ? .orderedAscending : (left > right ? .orderedDescending : .orderedSame)
        case (nil, nil):
            return .orderedSame
        case (nil, _):
            return .orderedAscending
        case (_, nil):
            return .orderedDescending
        }
    }
}
