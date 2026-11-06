import XCTest
@testable import MacMonitorCore

final class ProcessRankingTests: XCTestCase {
    private func entry(_ pid: Int32, cpu: Double = 0, rss: UInt64 = 0) -> ProcessEntry {
        ProcessEntry(pid: pid, ppid: 1, cpuPercent: cpu, rssKB: rss, user: "u", name: "p\(pid)")
    }

    func testSortsByCPUDescendingAndBreaksTiesByPID() {
        let entries = [entry(9, cpu: 1), entry(3, cpu: 5), entry(7, cpu: 5), entry(2, cpu: 0)]
        let top = ProcessRanking.top(entries, by: .cpu, limit: 30)
        XCTAssertEqual(top.map(\.pid), [3, 7, 9, 2])
    }

    func testSortsByMemoryDescendingAndBreaksTiesByPID() {
        let entries = [entry(9, rss: 10), entry(3, rss: 50), entry(7, rss: 50)]
        let top = ProcessRanking.top(entries, by: .memory, limit: 30)
        XCTAssertEqual(top.map(\.pid), [3, 7, 9])
    }

    func testLimitsTheNumberOfRows() {
        let entries = (1...40).map { entry(Int32($0), cpu: Double($0)) }
        let top = ProcessRanking.top(entries, by: .cpu, limit: 30)
        XCTAssertEqual(top.count, 30)
        XCTAssertEqual(top.first?.pid, 40)
    }

    func testFiltersBeforeTakingTheTopRows() {
        // 上位40件はCPUの高い順に1...40。絞り込みに入るのはCPUの低い3件だけ。
        let entries = (1...40).map { entry(Int32($0), cpu: Double($0)) }
        let top = ProcessRanking.top(entries, by: .cpu, limit: 30, includedPIDs: [1, 2, 3])
        XCTAssertEqual(top.map(\.pid), [3, 2, 1])
    }

    func testNilIncludedPIDsMeansNoFilter() {
        let entries = (1...40).map { entry(Int32($0), cpu: Double($0)) }
        XCTAssertEqual(ProcessRanking.top(entries, by: .cpu, limit: 30, includedPIDs: nil).count, 30)
    }
}
