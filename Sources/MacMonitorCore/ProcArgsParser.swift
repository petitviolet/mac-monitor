import Darwin

/// 環境変数のうち、起動した場所を示す2つだけを持つ。他の変数は秘密情報を含みうるので、文字列にもしない。
public struct LaunchEnvironment: Equatable, Sendable {
    /// 親プロセスから引き継いだPWD。起動したときに親のシェルがいた場所を示す。
    public let workingDirectoryAtLaunch: String?
    /// INIT_CWD。npm、yarn、pnpmがスクリプトを実行する前のカレントディレクトリ。
    public let commandDirectory: String?

    public init(workingDirectoryAtLaunch: String?, commandDirectory: String?) {
        self.workingDirectoryAtLaunch = workingDirectoryAtLaunch
        self.commandDirectory = commandDirectory
    }
}

public struct ProcArgs: Equatable, Sendable {
    public let executablePath: String
    public let arguments: [String]
    /// nilは環境変数が1つも返らなかったことを表す。実測では、/binなどにあるAppleのバイナリを他のプロセスから読むと空で返った。
    /// env -iで環境変数を空にして起動したプロセスも同じ形になるので、両者は区別できない。
    public let environment: LaunchEnvironment?
}

public enum ProcArgsParser {
    private typealias Bytes = UnsafeBufferPointer<UInt8>

    private static let argcSize = MemoryLayout<Int32>.size
    /// カーネルは実行パスの後をNULで埋め、argv[0]をargcの直後から数えてポインタ幅の境界に置く(実機の1,021件で確認)。
    private static let pointerSize = MemoryLayout<UInt>.size
    private static let workingDirectoryPrefix = Array("PWD=".utf8)
    private static let commandDirectoryPrefix = Array("INIT_CWD=".utf8)

    /// 文字列を作らずに、実行パスとargvの位置、環境変数の開始位置だけを求めた結果。
    private struct Layout {
        let executablePath: Range<Int>
        let arguments: [Range<Int>]
        /// argvを最後まで読めたときだけ値を持つ。
        let environmentStart: Int?
    }

    /// KERN_PROCARGS2のバッファは「argc、実行パス、NULの詰め物、argv、envp、空文字列、applestrings」の順に並ぶ。
    public static func parse(_ bytes: [UInt8]) -> ProcArgs? {
        bytes.withUnsafeBufferPointer { parse($0) }
    }

    static func parse(_ bytes: UnsafeBufferPointer<UInt8>) -> ProcArgs? {
        guard let layout = layout(of: bytes) else { return nil }
        return ProcArgs(
            executablePath: String(decoding: bytes[layout.executablePath], as: UTF8.self),
            arguments: layout.arguments.map { String(decoding: bytes[$0], as: UTF8.self) },
            environment: layout.environmentStart.flatMap { readEnvironment(bytes, from: $0) }
        )
    }

    /// 検索用に、引数を文字列にせず環境変数のPWDとINIT_CWDだけを読む。
    public static func parseLaunchEnvironment(_ bytes: [UInt8]) -> LaunchEnvironment? {
        bytes.withUnsafeBufferPointer { parseLaunchEnvironment($0) }
    }

    static func parseLaunchEnvironment(_ bytes: UnsafeBufferPointer<UInt8>) -> LaunchEnvironment? {
        layout(of: bytes)?.environmentStart.flatMap { readEnvironment(bytes, from: $0) }
    }

    private static func layout(of bytes: Bytes) -> Layout? {
        guard bytes.count >= argcSize else { return nil }
        let argc = UnsafeRawBufferPointer(bytes).loadUnaligned(as: Int32.self)
        guard argc >= 0 else { return nil }

        guard let pathEnd = bytes[argcSize...].firstIndex(of: 0) else { return nil }

        // 詰め物のNULを読み飛ばすだけにすると、argv[0]が空文字列のときに1つずれて、環境変数を引数として読んでしまう。
        let pathAreaSize = pathEnd + 1 - argcSize
        var cursor = argcSize + (pathAreaSize + pointerSize - 1) / pointerSize * pointerSize
        var arguments: [Range<Int>] = []
        while arguments.count < Int(argc), cursor < bytes.count {
            let end = bytes[cursor...].firstIndex(of: 0) ?? bytes.count
            arguments.append(cursor..<end)
            cursor = end + 1
        }

        let complete = arguments.count == Int(argc) && cursor < bytes.count
        return Layout(executablePath: argcSize..<pathEnd, arguments: arguments, environmentStart: complete ? cursor : nil)
    }

    /// envpは空文字列で終わる。NULで終わらない項目は途中で切れているので読まない。
    private static func readEnvironment(_ bytes: Bytes, from start: Int) -> LaunchEnvironment? {
        var workingDirectory: String?
        var commandDirectory: String?
        var entryCount = 0
        var cursor = start
        while cursor < bytes.count, let end = bytes[cursor...].firstIndex(of: 0), end > cursor {
            entryCount += 1
            let entry = bytes[cursor..<end]
            if workingDirectory == nil, let value = value(of: workingDirectoryPrefix, in: entry) {
                workingDirectory = value
            } else if commandDirectory == nil, let value = value(of: commandDirectoryPrefix, in: entry) {
                commandDirectory = value
            }
            cursor = end + 1
        }
        guard entryCount > 0 else { return nil }
        return LaunchEnvironment(workingDirectoryAtLaunch: workingDirectory, commandDirectory: commandDirectory)
    }

    private static func value(of prefix: [UInt8], in entry: Slice<Bytes>) -> String? {
        guard entry.starts(with: prefix) else { return nil }
        return String(decoding: entry.dropFirst(prefix.count), as: UTF8.self)
    }
}

/// KERN_PROCARGS2を読むバッファを使い回す。検索で全プロセスを読むときに、プロセスごとに大きなバッファを作らないため。
/// 状態を持つので、同じキューからのみ使う。
final class ProcArgsReader {
    private var buffer: [UInt8] = []

    func readProcArgs(pid: pid_t) -> ProcArgs? {
        read(pid: pid) { ProcArgsParser.parse($0) }
    }

    func readLaunchEnvironment(pid: pid_t) -> LaunchEnvironment? {
        read(pid: pid) { ProcArgsParser.parseLaunchEnvironment($0) }
    }

    private func read<T>(pid: pid_t, _ parse: (UnsafeBufferPointer<UInt8>) -> T?) -> T? {
        if buffer.isEmpty {
            guard let size = Self.argumentAreaSize() else { return nil }
            buffer = [UInt8](repeating: 0, count: size)
        }
        var length = buffer.count
        var mib: [Int32] = [CTL_KERN, KERN_PROCARGS2, pid]
        guard sysctl(&mib, UInt32(mib.count), &buffer, &length, nil, 0) == 0 else { return nil }
        return buffer.withUnsafeBufferPointer { parse(UnsafeBufferPointer(rebasing: $0[..<length])) }
    }

    private static func argumentAreaSize() -> Int? {
        var maxSize: Int32 = 0
        var maxSizeLength = MemoryLayout<Int32>.size
        var mib: [Int32] = [CTL_KERN, KERN_ARGMAX]
        guard sysctl(&mib, UInt32(mib.count), &maxSize, &maxSizeLength, nil, 0) == 0, maxSize > 0 else { return nil }
        return Int(maxSize)
    }
}
