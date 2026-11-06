import Darwin

public enum TerminalLaunch {
    /// shはyarnやlaunchdのスクリプトも使うので、端末の目印にしない。
    private static let shellNames: Set<String> = ["zsh", "bash", "fish", "tcsh", "ksh", "nu"]
    private static let loginShellPrefix: Character = "-"
    private static let rootPID: pid_t = 1
    /// 端末エミュレータが割り当てる擬似端末。consoleなどのTTYは端末アプリからの起動を示さない。
    private static let pseudoTerminalPrefix = "ttys"

    /// ttysで始まるTTYがあるか、ppidを辿った祖先にシェルがいるプロセスを返す。
    /// 端末を閉じて親を失ったプロセスはTTYが外れ、親がlaunchdになるので見つけられない。
    public static func pids(in entries: [ProcessEntry]) -> Set<pid_t> {
        let byPID = Dictionary(entries.map { ($0.pid, $0) }, uniquingKeysWith: { first, _ in first })
        return Set(entries.filter { hasPseudoTerminal($0) || hasShellAncestor($0, byPID: byPID) }.map(\.pid))
    }

    private static func hasShellAncestor(_ entry: ProcessEntry, byPID: [pid_t: ProcessEntry]) -> Bool {
        var visited: Set<pid_t> = [entry.pid]
        var parentPID = entry.ppid
        while parentPID > rootPID, visited.insert(parentPID).inserted, let parent = byPID[parentPID] {
            if isShell(parent.name) { return true }
            parentPID = parent.ppid
        }
        return false
    }

    private static func hasPseudoTerminal(_ entry: ProcessEntry) -> Bool {
        guard let tty = entry.tty, tty.hasPrefix(pseudoTerminalPrefix) else { return false }
        return tty.count > pseudoTerminalPrefix.count
    }

    private static func isShell(_ name: String) -> Bool {
        let bare = name.first == loginShellPrefix ? String(name.dropFirst()) : name
        return shellNames.contains(bare)
    }
}
