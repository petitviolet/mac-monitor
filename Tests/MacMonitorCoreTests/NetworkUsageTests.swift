import Darwin
import XCTest
@testable import MacMonitorCore

final class NetworkUsageTests: XCTestCase {
    private let upAndRunning = IFF_UP | IFF_RUNNING

    private func interfaceMessage(index: UInt16, name: String, flags: Int32, received: UInt64, sent: UInt64) -> [UInt8] {
        let nameBytes = Array(name.utf8)
        let addressHeaderSize = MemoryLayout<sockaddr_dl>.offset(of: \.sdl_data)!
        var message = if_msghdr2()
        message.ifm_msglen = UInt16(MemoryLayout<if_msghdr2>.size + addressHeaderSize + nameBytes.count)
        message.ifm_type = UInt8(RTM_IFINFO2)
        message.ifm_index = index
        message.ifm_flags = flags
        message.ifm_data.ifi_ibytes = received
        message.ifm_data.ifi_obytes = sent

        var address = [UInt8](repeating: 0, count: addressHeaderSize)
        address[MemoryLayout<sockaddr_dl>.offset(of: \.sdl_nlen)!] = UInt8(nameBytes.count)
        return withUnsafeBytes(of: &message) { Array($0) } + address + nameBytes
    }

    private func otherMessage(length: UInt16) -> [UInt8] {
        var bytes = [UInt8](repeating: 0xFF, count: Int(length))
        withUnsafeBytes(of: length) { bytes.replaceSubrange(0..<2, with: $0) }
        bytes[3] = UInt8(RTM_NEWADDR)
        return bytes
    }

    func testKeepsPerInterfaceCountersAndSkipsOtherMessages() {
        let bytes = interfaceMessage(index: 4, name: "en0", flags: upAndRunning, received: 100, sent: 10)
            + otherMessage(length: 20)
            + interfaceMessage(index: 7, name: "en5", flags: upAndRunning, received: 200, sent: 20)

        XCTAssertEqual(NetworkCounters.parseInterfaceList(bytes), [
            4: NetworkCounters(receivedBytes: 100, sentBytes: 10),
            7: NetworkCounters(receivedBytes: 200, sentBytes: 20)
        ])
    }

    func testSkipsLoopbackAndInterfacesThatAreNotUpAndRunning() {
        let bytes = interfaceMessage(index: 1, name: "lo0", flags: upAndRunning | IFF_LOOPBACK, received: 9, sent: 9)
            + interfaceMessage(index: 2, name: "en1", flags: IFF_UP, received: 9, sent: 9)
            + interfaceMessage(index: 3, name: "en2", flags: IFF_RUNNING, received: 9, sent: 9)
        XCTAssertEqual(NetworkCounters.parseInterfaceList(bytes), [:])
    }

    func testSkipsInterfacesThatCountTheSameTrafficTwice() {
        for name in ["utun0", "utun12", "awdl0", "llw0", "bridge100", "ipsec0", "gif0", "stf0", "ap1", "anpi0", "vmenet3"] {
            let bytes = interfaceMessage(index: 9, name: name, flags: upAndRunning, received: 9, sent: 9)
            XCTAssertEqual(NetworkCounters.parseInterfaceList(bytes), [:], name)
        }
    }

    func testPrefixOfExcludedNameIsNotEnoughToSkip() {
        XCTAssertTrue(NetworkInterfaceFilter.isCounted(flags: upAndRunning, name: "en0"))
        XCTAssertTrue(NetworkInterfaceFilter.isCounted(flags: upAndRunning, name: "apple0"))
        XCTAssertFalse(NetworkInterfaceFilter.isCounted(flags: upAndRunning, name: "ap1"))
    }

    func testStopsAtZeroLengthAndTruncatedMessages() {
        let valid = interfaceMessage(index: 4, name: "en0", flags: upAndRunning, received: 1, sent: 2)
        let expected = [UInt16(4): NetworkCounters(receivedBytes: 1, sentBytes: 2)]

        XCTAssertEqual(NetworkCounters.parseInterfaceList(valid + [0, 0, 0, 0]), expected)
        XCTAssertEqual(NetworkCounters.parseInterfaceList(valid + Array(valid.prefix(10))), expected)
        XCTAssertEqual(NetworkCounters.parseInterfaceList(valid + [1]), expected)
    }

