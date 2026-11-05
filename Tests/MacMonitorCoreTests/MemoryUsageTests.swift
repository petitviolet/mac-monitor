import XCTest
@testable import MacMonitorCore

final class MemoryUsageTests: XCTestCase {
    func testBreakdownFromPageCounts() {
        let pages = VMPageCounts(internalPages: 30, purgeablePages: 10, wiredPages: 5, compressorPages: 15)

        let usage = MemoryUsage.make(pages: pages, pageSize: 100, totalBytes: 10_000)

        XCTAssertEqual(usage.appBytes, 2_000)
        XCTAssertEqual(usage.wiredBytes, 500)
        XCTAssertEqual(usage.compressedBytes, 1_500)
        XCTAssertEqual(usage.freeBytes, 6_000)
        XCTAssertEqual(usage.usedFraction, 0.4, accuracy: 0.0001)
    }

    func testPurgeableLargerThanInternalDoesNotUnderflow() {
        let pages = VMPageCounts(internalPages: 1, purgeablePages: 5, wiredPages: 0, compressorPages: 0)
        XCTAssertEqual(MemoryUsage.make(pages: pages, pageSize: 100, totalBytes: 1_000).appBytes, 0)
    }

    func testUsedLargerThanTotalClampsFreeToZero() {
        let pages = VMPageCounts(internalPages: 100, purgeablePages: 0, wiredPages: 0, compressorPages: 0)
        let usage = MemoryUsage.make(pages: pages, pageSize: 100, totalBytes: 1_000)
        XCTAssertEqual(usage.freeBytes, 0)
        XCTAssertEqual(usage.usedFraction, 1, accuracy: 0.0001)
    }

    func testZeroTotalGivesZeroFraction() {
        let pages = VMPageCounts(internalPages: 1, purgeablePages: 0, wiredPages: 0, compressorPages: 0)
        XCTAssertEqual(MemoryUsage.make(pages: pages, pageSize: 100, totalBytes: 0).usedFraction, 0)
    }
}
