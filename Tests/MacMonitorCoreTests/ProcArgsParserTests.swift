import XCTest
@testable import MacMonitorCore

final class ProcArgsParserTests: XCTestCase {
    private func buffer(argc: Int32, _ body: String) -> [UInt8] {
        withUnsafeBytes(of: argc) { Array($0) } + Array(body.utf8)
    }

    func testParsesPathArgumentsAndDropsEnvironment() {
        let bytes = buffer(argc: 2, "/bin/sleep\0\0\0\0sleep\0300\0HOME=/Users/x\0SECRET=y\0")
        XCTAssertEqual(ProcArgsParser.parse(bytes), ProcArgs(executablePath: "/bin/sleep", arguments: ["sleep", "300"]))
    }

    func testBufferShorterThanArgcFieldGivesNil() {
        XCTAssertNil(ProcArgsParser.parse([]))
        XCTAssertNil(ProcArgsParser.parse([1, 0, 0]))
    }

    func testNegativeArgcGivesNil() {
        XCTAssertNil(ProcArgsParser.parse(buffer(argc: -1, "/bin/sleep\0")))
    }

    func testUnterminatedPathGivesNil() {
        XCTAssertNil(ProcArgsParser.parse(buffer(argc: 1, "/bin/sleep")))
    }

    func testArgcLargerThanBufferKeepsWhatExists() {
        let bytes = buffer(argc: 100, "/bin/sleep\0sleep\0300\0")
        XCTAssertEqual(ProcArgsParser.parse(bytes)?.arguments, ["sleep", "300"])
    }

    func testUnterminatedLastArgumentIsKept() {
        let bytes = buffer(argc: 2, "/bin/sleep\0sleep\0300")
        XCTAssertEqual(ProcArgsParser.parse(bytes)?.arguments, ["sleep", "300"])
    }

    func testZeroArgcGivesNoArguments() {
        let bytes = buffer(argc: 0, "/bin/sleep\0\0HOME=/x\0")
        XCTAssertEqual(ProcArgsParser.parse(bytes), ProcArgs(executablePath: "/bin/sleep", arguments: []))
    }
}
