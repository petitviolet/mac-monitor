import XCTest
@testable import MacMonitorCore

final class DiskUsageTests: XCTestCase {
    func testUsedIsTotalMinusAvailable() {
        let usage = DiskUsage(totalBytes: 1_000, availableBytes: 250)
        XCTAssertEqual(usage.usedBytes, 750)
        XCTAssertEqual(usage.usedFraction, 0.75, accuracy: 0.0001)
    }

    func testAvailableLargerThanTotalAndZeroTotalAreSafe() {
        XCTAssertEqual(DiskUsage(totalBytes: 100, availableBytes: 200).usedBytes, 0)
        XCTAssertEqual(DiskUsage(totalBytes: 0, availableBytes: 0).usedFraction, 0)
    }
}
