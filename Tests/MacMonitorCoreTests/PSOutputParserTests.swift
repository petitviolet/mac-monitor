import XCTest
@testable import MacMonitorCore

final class PSOutputParserTests: XCTestCase {
    func testParsesColumnsAndKeepsSpacesInCommand() {
        let output = """
          123     1   4.5  20784 root             ??       logd
         4567   123  12.0   1024 petitviolet      ttys001  Google Chrome Helper (Renderer)
        """

        let entries = PSOutputParser.parse(output)

        XCTAssertEqual(entries, [
            ProcessEntry(pid: 123, ppid: 1, cpuPercent: 4.5, rssKB: 20784, user: "root", name: "logd", tty: nil),
            ProcessEntry(pid: 4567, ppid: 123, cpuPercent: 12.0, rssKB: 1024, user: "petitviolet", name: "Google Chrome Helper (Renderer)", tty: "ttys001")
        ])
    }

    func testSkipsMalformedLines() {
        let output = """
        not a process line
        12 1
        abc 1 0.0 10 root ?? name
        5 x 0.0 10 root ?? name
        5 1 y 10 root ?? name
        5 1 0.0 z root ?? name
        5 1 nan 10 root ?? name
        -5 1 0.0 10 root ?? name
        5 1 0.0 -10 root ?? name
        5 1 0.0 10 root ??
        5 1 0.0 10 root ??   \("")

        7 1 0.0 10 root ?? ok
        """

        XCTAssertEqual(PSOutputParser.parse(output).map(\.pid), [7])
    }

    func testEmptyOutputGivesNoEntries() {
        XCTAssertEqual(PSOutputParser.parse(""), [])
    }
}