    func testShortInfoMessageIsNotRead() {
        var short = interfaceMessage(index: 4, name: "en0", flags: upAndRunning, received: 5, sent: 5)
        short = Array(short.prefix(16))
        withUnsafeBytes(of: UInt16(16)) { short.replaceSubrange(0..<2, with: $0) }
        XCTAssertEqual(NetworkCounters.parseInterfaceList(short), [:])
    }

    func testNameLengthPastTheMessageEndDoesNotReadOutside() {
        var bytes = interfaceMessage(index: 4, name: "utun0", flags: upAndRunning, received: 5, sent: 5)
        let nameLengthOffset = MemoryLayout<if_msghdr2>.size + MemoryLayout<sockaddr_dl>.offset(of: \.sdl_nlen)!
        bytes[nameLengthOffset] = 200
        XCTAssertEqual(NetworkCounters.parseInterfaceList(bytes)[4], NetworkCounters(receivedBytes: 5, sentBytes: 5))
    }

    func testRateSumsPerInterfaceDifferencesOverElapsedTime() {
        let rate = NetworkRate.between(
            previous: [
                1: NetworkCounters(receivedBytes: 100, sentBytes: 50),
                2: NetworkCounters(receivedBytes: 10, sentBytes: 10)
            ],
            current: [
                1: NetworkCounters(receivedBytes: 300, sentBytes: 90),
                2: NetworkCounters(receivedBytes: 110, sentBytes: 10)
            ],
            elapsedSeconds: 2
        )
        XCTAssertEqual(rate, NetworkRate(receivedBytesPerSecond: 150, sentBytesPerSecond: 20))
    }

    func testNewInterfaceCountsAsZero() {
        let rate = NetworkRate.between(
            previous: [1: NetworkCounters(receivedBytes: 100, sentBytes: 100)],
            current: [
                1: NetworkCounters(receivedBytes: 200, sentBytes: 100),
                2: NetworkCounters(receivedBytes: 999_999, sentBytes: 999_999)
            ],
            elapsedSeconds: 1
        )
        XCTAssertEqual(rate, NetworkRate(receivedBytesPerSecond: 100, sentBytesPerSecond: 0))
    }

    func testRemovedInterfaceDoesNotReduceTheOthers() {
        let rate = NetworkRate.between(
            previous: [
                1: NetworkCounters(receivedBytes: 100, sentBytes: 100),
                2: NetworkCounters(receivedBytes: 999_999, sentBytes: 999_999)
            ],
            current: [1: NetworkCounters(receivedBytes: 200, sentBytes: 150)],
            elapsedSeconds: 1
        )
        XCTAssertEqual(rate, NetworkRate(receivedBytesPerSecond: 100, sentBytesPerSecond: 50))
    }

    func testCounterRewindGivesZeroForThatInterfaceAndDirectionOnly() {
        let rate = NetworkRate.between(
            previous: [
                1: NetworkCounters(receivedBytes: 300, sentBytes: 50),
                2: NetworkCounters(receivedBytes: 100, sentBytes: 100)
            ],
            current: [
                1: NetworkCounters(receivedBytes: 100, sentBytes: 90),
                2: NetworkCounters(receivedBytes: 110, sentBytes: 100)
            ],
            elapsedSeconds: 2
        )
        XCTAssertEqual(rate, NetworkRate(receivedBytesPerSecond: 5, sentBytesPerSecond: 20))
    }

    func testNonPositiveElapsedGivesZero() {
        let rate = NetworkRate.between(
            previous: [1: NetworkCounters(receivedBytes: 0, sentBytes: 0)],
            current: [1: NetworkCounters(receivedBytes: 100, sentBytes: 100)],
            elapsedSeconds: 0
        )
        XCTAssertEqual(rate, NetworkRate(receivedBytesPerSecond: 0, sentBytesPerSecond: 0))
    }
}
