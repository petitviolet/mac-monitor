import XCTest
@testable import MacMonitorCore

final class SortingTests: XCTestCase {
    // MARK: プロセス

    func testProcessHeaderClickSelectsTheKeyAndNeverFlipsTheOrder() {
        XCTAssertEqual(ProcessSortKey.afterHeaderClick(.memory, current: .cpu), .memory)
        XCTAssertEqual(ProcessSortKey.afterHeaderClick(.cpu, current: .memory), .cpu)
        // 同じ見出しをもう一度押しても、多い順のまま変わらない。
        XCTAssertEqual(ProcessSortKey.afterHeaderClick(.cpu, current: .cpu), .cpu)
        // 並べ替えに使わない見出しは無視する。
        XCTAssertEqual(ProcessSortKey.afterHeaderClick(nil, current: .memory), .memory)
    }

    // MARK: アプリ

    private struct App {
        let pid: pid_t
        let name: String
        let aggregate: ProcessAggregate?
    }

    private func app(_ pid: pid_t, _ name: String, cpu: Double? = nil, rss: UInt64? = nil) -> App {
        let aggregate = cpu.map { ProcessAggregate(cpuPercent: $0, rssKB: rss ?? 0, processCount: 1) }
            ?? rss.map { ProcessAggregate(cpuPercent: 0, rssKB: $0, processCount: 1) }
        return App(pid: pid, name: name, aggregate: aggregate)
    }

    private func sorted(_ apps: [App], _ order: AppSortOrder) -> [pid_t] {
        AppRanking.sorted(apps, by: order, pid: \.pid, name: \.name, aggregate: \.aggregate).map(\.pid)
    }

    func testInitialOrderIsNameAscending() {
        XCTAssertEqual(AppSortOrder.initial, AppSortOrder(key: .name, ascending: true))
        let apps = [app(1, "Zed"), app(2, "Finder"), app(3, "finder2"), app(4, "Claude")]
        XCTAssertEqual(sorted(apps, .initial), [4, 2, 3, 1])
    }

    func testFirstClickUsesTheDefaultDirectionAndSecondClickReverses() {
        let byName = AppSortOrder.initial
        let byCPU = byName.afterHeaderClick(.cpu)
        XCTAssertEqual(byCPU, AppSortOrder(key: .cpu, ascending: false))
        XCTAssertEqual(byCPU.afterHeaderClick(.cpu), AppSortOrder(key: .cpu, ascending: true))
        XCTAssertEqual(byCPU.afterHeaderClick(.memory), AppSortOrder(key: .memory, ascending: false))
        XCTAssertEqual(byCPU.afterHeaderClick(.name), AppSortOrder(key: .name, ascending: true))
        XCTAssertEqual(byName.afterHeaderClick(.name), AppSortOrder(key: .name, ascending: false))
    }

    func testCPUDescendingAndAscending() {
        let apps = [app(1, "A", cpu: 5), app(2, "B", cpu: 50), app(3, "C", cpu: 20)]
        XCTAssertEqual(sorted(apps, AppSortOrder(key: .cpu, ascending: false)), [2, 3, 1])
        XCTAssertEqual(sorted(apps, AppSortOrder(key: .cpu, ascending: true)), [1, 3, 2])
    }

    func testMemoryDescendingAndAscending() {
        let apps = [app(1, "A", rss: 300), app(2, "B", rss: 100), app(3, "C", rss: 200)]
        XCTAssertEqual(sorted(apps, AppSortOrder(key: .memory, ascending: false)), [1, 3, 2])
        XCTAssertEqual(sorted(apps, AppSortOrder(key: .memory, ascending: true)), [2, 3, 1])
    }

    func testTiesAreBrokenByNameThenPIDInBothDirections() {
        let apps = [app(9, "Pages", cpu: 1), app(3, "Pages", cpu: 1), app(5, "Keynote", cpu: 1), app(7, "Zed", cpu: 9)]
        XCTAssertEqual(sorted(apps, AppSortOrder(key: .cpu, ascending: false)), [7, 5, 3, 9])
        XCTAssertEqual(sorted(apps, AppSortOrder(key: .cpu, ascending: true)), [5, 3, 9, 7])
    }

    func testSameNameIsOrderedByPIDWhenSortingByName() {
        let apps = [app(9, "Pages"), app(3, "Pages")]
        XCTAssertEqual(sorted(apps, AppSortOrder(key: .name, ascending: true)), [3, 9])
        XCTAssertEqual(sorted(apps, AppSortOrder(key: .name, ascending: false)), [3, 9])
    }

    func testAppsWithoutAggregateGoLastWhenDescendingAndFirstWhenAscending() {
        let apps = [app(1, "A"), app(2, "B", cpu: 0.5)]
        XCTAssertEqual(sorted(apps, AppSortOrder(key: .cpu, ascending: false)), [2, 1])
        XCTAssertEqual(sorted(apps, AppSortOrder(key: .cpu, ascending: true)), [1, 2])
    }

    func testOrderIsStableAcrossRepeatedSorts() {
        let apps = (1...20).map { app(Int32($0), "Same", cpu: 1) }.shuffled()
        let first = sorted(apps, AppSortOrder(key: .cpu, ascending: false))
        XCTAssertEqual(first, Array(1...20).map { Int32($0) })
        XCTAssertEqual(sorted(apps.shuffled(), AppSortOrder(key: .cpu, ascending: false)), first)
    }
}
