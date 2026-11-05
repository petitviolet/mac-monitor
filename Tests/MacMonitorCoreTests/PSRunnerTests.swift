import Darwin
import XCTest
@testable import MacMonitorCore

final class PSRunnerTests: XCTestCase {
    private let shortTimeout: TimeInterval = 0.3
    /// 期限がなければ30秒かかるコマンドで試すので、これより短ければ期限が働いたと判定できる。
    private let returnedEarlyLimit: TimeInterval = 10

    private func timedCapture(_ path: String, _ arguments: [String]) -> (Data?, TimeInterval) {
        let start = Date()
        let data = PSRunner.capture(executablePath: path, arguments: arguments, timeout: shortTimeout)
        return (data, Date().timeIntervalSince(start))
    }

    func testReturnsOutputOfCommandThatFinishes() {
        let data = PSRunner.capture(executablePath: "/bin/echo", arguments: ["hello"], timeout: 5)
        XCTAssertEqual(data.map { String(decoding: $0, as: UTF8.self) }, "hello\n")
    }

    func testReadsOutputLargerThanThePipeBuffer() {
        let data = PSRunner.capture(executablePath: "/bin/sh", arguments: ["-c", "yes | head -c 300000"], timeout: 5)
        XCTAssertEqual(data?.count, 300_000)
    }

    func testNonZeroExitGivesNil() {
        XCTAssertNil(PSRunner.capture(executablePath: "/usr/bin/false", arguments: [], timeout: 5))
    }

    func testMissingExecutableGivesNil() {
        XCTAssertNil(PSRunner.capture(executablePath: "/no/such/command", arguments: [], timeout: 5))
    }

    func testCommandThatNeverWritesHitsTheDeadlineAndIsTerminated() throws {
        let pidFile = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let (data, elapsed) = timedCapture("/bin/sh", ["-c", "echo $$ > '\(pidFile.path)'; exec /bin/sleep 30"])

        XCTAssertNil(data)
        XCTAssertLessThan(elapsed, returnedEarlyLimit)

        let pidText = try String(contentsOf: pidFile, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)
        let pid = try XCTUnwrap(pid_t(pidText))
        // シグナル0は生存確認だけで、何も送らない。相手はこのテストが起動したプロセス。
        var alive = true
        for _ in 0..<100 where alive {
            alive = kill(pid, 0) == 0
            if alive { Thread.sleep(forTimeInterval: 0.02) }
        }
        XCTAssertFalse(alive)
    }

    func testCommandThatClosesStdoutButKeepsRunningHitsTheDeadline() {
        let (data, elapsed) = timedCapture("/bin/sh", ["-c", "exec 1>&-; exec /bin/sleep 30"])
        XCTAssertNil(data)
        XCTAssertLessThan(elapsed, returnedEarlyLimit)
    }
}
