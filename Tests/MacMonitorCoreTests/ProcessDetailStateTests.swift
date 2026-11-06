import XCTest
@testable import MacMonitorCore

final class ProcessDetailStateTests: XCTestCase {
    private func detail(pid: pid_t) -> ProcessDetail {
        ProcessDetail(
            pid: pid, parentPID: 1, user: nil, path: nil, arguments: nil, launchEnvironment: nil, workingDirectory: nil,
            startTime: nil, threadCount: nil, cpuTimeSeconds: nil, footprintBytes: nil, rssBytes: nil
        )
    }

    func testSelectingNilGivesNoSelectionAndAPIDGivesLoading() {
        XCTAssertEqual(ProcessDetailState.selecting(nil), .noSelection)
        XCTAssertEqual(ProcessDetailState.selecting(5), .loading)
    }

    func testResultForCurrentSelectionIsApplied() {
        let result = ProcessDetailResult(pid: 5, detail: detail(pid: 5))
        XCTAssertEqual(ProcessDetailState.loading.applying(result, selectedPID: 5), .loaded(detail(pid: 5)))
    }

    func testResultWithoutDetailMeansExited() {
        let result = ProcessDetailResult(pid: 5, detail: nil)
        XCTAssertEqual(ProcessDetailState.loading.applying(result, selectedPID: 5), .exited)
    }

    func testResultOfPreviousSelectionIsDiscarded() {
        let stale = ProcessDetailResult(pid: 5, detail: detail(pid: 5))
        XCTAssertEqual(ProcessDetailState.loading.applying(stale, selectedPID: 6), .loading)
    }

    func testResultArrivingAfterDeselectionIsDiscarded() {
        let stale = ProcessDetailResult(pid: 5, detail: detail(pid: 5))
        XCTAssertEqual(ProcessDetailState.noSelection.applying(stale, selectedPID: nil), .noSelection)
    }
}
