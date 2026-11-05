import XCTest
@testable import MacMonitorCore

final class SerialTickerTests: XCTestCase {
    func testRunsOffMainThreadWithoutOverlap() {
        let lock = NSLock()
        var running = 0
        var overlapped = false
        var ranOnMain = false
        var runs = 0
        let finished = expectation(description: "3 runs")
        finished.assertForOverFulfill = false

        let ticker = SerialTicker(interval: 0.01) {
            lock.lock()
            running += 1
            if running > 1 { overlapped = true }
            if Thread.isMainThread { ranOnMain = true }
            lock.unlock()

            Thread.sleep(forTimeInterval: 0.05)

            lock.lock()
            running -= 1
            runs += 1
            let done = runs >= 3
            lock.unlock()
            if done { finished.fulfill() }
        }
        ticker.start()
        wait(for: [finished], timeout: 5)
        ticker.stop()

        lock.lock()
        defer { lock.unlock() }
        XCTAssertFalse(overlapped)
        XCTAssertFalse(ranOnMain)
    }

    func testPerformRunsOnTheSameSerialQueue() {
        let done = expectation(description: "perform")
        let ticker = SerialTicker(interval: 60) {}
        ticker.perform {
            XCTAssertFalse(Thread.isMainThread)
            done.fulfill()
        }
        wait(for: [done], timeout: 5)
    }

    private final class StartTimes {
        private let lock = NSLock()
        private var values: [Date] = []

        func record() {
            lock.lock()
            values.append(Date())
            lock.unlock()
        }

        var gaps: [TimeInterval] {
            lock.lock()
            defer { lock.unlock() }
            return zip(values.dropFirst(), values).map { $0.timeIntervalSince($1) }
        }
    }

    private func gaps(interval: TimeInterval, workDuration: TimeInterval, runFor duration: TimeInterval, configure: (SerialTicker) -> Void) -> [TimeInterval] {
        let starts = StartTimes()
        let ticker = SerialTicker(interval: interval) {
            starts.record()
            Thread.sleep(forTimeInterval: workDuration)
        }
        configure(ticker)
        Thread.sleep(forTimeInterval: duration)
        ticker.stop()
        return starts.gaps
    }

    private func mean(_ values: [TimeInterval]) -> TimeInterval {
        values.reduce(0, +) / Double(values.count)
    }

    func testStartsAreSpacedByTheInterval() {
        let observed = gaps(interval: 0.1, workDuration: 0, runFor: 0.65) { $0.start() }
        XCTAssertGreaterThanOrEqual(observed.count, 2)
        // タイマーの許容幅の分だけ1回ごとの間隔は揺れるので、平均で確かめる。
        XCTAssertGreaterThanOrEqual(mean(observed), 0.09, "\(observed)")
    }

    func testLongWorkFinishesBeforeTheNextStarts() {
        let observed = gaps(interval: 0.05, workDuration: 0.2, runFor: 0.95) { $0.start() }
        XCTAssertGreaterThanOrEqual(observed.count, 2)
        XCTAssertTrue(observed.allSatisfy { $0 >= 0.19 }, "\(observed)")
    }

    func testRestartAndRepeatedStartKeepASingleChain() {
        let observed = gaps(interval: 0.1, workDuration: 0, runFor: 0.65) { ticker in
            ticker.start()
            ticker.stop()
            ticker.start()
            ticker.start()
        }
        XCTAssertGreaterThanOrEqual(observed.count, 4)
        // startを3回呼ぶので最初の2つの間隔は短い。3回目のstartの連鎖だけが残ることを、その後の間隔で確かめる。
        XCTAssertGreaterThanOrEqual(mean(Array(observed.dropFirst(2))), 0.09, "\(observed)")
    }

    func testStopEndsTheChain() {
        let starts = StartTimes()
        let ticker = SerialTicker(interval: 0.02) { starts.record() }
        ticker.start()
        Thread.sleep(forTimeInterval: 0.1)
        ticker.stop()
        Thread.sleep(forTimeInterval: 0.05)
        let countAfterStop = starts.gaps.count
        Thread.sleep(forTimeInterval: 0.1)
        XCTAssertEqual(starts.gaps.count, countAfterStop)
    }
}
