import XCTest
@testable import MacMonitorCore

final class CPUUsageTests: XCTestCase {
    private func ticks(user: UInt32 = 0, system: UInt32 = 0, idle: UInt32 = 0, nice: UInt32 = 0) -> CPUTicks {
        CPUTicks(user: user, system: system, idle: idle, nice: nice)
    }

    func testComputesPerCoreAndOverallFromDifference() throws {
        let previous = [ticks(user: 10, idle: 10), ticks(system: 5, idle: 5)]
        let current = [ticks(user: 40, idle: 40), ticks(system: 5, idle: 95)]

        let usage = try XCTUnwrap(CPUUsage.between(previous: previous, current: current))

        XCTAssertEqual(usage.perCore[0], 0.5, accuracy: 0.0001)
        XCTAssertEqual(usage.perCore[1], 0, accuracy: 0.0001)
        XCTAssertEqual(usage.overall, 30.0 / 150.0, accuracy: 0.0001)
    }

    func testNiceCountsAsBusy() throws {
        let usage = try XCTUnwrap(CPUUsage.between(previous: [ticks()], current: [ticks(idle: 1, nice: 3)]))
        XCTAssertEqual(usage.overall, 0.75, accuracy: 0.0001)
    }

    func testNoTickDifferenceGivesZeroWithoutDividingByZero() throws {
        let sample = [ticks(user: 5, idle: 5)]
        let usage = try XCTUnwrap(CPUUsage.between(previous: sample, current: sample))
        XCTAssertEqual(usage.overall, 0)
        XCTAssertEqual(usage.perCore, [0])
    }

    func testCounterWraparoundUsesModularDifference() throws {
        let previous = [ticks(user: UInt32.max, idle: 0)]
        let current = [ticks(user: 0, idle: 1)]
        let usage = try XCTUnwrap(CPUUsage.between(previous: previous, current: current))
        XCTAssertEqual(usage.overall, 0.5, accuracy: 0.0001)
    }

    func testCoreCountChangeGivesNil() {
        XCTAssertNil(CPUUsage.between(previous: [ticks()], current: [ticks(), ticks()]))
        XCTAssertNil(CPUUsage.between(previous: [], current: []))
    }
}
