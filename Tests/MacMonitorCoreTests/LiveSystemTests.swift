import Darwin
import XCTest
@testable import MacMonitorCore

/// 実機のOSから読む経路を確かめる。シグナルを送る相手は、このテストが起動したsleepだけに限る。
final class LiveSystemTests: XCTestCase {
    private func startSleep() throws -> Process {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sleep")
        process.arguments = ["300"]
        try process.run()
        return process
    }

    func testPSListsThisProcessWithItsOwnUser() throws {
        let entries = try XCTUnwrap(PSRunner.run())
        XCTAssertGreaterThan(entries.count, 1)
        let me = try XCTUnwrap(entries.first { $0.pid == getpid() })
        XCTAssertEqual(me.ppid, getppid())
        XCTAssertEqual(me.user, NSUserName())
    }

    func testPSKeepsNonASCIINamesAndDotDecimals() throws {
        // ps -cのcommはargv[0]から作られるので、exec -aで名前を変えられる。
        let child = Process()
        child.executableURL = URL(fileURLWithPath: "/bin/bash")
        child.arguments = ["-c", "exec -a 日本語スリープ /bin/sleep 30"]
        try child.run()
        defer { child.terminate() }

        var entry: ProcessEntry?
        for _ in 0..<50 {
            entry = PSRunner.run()?.first { $0.pid == child.processIdentifier && $0.name != "bash" }
            if entry != nil { break }
            Thread.sleep(forTimeInterval: 0.02)
        }
        XCTAssertEqual(entry?.name, "日本語スリープ")
    }

    func testReadNameOfOwnChildAndMissingPID() throws {
        let child = try startSleep()
        defer { child.terminate() }
        var name: String?
        for _ in 0..<50 {
            name = PSRunner.readName(pid: child.processIdentifier)
            if name == "sleep" { break }
            Thread.sleep(forTimeInterval: 0.02)
        }
        XCTAssertEqual(name, "sleep")
        XCTAssertNil(PSRunner.readName(pid: 99_999_999))
    }

    func testLiveNetworkListContainsNoExcludedInterfaceIndex() {
        // 実機のバッファから名前を読めていれば、utunなどのインデックスは結果に入らない。
        var index: UInt32 = 1
        var name = [CChar](repeating: 0, count: Int(IF_NAMESIZE))
        let counted = NetworkCountersReader.read() ?? [:]
        while if_indextoname(index, &name) != nil {
            let text = String(cString: name)
            if !NetworkInterfaceFilter.isCounted(flags: IFF_UP | IFF_RUNNING, name: text) {
                XCTAssertNil(counted[UInt16(index)], text)
            }
            index += 1
        }
    }

    func testStartTimeIsStableAndMissingForDeadPID() throws {
        let child = try startSleep()
        defer { child.terminate() }

        let first = try XCTUnwrap(ProcessStartTimeReader.read(pid: child.processIdentifier))
        XCTAssertEqual(ProcessStartTimeReader.read(pid: child.processIdentifier), first)
        XCTAssertNil(ProcessStartTimeReader.read(pid: 99_999_999))
    }

    func testKillerTerminatesOwnChildAndReportsExitAfterwards() throws {
        for signal in [KillSignal.terminate, .forceKill] {
            let child = try startSleep()
            let pid = child.processIdentifier
            let killer = ProcessKiller.live

            let ticket = try killer.prepare(pid: pid, name: "sleep").get()
            XCTAssertEqual(killer.send(ticket, signal: signal), .sent)
            child.waitUntilExit()

            XCTAssertEqual(child.terminationStatus, signal.rawValue)
            XCTAssertEqual(killer.send(ticket, signal: signal), .alreadyExited)
        }
    }

    func testLiveKillerRefusesThisTestProcess() {
        XCTAssertEqual(ProcessKiller.live.prepare(pid: getpid(), name: "self"), .failure(.protected))
    }

    func testDetailOfChildShowsPathAndArguments() throws {
        let child = try startSleep()
        defer { child.terminate() }
        // execが終わる前に読むと親プロセスの実行パスが返るので、切り替わるのを待つ。
        var detail: ProcessDetail?
        for _ in 0..<50 {
            detail = ProcessDetailReader.read(pid: child.processIdentifier, psEntry: nil)
            if detail?.path == "/bin/sleep" { break }
            Thread.sleep(forTimeInterval: 0.02)
        }

        let read = try XCTUnwrap(detail)
        XCTAssertEqual(read.path, "/bin/sleep")
        XCTAssertEqual(read.parentPID, getpid())
        XCTAssertEqual(read.arguments, ["/bin/sleep", "300"])
        XCTAssertEqual(read.user, NSUserName())
        XCTAssertNotNil(read.startTime)
        XCTAssertEqual(read.threadCount, 1)
        XCTAssertNotNil(read.footprintBytes)
        XCTAssertNotNil(read.rssBytes)
    }

    func testDetailCPUTimeMatchesGetrusageInSeconds() throws {
        let deadline = Date().addingTimeInterval(0.3)
        var counter: UInt64 = 0
        while Date() < deadline { counter &+= 1 }
        XCTAssertGreaterThan(counter, 0)

        let measured = try XCTUnwrap(ProcessDetailReader.read(pid: getpid(), psEntry: nil)?.cpuTimeSeconds)
        var usage = rusage()
        getrusage(RUSAGE_SELF, &usage)
        let expected = Double(usage.ru_utime.tv_sec + usage.ru_stime.tv_sec)
            + Double(usage.ru_utime.tv_usec + usage.ru_stime.tv_usec) / 1_000_000
        XCTAssertEqual(measured, expected, accuracy: 0.5)
    }

    func testDetailOfMissingPIDIsNil() {
        XCTAssertNil(ProcessDetailReader.read(pid: 99_999_999, psEntry: nil))
    }

    func testRootOwnedProcessDetailFailsPerFieldWithoutCrashing() throws {
        let launchd = try XCTUnwrap(ProcessDetailReader.read(pid: 1, psEntry: nil))
        XCTAssertEqual(launchd.parentPID, 0)
        XCTAssertNotNil(launchd.startTime)
    }

    func testSamplerReturnsMeasuringFirstThenValues() throws {
        let sampler = SystemSampler()
        let first = sampler.sample()
        XCTAssertNil(first.cpu)
        XCTAssertNil(first.network)
        XCTAssertNotNil(first.processes)
        let memory = try XCTUnwrap(first.memory)
        XCTAssertGreaterThan(memory.totalBytes, 0)
        XCTAssertEqual(
            memory.appBytes + memory.wiredBytes + memory.compressedBytes + memory.freeBytes,
            memory.totalBytes
        )
        let disk = try XCTUnwrap(first.disk)
        XCTAssertGreaterThan(disk.totalBytes, 0)

        Thread.sleep(forTimeInterval: 0.2)
        let second = sampler.sample()
        let cpu = try XCTUnwrap(second.cpu)
        XCTAssertEqual(cpu.perCore.count, ProcessInfo.processInfo.processorCount)
        XCTAssertTrue((0...1).contains(cpu.overall))
        XCTAssertNotNil(second.network)
    }
}
