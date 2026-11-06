import Foundation

public enum PSRunner {
    private static let executablePath = "/bin/ps"
    private static let listArguments = ["-Aceo", "pid=,ppid=,pcpu=,rss=,user=,tty=,comm="]
    private static let listTimeout: TimeInterval = 5
    /// ダイアログを開く操作の途中で呼ぶので、一覧より短くする。
    private static let nameTimeout: TimeInterval = 1
    /// LC_ALL=Cでは非ASCIIの名前が化けるので、文字コードと数値の書式を別々に指定する。
    private static let environment = ["LC_CTYPE": "UTF-8", "LC_NUMERIC": "C"]

    /// /bin/psはsetuid rootなので、proc_pid_rusageを拒否されるプロセスのCPUとRSSも読める。
    public static func run() -> [ProcessEntry]? {
        capture(executablePath: executablePath, arguments: listArguments, timeout: listTimeout)
            .map { PSOutputParser.parse(String(decoding: $0, as: UTF8.self)) }
    }

    /// 一覧と同じ取り方で1プロセスの名前を読む。proc_nameとは1割強のプロセスで値が異なり
    /// (ps -cはargv[0]由来)、root所有のプロセスは読めないので比較に使えない。
    public static func readName(pid: pid_t) -> String? {
        guard let data = capture(
            executablePath: executablePath,
            arguments: ["-co", "comm=", "-p", String(pid)],
            timeout: nameTimeout
        ) else { return nil }
        let name = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? nil : name
    }

    /// 期限を過ぎたら相手を止めてnilを返す。読み取りをブロックしないので、相手が固まっても呼び出し側は止まらない。
    static func capture(executablePath: String, arguments: [String], timeout: TimeInterval) -> Data? {
        let process = Process()
        let stdout = Pipe()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = arguments
        process.environment = environment
        process.standardOutput = stdout
        process.standardError = FileHandle.nullDevice

        let exited = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in exited.signal() }
        guard (try? process.run()) != nil else { return nil }

        let output = OutputBuffer()
        let outputEnded = DispatchSemaphore(value: 0)
        let reader = stdout.fileHandleForReading
        reader.readabilityHandler = { handle in
            let chunk = handle.availableData
            if chunk.isEmpty {
                handle.readabilityHandler = nil
                outputEnded.signal()
            } else {
                output.append(chunk)
            }
        }

        let deadline = DispatchTime.now() + timeout
        guard outputEnded.wait(timeout: deadline) == .success, exited.wait(timeout: deadline) == .success else {
            reader.readabilityHandler = nil
            process.terminate()
            return nil
        }
        return process.terminationStatus == 0 ? output.data : nil
    }
}

private final class OutputBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private var stored = Data()

    func append(_ chunk: Data) {
        lock.lock()
        stored.append(chunk)
        lock.unlock()
    }

    var data: Data {
        lock.lock()
        defer { lock.unlock() }
        return stored
    }
}
