public struct ProcArgs: Equatable, Sendable {
    public let executablePath: String
    public let arguments: [String]

    public init(executablePath: String, arguments: [String]) {
        self.executablePath = executablePath
        self.arguments = arguments
    }
}

public enum ProcArgsParser {
    private static let argcSize = MemoryLayout<Int32>.size

    /// KERN_PROCARGS2のバッファは「argc、実行パス、NULの詰め物、argv、envp」の順に並ぶ。
    /// envpは秘密情報を含みうるので読まない。
    public static func parse(_ bytes: [UInt8]) -> ProcArgs? {
        guard bytes.count >= argcSize else { return nil }
        let argc = bytes.withUnsafeBytes { $0.loadUnaligned(as: Int32.self) }
        guard argc >= 0 else { return nil }

        guard let pathEnd = bytes[argcSize...].firstIndex(of: 0) else { return nil }
        let path = String(decoding: bytes[argcSize..<pathEnd], as: UTF8.self)

        var arguments: [String] = []
        var cursor = pathEnd
        while cursor < bytes.count, bytes[cursor] == 0 {
            cursor += 1
        }
        while arguments.count < Int(argc), cursor < bytes.count {
            let end = bytes[cursor...].firstIndex(of: 0) ?? bytes.count
            arguments.append(String(decoding: bytes[cursor..<end], as: UTF8.self))
            cursor = end + 1
        }
        return ProcArgs(executablePath: path, arguments: arguments)
    }
}
