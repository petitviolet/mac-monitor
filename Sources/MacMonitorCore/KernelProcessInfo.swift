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
    public static func read(pid: pid_t) -> ProcessStartTime? {
        KernelProcessInfo.read(pid: pid)?.startTime
    }
}
