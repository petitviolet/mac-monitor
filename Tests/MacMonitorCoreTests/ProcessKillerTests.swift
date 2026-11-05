import Darwin
import XCTest
@testable import MacMonitorCore

final class ProcessKillerTests: XCTestCase {
    private let start = ProcessStartTime(seconds: 1_000, microseconds: 5)

    private final class Recorder {
        var calls: [(pid_t, Int32)] = []
    }

    private func killer(
        ownPID: pid_t = 500,
        startTimes: [ProcessStartTime?],
        result: Int32 = 0,
        currentName: String? = nil,
        recorder: Recorder = Recorder()
    ) -> ProcessKiller {
        var remaining = startTimes
        return ProcessKiller(
            ownPID: ownPID,
            readStartTime: { _ in remaining.isEmpty ? nil : remaining.removeFirst() },
            readName: { _ in currentName },
            sendSignal: { pid, signal in
                recorder.calls.append((pid, signal))
                return result
            }
        )
    }

    func testRefusesProtectedPIDsWithoutTouchingAnything() {
        let recorder = Recorder()
        let subject = killer(startTimes: [start], recorder: recorder)
        for pid: pid_t in [-1, -500, 0, 1, 500] {
            XCTAssertEqual(subject.prepare(pid: pid, name: "x"), .failure(.protected), "pid \(pid)")
        }
        XCTAssertTrue(recorder.calls.isEmpty)
    }

    func testPrepareOnExitedProcessReportsAlreadyExited() {
        XCTAssertEqual(killer(startTimes: [nil]).prepare(pid: 42, name: "x"), .failure(.alreadyExited))
    }

    func testPrepareCapturesStartTime() throws {
        let ticket = try killer(startTimes: [start]).prepare(pid: 42, name: "x").get()
        XCTAssertEqual(ticket, KillTicket(pid: 42, name: "x", startTime: start))
    }

    func testSendsRequestedSignalWhenStartTimeMatches() {
        for (signal, raw) in [(KillSignal.terminate, SIGTERM), (.forceKill, SIGKILL)] {
            let recorder = Recorder()
            let ticket = KillTicket(pid: 42, name: "x", startTime: start)
            let outcome = killer(startTimes: [start], recorder: recorder).send(ticket, signal: signal)
            XCTAssertEqual(outcome, .sent)
            XCTAssertEqual(recorder.calls.count, 1)
            XCTAssertEqual(recorder.calls.first?.0, 42)
            XCTAssertEqual(recorder.calls.first?.1, raw)
        }
    }

    func testDifferentStartTimeIsTreatedAsReusedPIDAndNothingIsSent() {
        let recorder = Recorder()
        let ticket = KillTicket(pid: 42, name: "x", startTime: start)
        let later = ProcessStartTime(seconds: 1_000, microseconds: 6)
        let outcome = killer(startTimes: [later], recorder: recorder).send(ticket, signal: .forceKill)
        XCTAssertEqual(outcome, .pidReused)
        XCTAssertTrue(recorder.calls.isEmpty)
    }

    func testProcessGoneBeforeSendIsAlreadyExitedAndNothingIsSent() {
        let recorder = Recorder()
        let ticket = KillTicket(pid: 42, name: "x", startTime: start)
        let outcome = killer(startTimes: [nil], recorder: recorder).send(ticket, signal: .terminate)
        XCTAssertEqual(outcome, .alreadyExited)
        XCTAssertTrue(recorder.calls.isEmpty)
    }

    func testSendRefusesProtectedPIDEvenWithForgedTicket() {
        let recorder = Recorder()
        let subject = killer(startTimes: [start, start, start, start], recorder: recorder)
        for pid: pid_t in [-1, 0, 1, 500] {
            let ticket = KillTicket(pid: pid, name: "x", startTime: start)
            XCTAssertEqual(subject.send(ticket, signal: .forceKill), .protected)
        }
        XCTAssertTrue(recorder.calls.isEmpty)
    }

    func testErrnoIsMappedToOutcome() {
        let ticket = KillTicket(pid: 42, name: "x", startTime: start)
        XCTAssertEqual(killer(startTimes: [start], result: EPERM).send(ticket, signal: .terminate), .permissionDenied)
        XCTAssertEqual(killer(startTimes: [start], result: ESRCH).send(ticket, signal: .terminate), .alreadyExited)
        XCTAssertEqual(killer(startTimes: [start], result: EINVAL).send(ticket, signal: .terminate), .failed(errno: EINVAL))
    }

    func testPrepareShowsTheNameReadAtThatMoment() throws {
        let ticket = try killer(startTimes: [start], currentName: "x").prepare(pid: 42, name: "x").get()
        XCTAssertEqual(ticket.name, "x")
    }

    func testPrepareUsesListedNameWhenCurrentNameCannotBeRead() throws {
        let ticket = try killer(startTimes: [start], currentName: nil).prepare(pid: 42, name: "listed").get()
        XCTAssertEqual(ticket.name, "listed")
    }

    func testPrepareRefusesWhenNameDiffersFromList() {
        let result = killer(startTimes: [start], currentName: "other").prepare(pid: 42, name: "listed")
        XCTAssertEqual(result, .failure(.targetChanged(listed: "listed", current: "other")))
    }

    func testResolveNameIsPure() {
        XCTAssertEqual(KillTargetName.resolve(listed: "a", current: "a"), .confirmed("a"))
        XCTAssertEqual(KillTargetName.resolve(listed: "a", current: nil), .confirmed("a"))
        XCTAssertEqual(KillTargetName.resolve(listed: "a", current: ""), .confirmed("a"))
        XCTAssertEqual(KillTargetName.resolve(listed: "a", current: "b"), .changed(listed: "a", current: "b"))
    }

    func testOutcomesAreDistinguishable() {
        let outcomes: [KillOutcome] = [
            .sent, .protected, .pidReused, .permissionDenied, .alreadyExited,
            .failed(errno: EINVAL), .failed(errno: EIO),
            .targetChanged(listed: "a", current: "b"), .targetChanged(listed: "a", current: "c")
        ]
        for (leftIndex, left) in outcomes.enumerated() {
            for (rightIndex, right) in outcomes.enumerated() where leftIndex != rightIndex {
                XCTAssertNotEqual(left, right)
            }
        }
    }
}
