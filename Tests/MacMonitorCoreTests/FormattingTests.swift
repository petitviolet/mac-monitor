import XCTest
@testable import MacMonitorCore

final class FormattingTests: XCTestCase {
    func testBytesUseBinaryUnits() {
        XCTAssertEqual(Formatting.bytes(512), "512 B")
        XCTAssertEqual(Formatting.bytes(1_536), "1.5 KB")
        XCTAssertEqual(Formatting.bytes(1_073_741_824), "1.0 GB")
        XCTAssertEqual(Formatting.bytes(5_497_558_138_880), "5.0 TB")
    }

    func testRate() {
        XCTAssertEqual(Formatting.rate(2_048), "2.0 KB/s")
    }

    func testPercent() {
        XCTAssertEqual(Formatting.percent(fraction: 0.426), "43%")
        XCTAssertEqual(Formatting.percent(fraction: 0), "0%")
    }

    func testCPUPercentKeepsOneDecimal() {
        XCTAssertEqual(Formatting.cpuPercent(123.45), "123.5%")
    }

    func testMenuBarLabel() {
        XCTAssertEqual(Formatting.menuBarLabel(cpuFraction: 0.12, memoryFraction: 0.65), "CPU 12% MEM 65%")
        XCTAssertEqual(Formatting.menuBarLabel(cpuFraction: nil, memoryFraction: nil), "CPU -- MEM --")
    }

    func testCPUTime() {
        XCTAssertEqual(Formatting.cpuTime(seconds: 3_723.45), "1:02:03.45")
        XCTAssertEqual(Formatting.cpuTime(seconds: 5.5), "0:00:05.50")
    }

    func testCPUTimeCarriesWhenRoundingReachesTheNextMinuteOrHour() {
        XCTAssertEqual(Formatting.cpuTime(seconds: 59.999), "0:01:00.00")
        XCTAssertEqual(Formatting.cpuTime(seconds: 3599.999), "1:00:00.00")
    }
}
