import Darwin

public struct ProcessStartTime: Equatable, Sendable {
    public let seconds: Int
    public let microseconds: Int32

    public init(seconds: Int, microseconds: Int32) {
        self.seconds = seconds
        self.microseconds = microseconds
    }
}

struct KernelProcessInfo {
    let parentPID: pid_t
    let userID: uid_t
    let startTime: ProcessStartTime

    /// sysctlは存在しないPIDでもエラーを返さず長さ0で成功するので、長さで判定する。
    static func read(pid: pid_t) -> KernelProcessInfo? {
        var info = kinfo_proc()
        var length = MemoryLayout<kinfo_proc>.stride
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        guard sysctl(&mib, UInt32(mib.count), &info, &length, nil, 0) == 0, length > 0 else { return nil }

        let start = info.kp_proc.p_un.__p_starttime
        return KernelProcessInfo(
            parentPID: info.kp_eproc.e_ppid,
            userID: info.kp_eproc.e_ucred.cr_uid,
            startTime: ProcessStartTime(seconds: start.tv_sec, microseconds: start.tv_usec)
        )
    }
}

public enum ProcessStartTimeReader {
    /// 一覧の取得中にプロセスが増えても足りるように、カーネルが返した大きさに余裕を足す。
    private static let extraProcessCapacity = 64

    public static func read(pid: pid_t) -> ProcessStartTime? {
        KernelProcessInfo.read(pid: pid)?.startTime
    }

    /// 大きさを問い合わせた後にプロセスが増えると、2回目の呼び出しがENOMEMで失敗する。そのときは問い合わせからやり直す。
    static let maximumAttempts = 3

    /// bufferがnilなら必要な大きさをlengthに入れる。戻り値は成功で0、失敗でerrno。
    typealias ProcListCall = (_ buffer: UnsafeMutableRawPointer?, _ length: inout Int) -> Int32

    private static let liveCall: ProcListCall = { buffer, length in
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_ALL, 0]
        return sysctl(&mib, UInt32(mib.count), buffer, &length, nil, 0) == 0 ? 0 : errno
    }

    /// 全プロセスの起動時刻を1回のsysctlで読む。nilは読めなかったことを表す。
    public static func readAll() -> [pid_t: ProcessStartTime]? {
        readAll(call: liveCall)
    }

    static func readAll(call: ProcListCall) -> [pid_t: ProcessStartTime]? {
        let stride = MemoryLayout<kinfo_proc>.stride
        for _ in 0..<maximumAttempts {
            var length = 0
            guard call(nil, &length) == 0 else { return nil }
            var processes = [kinfo_proc](repeating: kinfo_proc(), count: length / stride + extraProcessCapacity)
            length = processes.count * stride
            let result = processes.withUnsafeMutableBytes { call($0.baseAddress, &length) }
            if result == ENOMEM { continue }
            guard result == 0 else { return nil }

            var startTimes: [pid_t: ProcessStartTime] = [:]
            for info in processes.prefix(length / stride) {
                let start = info.kp_proc.p_un.__p_starttime
                startTimes[info.kp_proc.p_pid] = ProcessStartTime(seconds: start.tv_sec, microseconds: start.tv_usec)
            }
            return startTimes
        }
        return nil
    }
}
