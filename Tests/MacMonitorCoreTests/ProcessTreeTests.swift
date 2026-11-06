import XCTest
@testable import MacMonitorCore

final class ProcessTreeTests: XCTestCase {
    private func entry(_ pid: Int32, parent: Int32, cpu: Double = 1, rss: UInt64 = 10) -> ProcessEntry {
        ProcessEntry(pid: pid, ppid: parent, cpuPercent: cpu, rssKB: rss, user: "u", name: "p\(pid)")
    }

    private func aggregate(_ root: pid_t, _ entries: [ProcessEntry]) -> ProcessAggregate? {
        ProcessTree.aggregates(rootPIDs: [root], entries: entries)[root]
    }

    func testSumsRootAndAllDescendants() {
        let entries = [
            entry(10, parent: 1, cpu: 1, rss: 100),
            entry(11, parent: 10, cpu: 2, rss: 200),
            entry(12, parent: 11, cpu: 4, rss: 400),
            entry(20, parent: 1, cpu: 8, rss: 800)
        ]

        let aggregate = aggregate(10, entries)

        XCTAssertEqual(aggregate, ProcessAggregate(cpuPercent: 7, rssKB: 700, processCount: 3))
    }

    func testMissingRootGivesNil() {
        XCTAssertNil(aggregate(99, [entry(10, parent: 1)]))
    }

    func testCycleTerminatesAndCountsEachProcessOnce() {
        let entries = [entry(10, parent: 12), entry(11, parent: 10), entry(12, parent: 11)]
        let aggregate = aggregate(10, entries)
        XCTAssertEqual(aggregate?.processCount, 3)
        XCTAssertEqual(aggregate?.rssKB, 30)
    }

    func testSelfParentTerminates() {
        let aggregate = aggregate(0, [entry(0, parent: 0)])
        XCTAssertEqual(aggregate?.processCount, 1)
    }

    func testBatchAggregatesMatchOneRootAtATime() {
        let entries = [
            entry(10, parent: 1, cpu: 1, rss: 100),
            entry(11, parent: 10, cpu: 2, rss: 200),
            entry(20, parent: 1, cpu: 8, rss: 800),
            entry(21, parent: 20, cpu: 4, rss: 400),
            entry(22, parent: 21, cpu: 16, rss: 1_600)
        ]
        let batch = ProcessTree.aggregates(rootPIDs: [10, 20, 99], entries: entries)
        XCTAssertEqual(batch[10], aggregate(10, entries))
        XCTAssertEqual(batch[20], aggregate(20, entries))
        XCTAssertNil(batch[99])
        XCTAssertEqual(batch.count, 2)
    }

    func testBatchAggregatesAreCycleSafe() {
        let entries = [entry(10, parent: 12), entry(11, parent: 10), entry(12, parent: 11)]
        XCTAssertEqual(ProcessTree.aggregates(rootPIDs: [10, 11], entries: entries)[11]?.processCount, 3)
    }
}
