import Darwin

public enum KillSignal: Sendable {
    case terminate
    case forceKill

    public var rawValue: Int32 {
        switch self {
        case .terminate: return SIGTERM
        case .forceKill: return SIGKILL
        }
    }
}

public struct KillTicket: Equatable, Identifiable, Sendable {
    public let pid: pid_t
    public let name: String
    public let startTime: ProcessStartTime

    public var id: pid_t { pid }

    public init(pid: pid_t, name: String, startTime: ProcessStartTime) {
        self.pid = pid
        self.name = name
        self.startTime = startTime
    }
}

public enum KillOutcome: Error, Equatable, Sendable {
    case sent
    case protected
    case pidReused
    case permissionDenied
    case alreadyExited
    case failed(errno: Int32)
    case targetChanged(listed: String, current: String)
}

public enum KillTargetName: Equatable, Sendable {
    case confirmed(String)
    case changed(listed: String, current: String)

    /// 読めない場合は一覧の名前を使う。読めて一覧と異なる場合は、一覧を見た後に対象が入れ替わった可能性がある。
    public static func resolve(listed: String, current: String?) -> KillTargetName {
        guard let current, !current.isEmpty else { return .confirmed(listed) }
        return current == listed ? .confirmed(listed) : .changed(listed: listed, current: current)
    }
}

public struct ProcessKiller {
    private static let lowestKillablePID: pid_t = 2

    private let ownPID: pid_t
    private let readStartTime: (pid_t) -> ProcessStartTime?
    private let readName: (pid_t) -> String?
    private let sendSignal: (pid_t, Int32) -> Int32

    /// sendSignalは成功で0、失敗でerrnoを返す。
    public init(
        ownPID: pid_t,
        readStartTime: @escaping (pid_t) -> ProcessStartTime?,
        readName: @escaping (pid_t) -> String?,
        sendSignal: @escaping (pid_t, Int32) -> Int32
    ) {
        self.ownPID = ownPID
        self.readStartTime = readStartTime
        self.readName = readName
        self.sendSignal = sendSignal
    }

    public static let live = ProcessKiller(
        ownPID: getpid(),
        readStartTime: { ProcessStartTimeReader.read(pid: $0) },
        readName: { PSRunner.readName(pid: $0) },
        sendSignal: { pid, signal in kill(pid, signal) == 0 ? 0 : errno }
    )

    /// 確認ダイアログを開くときに呼び、そのときの起動時刻と名前を控える。
    /// nameには一覧に表示した、psと同じ取り方の名前を渡す。
    public func prepare(pid: pid_t, name: String) -> Result<KillTicket, KillOutcome> {
        guard isKillable(pid) else { return .failure(.protected) }
        guard let startTime = readStartTime(pid) else { return .failure(.alreadyExited) }
        switch KillTargetName.resolve(listed: name, current: readName(pid)) {
        case .confirmed(let confirmed):
            return .success(KillTicket(pid: pid, name: confirmed, startTime: startTime))
        case .changed(let listed, let current):
            return .failure(.targetChanged(listed: listed, current: current))
        }
    }

    /// 確認中に対象が終了し、同じPIDを別のプロセスが使っている場合に備えて、送信の直前に起動時刻を比べる。
    public func send(_ ticket: KillTicket, signal: KillSignal) -> KillOutcome {
        guard isKillable(ticket.pid) else { return .protected }
        guard let current = readStartTime(ticket.pid) else { return .alreadyExited }
        guard current == ticket.startTime else { return .pidReused }

        switch sendSignal(ticket.pid, signal.rawValue) {
        case 0: return .sent
        case EPERM: return .permissionDenied
        case ESRCH: return .alreadyExited
        case let code: return .failed(errno: code)
        }
    }

    /// kill(2)は0と負のPIDをプロセスグループ全体への送信として扱うので、1以下を必ず弾く。
    private func isKillable(_ pid: pid_t) -> Bool {
        pid >= Self.lowestKillablePID && pid != ownPID
    }
}
