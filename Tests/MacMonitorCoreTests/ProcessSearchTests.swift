import XCTest
@testable import MacMonitorCore

final class ProcessSearchTests: XCTestCase {
    private func entry(_ pid: pid_t, _ name: String, cpu: Double = 0) -> ProcessEntry {
        ProcessEntry(pid: pid, ppid: 1, cpuPercent: cpu, rssKB: 0, user: "u", name: name)
    }

    func testEmptyOrBlankQueryMatchesEverything() {
        XCTAssertFalse(ProcessSearch.isActive(""))
        XCTAssertFalse(ProcessSearch.isActive("  \n"))
        XCTAssertEqual(ProcessRanking.top([entry(1, "node")], by: .cpu, limit: 30, query: " \n").count, 1)
    }

    func testMatchesNameCaseInsensitivelyAndPartially() {
        XCTAssertTrue(ProcessSearch.matches(name: "MacMonitor", launchPWD: nil, needle: "monit"))
        XCTAssertTrue(ProcessSearch.matches(name: "node", launchPWD: nil, needle: "NODE"))
        XCTAssertFalse(ProcessSearch.matches(name: "node", launchPWD: nil, needle: "ruby"))
    }

    func testMatchesLaunchPWD() {
        XCTAssertTrue(ProcessSearch.matches(name: "node", launchPWD: "/Users/x/src/mac-monitor", needle: "Mac-Monitor"))
        XCTAssertFalse(ProcessSearch.matches(name: "node", launchPWD: "/Users/x/src/other", needle: "mac-monitor"))
    }

    func testSurroundingWhitespaceIsIgnored() {
        XCTAssertEqual(ProcessRanking.top([entry(1, "node")], by: .cpu, limit: 30, query: " node ").count, 1)
    }

    func testRankingFiltersByTerminalAndQueryBeforeTakingTheTopRows() {
        let entries = [
            entry(1, "node", cpu: 90),
            entry(2, "node", cpu: 80),
            entry(3, "ruby", cpu: 70),
            entry(4, "zsh", cpu: 60),
            entry(5, "node", cpu: 1)
        ]
        let top = ProcessRanking.top(
            entries,
            by: .cpu,
            limit: 2,
            includedPIDs: [2, 3, 4, 5],
            query: "node",
            launchPWDs: [4: "/work/node-app"]
        )
        // 端末で2,3,4,5に絞り、名前かPWDにnodeを含む2,4,5から上位2件を取る。
        XCTAssertEqual(top.map(\.pid), [2, 4])
    }

    func testEmptyQueryKeepsPreviousBehavior() {
        let entries = (1...40).map { entry(Int32($0), "p", cpu: Double($0)) }
        XCTAssertEqual(ProcessRanking.top(entries, by: .cpu, limit: 30, query: "").count, 30)
    }

    private let entries = [
        ProcessEntry(pid: 1, ppid: 0, cpuPercent: 50, rssKB: 0, user: "u", name: "日本語アプリ"),
        ProcessEntry(pid: 2, ppid: 0, cpuPercent: 40, rssKB: 0, user: "u", name: "node"),
        ProcessEntry(pid: 3, ppid: 0, cpuPercent: 30, rssKB: 0, user: "u", name: "ruby"),
        ProcessEntry(pid: 4, ppid: 0, cpuPercent: 20, rssKB: 0, user: "u", name: "node")
    ]

    func testLimitExactlyAndBelowTheMatchCount() {
        XCTAssertEqual(ProcessRanking.top(entries, by: .cpu, limit: 2, query: "node").map(\.pid), [2, 4])
        XCTAssertEqual(ProcessRanking.top(entries, by: .cpu, limit: 1, query: "node").map(\.pid), [2])
    }

    func testJapaneseNameAndQuery() {
        XCTAssertEqual(ProcessRanking.top(entries, by: .cpu, limit: 30, query: "日本語").map(\.pid), [1])
        XCTAssertEqual(
            ProcessRanking.top(entries, by: .cpu, limit: 30, query: "作業", launchPWDs: [3: "/Users/x/作業/app"]).map(\.pid),
            [3]
        )
    }

    func testEmptyIncludedPIDsGivesNothing() {
        XCTAssertEqual(ProcessRanking.top(entries, by: .cpu, limit: 30, includedPIDs: [], query: "node"), [])
    }

    func testPWDForPIDMissingFromEntriesIsIgnored() {
        XCTAssertEqual(ProcessRanking.top(entries, by: .cpu, limit: 30, query: "secret", launchPWDs: [99: "/secret"]), [])
    }

    func testNeitherNameNorPWDMatches() {
        XCTAssertEqual(ProcessRanking.top(entries, by: .cpu, limit: 30, query: "python", launchPWDs: [2: "/work"]), [])
    }

    func testPWDOnlyMatchAndOrderFollowsTheSortKey() {
        let pwds: [pid_t: String] = [3: "/work/mac-monitor", 1: "/work/mac-monitor"]
        XCTAssertEqual(ProcessRanking.top(entries, by: .cpu, limit: 30, query: "mac-monitor", launchPWDs: pwds).map(\.pid), [1, 3])
    }

    func testQueryIsNormalizedOnce() {
        XCTAssertEqual(ProcessSearch.normalized(" \n node \t"), "node")
        XCTAssertNil(ProcessSearch.normalized(" \n "))
    }
}
