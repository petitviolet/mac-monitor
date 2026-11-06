import XCTest
@testable import MacMonitorCore

final class LaunchPWDCacheTests: XCTestCase {
    private final class Reader {
        var startTimes: [pid_t: ProcessStartTime]? = [:]
        var pwds: [pid_t: String] = [:]
        var reads: [pid_t] = []
    }

    private func time(_ seconds: Int) -> ProcessStartTime {
        ProcessStartTime(seconds: seconds, microseconds: 0)
    }

    private func cache(_ reader: Reader) -> LaunchPWDCache {
        LaunchPWDCache(
            readStartTimes: { reader.startTimes },
            readPWD: { pid in
                reader.reads.append(pid)
                return reader.pwds[pid]
            }
        )
    }

    func testReadsEachProcessOnlyOnce() {
        let reader = Reader()
        reader.startTimes = [10: time(1), 11: time(2)]
        reader.pwds = [10: "/a"]
        let subject = cache(reader)

        XCTAssertEqual(subject.refresh(pids: [10, 11]), LaunchPWDRefresh(pwds: [10: "/a"], changed: true))
        XCTAssertEqual(subject.refresh(pids: [10, 11]), LaunchPWDRefresh(pwds: [10: "/a"], changed: false))
        // 11は読めなかったが、読めなかったことも覚えて読み直さない。
        XCTAssertEqual(reader.reads.sorted(), [10, 11])
    }

    func testReusedPIDWithNewStartTimeIsReadAgain() {
        let reader = Reader()
        reader.startTimes = [10: time(1)]
        reader.pwds = [10: "/old"]
        let subject = cache(reader)
        _ = subject.refresh(pids: [10])

        reader.startTimes = [10: time(99)]
        reader.pwds = [10: "/new"]
        XCTAssertEqual(subject.refresh(pids: [10]), LaunchPWDRefresh(pwds: [10: "/new"], changed: true))
        XCTAssertEqual(reader.reads, [10, 10])
    }

    func testVanishedProcessesAreDropped() {
        let reader = Reader()
        reader.startTimes = [10: time(1), 11: time(1)]
        reader.pwds = [10: "/a", 11: "/b"]
        let subject = cache(reader)
        _ = subject.refresh(pids: [10, 11])

        reader.startTimes = [10: time(1)]
        XCTAssertEqual(subject.refresh(pids: [10]), LaunchPWDRefresh(pwds: [10: "/a"], changed: true))
        XCTAssertEqual(subject.cachedCount, 1)
    }

    func testProcessLeavingThePIDListIsDroppedEvenIfItStillHasAStartTime() {
        let reader = Reader()
        reader.startTimes = [10: time(1), 11: time(1)]
        reader.pwds = [10: "/a", 11: "/b"]
        let subject = cache(reader)
        _ = subject.refresh(pids: [10, 11])

        XCTAssertEqual(subject.refresh(pids: [10]), LaunchPWDRefresh(pwds: [10: "/a"], changed: true))
        XCTAssertEqual(subject.cachedCount, 1)
    }

    func testProcessWithoutStartTimeIsSkipped() {
        let reader = Reader()
        reader.pwds = [10: "/a"]
        XCTAssertEqual(cache(reader).refresh(pids: [10]), LaunchPWDRefresh(pwds: [:], changed: false))
        XCTAssertEqual(reader.reads, [])
    }

    func testFailedStartTimeReadKeepsThePreviousResultAndCache() {
        let reader = Reader()
        reader.startTimes = [10: time(1)]
        reader.pwds = [10: "/a"]
        let subject = cache(reader)
        _ = subject.refresh(pids: [10])

        reader.startTimes = nil
        XCTAssertEqual(subject.refresh(pids: [10, 11]), LaunchPWDRefresh(pwds: [10: "/a"], changed: false))
        XCTAssertEqual(subject.cachedCount, 1)

        reader.startTimes = [10: time(1)]
        _ = subject.refresh(pids: [10])
        XCTAssertEqual(reader.reads, [10])
    }
}
