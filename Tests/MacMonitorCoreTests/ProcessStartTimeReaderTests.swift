import Darwin
import XCTest
@testable import MacMonitorCore

final class ProcessStartTimeReaderTests: XCTestCase {
    private let stride = MemoryLayout<kinfo_proc>.stride

    private func process(pid: pid_t, seconds: Int) -> kinfo_proc {
        var info = kinfo_proc()
        info.kp_proc.p_pid = pid
        info.kp_proc.p_un.__p_starttime.tv_sec = seconds
        return info
    }

    /// results[n]はn回目のデータ取得の戻り値。大きさの問い合わせは常にsizeCountを返す。
    private func call(sizeCount: Int, results: [Int32], processes: [kinfo_proc]) -> (ProcessStartTimeReader.ProcListCall, () -> Int) {
        var dataCalls = 0
        let stride = self.stride
        let fn: ProcessStartTimeReader.ProcListCall = { buffer, length in
            guard let buffer else {
                length = sizeCount * stride
                return 0
            }
            let result = results[min(dataCalls, results.count - 1)]
            dataCalls += 1
            guard result == 0 else { return result }
            for (index, info) in processes.enumerated() {
                buffer.storeBytes(of: info, toByteOffset: index * stride, as: kinfo_proc.self)
            }
            length = processes.count * stride
            return 0
        }
        return (fn, { dataCalls })
    }

    func testReadsStartTimes() {
        let (fn, _) = call(sizeCount: 2, results: [0], processes: [process(pid: 10, seconds: 5), process(pid: 11, seconds: 7)])
        XCTAssertEqual(ProcessStartTimeReader.readAll(call: fn), [
            10: ProcessStartTime(seconds: 5, microseconds: 0),
            11: ProcessStartTime(seconds: 7, microseconds: 0)
        ])
    }

    func testRetriesWhenTheListGrewBetweenTheCalls() {
        let (fn, dataCalls) = call(sizeCount: 1, results: [ENOMEM, 0], processes: [process(pid: 10, seconds: 5)])
        XCTAssertEqual(ProcessStartTimeReader.readAll(call: fn)?.count, 1)
        XCTAssertEqual(dataCalls(), 2)
    }

    func testGivesUpAfterRepeatedENOMEM() {
        let (fn, dataCalls) = call(sizeCount: 1, results: [ENOMEM], processes: [])
        XCTAssertNil(ProcessStartTimeReader.readAll(call: fn))
        XCTAssertEqual(dataCalls(), ProcessStartTimeReader.maximumAttempts)
    }

    func testOtherErrorsGiveNil() {
        let (fn, _) = call(sizeCount: 1, results: [EPERM], processes: [])
        XCTAssertNil(ProcessStartTimeReader.readAll(call: fn))
        let failingSize: ProcessStartTimeReader.ProcListCall = { _, _ in EINVAL }
        XCTAssertNil(ProcessStartTimeReader.readAll(call: failingSize))
    }
}
