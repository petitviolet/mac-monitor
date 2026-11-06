import XCTest
@testable import MacMonitorCore

final class ProcArgsParserTests: XCTestCase {
    private static let pointerSize = 8

    /// カーネルと同じ並びを作る。実行パスの後は、argcの直後から数えて8バイト境界までNULで埋める。
    private func buffer(argc: Int32, path: String, _ rest: String) -> [UInt8] {
        let pathBytes = Array(path.utf8) + [0]
        let padding = (Self.pointerSize - pathBytes.count % Self.pointerSize) % Self.pointerSize
        return withUnsafeBytes(of: argc) { Array($0) } + pathBytes + [UInt8](repeating: 0, count: padding) + Array(rest.utf8)
    }

    private func raw(argc: Int32, _ body: String) -> [UInt8] {
        withUnsafeBytes(of: argc) { Array($0) } + Array(body.utf8)
    }

    func testParsesPathAndArgumentsAndKeepsOtherVariablesOutOfArguments() {
        let parsed = ProcArgsParser.parse(buffer(argc: 2, path: "/bin/sleep", "sleep\u{0}300\u{0}HOME=/Users/x\u{0}SECRET=y\u{0}"))
        XCTAssertEqual(parsed?.executablePath, "/bin/sleep")
        XCTAssertEqual(parsed?.arguments, ["sleep", "300"])
    }

    func testEmptyArgv0DoesNotShiftArgumentsIntoEnvironment() {
        let parsed = ProcArgsParser.parse(buffer(argc: 1, path: "/usr/bin/x", "\u{0}TOKEN=secret\u{0}PWD=/work\u{0}"))
        XCTAssertEqual(parsed?.arguments, [""])
        XCTAssertEqual(parsed?.environment?.workingDirectoryAtLaunch, "/work")
    }

    func testPathThatEndsOnTheBoundaryHasNoPadding() {
        // 7文字とNULでちょうど8バイトになる。
        let parsed = ProcArgsParser.parse(buffer(argc: 1, path: "/bin/ab", "ab\u{0}PWD=/p\u{0}"))
        XCTAssertEqual(parsed?.arguments, ["ab"])
        XCTAssertEqual(parsed?.environment?.workingDirectoryAtLaunch, "/p")
    }

    func testBufferShorterThanArgcFieldGivesNil() {
        XCTAssertNil(ProcArgsParser.parse([]))
        XCTAssertNil(ProcArgsParser.parse([1, 0, 0]))
    }

    func testNegativeArgcGivesNil() {
        XCTAssertNil(ProcArgsParser.parse(raw(argc: -1, "/bin/sleep\u{0}")))
    }

    func testUnterminatedPathGivesNil() {
        XCTAssertNil(ProcArgsParser.parse(raw(argc: 1, "/bin/sleep")))
    }

    func testBufferEndingInsideThePaddingGivesNoArguments() {
        let parsed = ProcArgsParser.parse(raw(argc: 1, "/bin/sleep\u{0}"))
        XCTAssertEqual(parsed?.arguments, [])
        XCTAssertNil(parsed?.environment)
    }

    func testArgcLargerThanBufferKeepsWhatExists() {
        let parsed = ProcArgsParser.parse(buffer(argc: 100, path: "/bin/sleep", "sleep\u{0}300\u{0}"))
        XCTAssertEqual(parsed?.arguments, ["sleep", "300"])
    }

    func testUnterminatedLastArgumentIsKept() {
        let parsed = ProcArgsParser.parse(buffer(argc: 2, path: "/bin/sleep", "sleep\u{0}300"))
        XCTAssertEqual(parsed?.arguments, ["sleep", "300"])
    }

    func testZeroArgcGivesNoArguments() {
        let parsed = ProcArgsParser.parse(buffer(argc: 0, path: "/bin/sleep", "HOME=/x\u{0}"))
        XCTAssertEqual(parsed?.executablePath, "/bin/sleep")
        XCTAssertEqual(parsed?.arguments, [])
    }

    func testReadsPWDAndINITCWDFromEnvironment() {
        let rest = "node\u{0}HOME=/Users/x\u{0}PWD=/work/app\u{0}INIT_CWD=/work\u{0}TOKEN=secret\u{0}"
        let parsed = ProcArgsParser.parse(buffer(argc: 1, path: "/usr/bin/node", rest))
        XCTAssertEqual(parsed?.environment, LaunchEnvironment(workingDirectoryAtLaunch: "/work/app", commandDirectory: "/work"))
    }

    func testMissingVariablesGiveNil() {
        let parsed = ProcArgsParser.parse(buffer(argc: 1, path: "/bin/sleep", "sleep\u{0}HOME=/Users/x\u{0}"))
        XCTAssertEqual(parsed?.environment, LaunchEnvironment(workingDirectoryAtLaunch: nil, commandDirectory: nil))
    }

    func testNoEnvironmentAtAllGivesNil() {
        let parsed = ProcArgsParser.parse(buffer(argc: 1, path: "/bin/sleep", "sleep\u{0}\u{0}\u{0}"))
        XCTAssertEqual(parsed?.arguments, ["sleep"])
        XCTAssertNil(parsed?.environment)
    }

    func testOnlyNamesAtTheStartOfAnEntryMatch() {
        let rest = "x\u{0}OLDPWD=/old\u{0}FOO=PWD=/evil\u{0}XINIT_CWD=/nope\u{0}PWD=/real\u{0}"
        let parsed = ProcArgsParser.parse(buffer(argc: 1, path: "/bin/x", rest))
        XCTAssertEqual(parsed?.environment, LaunchEnvironment(workingDirectoryAtLaunch: "/real", commandDirectory: nil))
    }

    func testFirstOccurrenceWins() {
        let parsed = ProcArgsParser.parse(buffer(argc: 1, path: "/bin/x", "x\u{0}PWD=/first\u{0}PWD=/second\u{0}"))
        XCTAssertEqual(parsed?.environment?.workingDirectoryAtLaunch, "/first")
    }

    func testTruncatedEntryWithoutTerminatorIsIgnored() {
        let parsed = ProcArgsParser.parse(buffer(argc: 1, path: "/bin/x", "x\u{0}INIT_CWD=/a\u{0}PWD=/cut-in-the-mid"))
        XCTAssertEqual(parsed?.environment, LaunchEnvironment(workingDirectoryAtLaunch: nil, commandDirectory: "/a"))
    }

    func testEnvironmentEndsAtEmptyStringAndAppleStringsAreNotRead() {
        let parsed = ProcArgsParser.parse(buffer(argc: 1, path: "/bin/x", "x\u{0}HOME=/h\u{0}\u{0}\u{0}PWD=/apple-area\u{0}"))
        XCTAssertEqual(parsed?.environment, LaunchEnvironment(workingDirectoryAtLaunch: nil, commandDirectory: nil))
    }

    func testArgcLargerThanBufferLeavesNoEnvironment() {
        let parsed = ProcArgsParser.parse(buffer(argc: 5, path: "/bin/x", "x\u{0}PWD=/looks-like-arg\u{0}"))
        XCTAssertEqual(parsed?.arguments, ["x", "PWD=/looks-like-arg"])
        XCTAssertNil(parsed?.environment)
    }

    func testEmptyValueIsKeptAsEmpty() {
        let parsed = ProcArgsParser.parse(buffer(argc: 1, path: "/bin/x", "x\u{0}PWD=\u{0}"))
        XCTAssertEqual(parsed?.environment?.workingDirectoryAtLaunch, "")
    }
}
