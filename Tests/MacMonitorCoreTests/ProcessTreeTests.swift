import XCTest
@testable import MacMonitorCore

final class ProcessTreeTests: XCTestCase {
    private func entry(_ pid: Int32, parent: Int32, cpu: Double = 1, rss: UInt64 = 10) -> ProcessEntry {
        ProcessEntry(pid: pid, ppid: parent, cpuPercent: cpu, rssKB: rss, user: "u", name: "p\(pid)")
    }

    func testSumsRootAndAllDescendants() {
        let entries = [
            entry(10, parent: 1, cpu: 1, rss: 100),
            entry(11, parent: 10, cpu: 2, rss: 200),
            entry(12, parent: 11, cpu: 4, rss: 400),
            entry(20, parent: 1, cpu: 8, rss: 800)
        ]

        let aggregate = ProcessTree.aggregate(rootPID: 10, entries: entries)

        XCTAssertEqual(aggregate, ProcessAggregate(cpuPercent: 7, rssKB: 700, processCount: 3))
    }

    func testMissingRootGivesNil() {
        XCTAssertNil(ProcessTree.aggregate(rootPID: 99, entries: [entry(10, parent: 1)]))
    }

    func testCycleTerminatesAndCountsEachProcessOnce() {
        let entries = [entry(10, parent: 12), entry(11, parent: 10), entry(12, parent: 11)]
        let aggregate = ProcessTree.aggregate(rootPID: 10, entries: entries)
        XCTAssertEqual(aggregate?.processCount, 3)
        XCTAssertEqual(aggregate?.rssKB, 30)
    }

    func testSelfParentTerminates() {
        let aggregate = ProcessTree.aggregate(rootPID: 0, entries: [entry(0, parent: 0)])
        XCTAssertEqual(aggregate?.processCount, 1)
    }
}
