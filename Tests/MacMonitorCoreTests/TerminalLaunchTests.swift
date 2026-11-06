import XCTest
@testable import MacMonitorCore

final class TerminalLaunchTests: XCTestCase {
    private func entry(_ pid: pid_t, parent: pid_t, name: String, tty: String? = nil) -> ProcessEntry {
        ProcessEntry(pid: pid, ppid: parent, cpuPercent: 0, rssKB: 0, user: "u", name: name, tty: tty)
    }

    func testProcessWithTTYIsLaunchedFromTerminal() {
        let entries = [entry(1, parent: 0, name: "launchd"), entry(10, parent: 1, name: "yarn", tty: "ttys001")]
        XCTAssertEqual(TerminalLaunch.pids(in: entries), [10])
    }

    func testDescendantOfShellWithoutTTYIsLaunchedFromTerminal() {
        let entries = [
            entry(1, parent: 0, name: "launchd"),
            entry(10, parent: 1, name: "-zsh"),
            entry(11, parent: 10, name: "node"),
            entry(12, parent: 11, name: "esbuild")
        ]
        XCTAssertEqual(TerminalLaunch.pids(in: entries), [11, 12])
    }

    func testEachSupportedShellCountsAndLoginDashIsIgnored() {
        for shell in ["zsh", "-zsh", "bash", "-bash", "fish", "tcsh", "ksh", "nu"] {
            let entries = [entry(10, parent: 1, name: shell), entry(11, parent: 10, name: "child")]
            XCTAssertEqual(TerminalLaunch.pids(in: entries), [11], shell)
        }
    }

    func testPlainShAndOtherNamesDoNotCount() {
        for name in ["sh", "-sh", "zshrc", "nushell", "-", "bash2"] {
            let entries = [entry(10, parent: 1, name: name), entry(11, parent: 10, name: "child")]
            XCTAssertEqual(TerminalLaunch.pids(in: entries), [], name)
        }
    }

    func testOrphanReparentedToLaunchdIsNotDetected() {
        let entries = [entry(1, parent: 0, name: "launchd"), entry(20, parent: 1, name: "yarn")]
        XCTAssertEqual(TerminalLaunch.pids(in: entries), [])
    }

    func testWalkStopsAtPIDOneEvenIfItLooksLikeAShell() {
        let entries = [entry(1, parent: 0, name: "zsh"), entry(20, parent: 1, name: "daemon")]
        XCTAssertEqual(TerminalLaunch.pids(in: entries), [])
    }

    func testCycleWithoutShellTerminates() {
        let entries = [entry(10, parent: 12, name: "a"), entry(11, parent: 10, name: "b"), entry(12, parent: 11, name: "c")]
        XCTAssertEqual(TerminalLaunch.pids(in: entries), [])
    }

    func testCycleThroughShellCountsAndTerminates() {
        // 10は循環で自分自身に戻るだけなので、自分はシェルの祖先に数えない。
        let entries = [entry(10, parent: 11, name: "zsh"), entry(11, parent: 10, name: "child")]
        XCTAssertEqual(TerminalLaunch.pids(in: entries), [11])
    }

    func testMissingParentStopsTheWalk() {
        XCTAssertEqual(TerminalLaunch.pids(in: [entry(30, parent: 999, name: "x")]), [])
    }

    func testOnlyTTYsStartingWithTtysCount() {
        for tty in ["console", "tty", "ttyp0", "s001", ""] {
            XCTAssertEqual(TerminalLaunch.pids(in: [entry(10, parent: 1, name: "x", tty: tty)]), [], tty)
        }
        for tty in ["ttys001", "ttys1000"] {
            XCTAssertEqual(TerminalLaunch.pids(in: [entry(10, parent: 1, name: "x", tty: tty)]), [10], tty)
        }
    }
}
