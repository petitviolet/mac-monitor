import Foundation

public enum PSOutputParser {
    private static let leadingColumnCount = 6
    private static let noTTY = "??"

    public static func parse(_ output: String) -> [ProcessEntry] {
        output.split(separator: "\n").compactMap(parseLine)
    }

    private static func parseLine(_ line: Substring) -> ProcessEntry? {
        // commは空白を含むので、先頭6列だけを切り出し、残りをそのままcommとして扱う。
        let parts = line.split(
            maxSplits: leadingColumnCount,
            omittingEmptySubsequences: true,
            whereSeparator: { $0 == " " || $0 == "\t" }
        )
        guard parts.count == leadingColumnCount + 1 else { return nil }
        guard let pid = pid_t(parts[0]), pid >= 0,
              let ppid = pid_t(parts[1]), ppid >= 0,
              let cpu = Double(parts[2]), cpu.isFinite, cpu >= 0,
              let rss = UInt64(parts[3]) else { return nil }

        let name = parts[6].trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return nil }
        let tty = parts[5] == noTTY ? nil : String(parts[5])
        return ProcessEntry(pid: pid, ppid: ppid, cpuPercent: cpu, rssKB: rss, user: String(parts[4]), name: name, tty: tty)
    }
}
