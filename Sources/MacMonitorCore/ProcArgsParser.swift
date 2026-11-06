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
    private static let argcSize = MemoryLayout<Int32>.size
    /// カーネルは実行パスの後をNULで埋め、argv[0]をargcの直後から数えてポインタ幅の境界に置く(実機の1,021件で確認)。
    private static let pointerSize = MemoryLayout<UInt>.size
    private static let workingDirectoryPrefix = Array("PWD=".utf8)
    private static let commandDirectoryPrefix = Array("INIT_CWD=".utf8)

    /// KERN_PROCARGS2のバッファは「argc、実行パス、NULの詰め物、argv、envp、空文字列、applestrings」の順に並ぶ。
    public static func parse(_ bytes: [UInt8]) -> ProcArgs? {
        guard bytes.count >= argcSize else { return nil }
        let argc = bytes.withUnsafeBytes { $0.loadUnaligned(as: Int32.self) }
        guard argc >= 0 else { return nil }

        guard let pathEnd = bytes[argcSize...].firstIndex(of: 0) else { return nil }
        let path = String(decoding: bytes[argcSize..<pathEnd], as: UTF8.self)

        // 詰め物のNULを読み飛ばすだけにすると、argv[0]が空文字列のときに1つずれて、環境変数を引数として読んでしまう。
        let pathAreaSize = pathEnd + 1 - argcSize
        var cursor = argcSize + (pathAreaSize + pointerSize - 1) / pointerSize * pointerSize
        var arguments: [String] = []
        while arguments.count < Int(argc), cursor < bytes.count {
            let end = bytes[cursor...].firstIndex(of: 0) ?? bytes.count
            arguments.append(String(decoding: bytes[cursor..<end], as: UTF8.self))
            cursor = end + 1
        }

        let environment = arguments.count == Int(argc) && cursor < bytes.count ? readEnvironment(bytes, from: cursor) : nil
        return ProcArgs(executablePath: path, arguments: arguments, environment: environment)
    }

    /// envpは空文字列で終わる。NULで終わらない項目は途中で切れているので読まない。
    private static func readEnvironment(_ bytes: [UInt8], from start: Int) -> LaunchEnvironment? {
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

    private static func value(of prefix: [UInt8], in entry: ArraySlice<UInt8>) -> String? {
        guard entry.starts(with: prefix) else { return nil }
        return String(decoding: entry.dropFirst(prefix.count), as: UTF8.self)
    }
}
