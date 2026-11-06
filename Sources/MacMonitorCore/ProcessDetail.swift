import Foundation

/// nilの項目は「読めなかった」ことを表す。項目ごとに別のAPIから読むので、独立して失敗する。
public struct ProcessDetail: Equatable, Sendable {
    public let pid: pid_t
    public let parentPID: pid_t
    public let user: String?
    public let path: String?
    public let arguments: [String]?
    /// nilは環境変数を読めなかったことを表す。
    public let launchEnvironment: LaunchEnvironment?
    /// 今のカレントディレクトリ。
    public let workingDirectory: String?
    public let startTime: Date?
    public let threadCount: Int?
    public let cpuTimeSeconds: Double?
    public let footprintBytes: UInt64?
    public let rssBytes: UInt64?
}

public enum ProcessDetailReader {
    private static let nanosecondsPerSecond = 1_000_000_000.0
    private static let microsecondsPerSecond = 1_000_000.0
    /// SwiftからマクロPROC_PIDPATHINFO_MAXSIZEを参照できないので、定義どおり4*MAXPATHLENで計算する。
    private static let pathBufferSize = 4 * Int(MAXPATHLEN)
    private static let fallbackPasswordBufferSize = 4096

    /// 戻り値のnilはプロセスが存在しないことを表す。
    public static func read(pid: pid_t, psEntry: ProcessEntry?) -> ProcessDetail? {
        guard let kernel = KernelProcessInfo.read(pid: pid) else { return nil }

        let rusage = readRusage(pid: pid)
        let procArgs = readProcArgs(pid: pid)
        let start = kernel.startTime
        return ProcessDetail(
            pid: pid,
            parentPID: kernel.parentPID,
            user: psEntry?.user ?? userName(uid: kernel.userID),
            path: readPath(pid: pid),
            arguments: procArgs?.arguments,
            launchEnvironment: procArgs?.environment,
            workingDirectory: readWorkingDirectory(pid: pid),
            startTime: Date(timeIntervalSince1970: Double(start.seconds) + Double(start.microseconds) / microsecondsPerSecond),
            threadCount: readThreadCount(pid: pid),
            cpuTimeSeconds: rusage.map { cpuSeconds(from: $0) },
            footprintBytes: rusage?.ri_phys_footprint,
            // psはsetuid rootなので、rusageを拒否されるプロセスでもRSSを読める。
            rssBytes: psEntry?.rssBytes ?? rusage?.ri_resident_size
        )
    }

    private static func userName(uid: uid_t) -> String? {
        let suggestedSize = sysconf(_SC_GETPW_R_SIZE_MAX)
        var buffer = [CChar](repeating: 0, count: suggestedSize > 0 ? suggestedSize : fallbackPasswordBufferSize)
        var entry = passwd()
        var result: UnsafeMutablePointer<passwd>?
        guard getpwuid_r(uid, &entry, &buffer, buffer.count, &result) == 0, result != nil else { return nil }
        return String(cString: entry.pw_name)
    }

    private static func readPath(pid: pid_t) -> String? {
        var buffer = [CChar](repeating: 0, count: pathBufferSize)
        guard proc_pidpath(pid, &buffer, UInt32(buffer.count)) > 0 else { return nil }
        return String(cString: buffer)
    }

    private static func readProcArgs(pid: pid_t) -> ProcArgs? {
        var maxSize: Int32 = 0
        var maxSizeLength = MemoryLayout<Int32>.size
        var argmaxMIB: [Int32] = [CTL_KERN, KERN_ARGMAX]
        guard sysctl(&argmaxMIB, UInt32(argmaxMIB.count), &maxSize, &maxSizeLength, nil, 0) == 0, maxSize > 0 else {
            return nil
        }

        var buffer = [UInt8](repeating: 0, count: Int(maxSize))
        var length = buffer.count
        var mib: [Int32] = [CTL_KERN, KERN_PROCARGS2, pid]
        guard sysctl(&mib, UInt32(mib.count), &buffer, &length, nil, 0) == 0 else { return nil }
        buffer.removeSubrange(length...)
        return ProcArgsParser.parse(buffer)
    }

    private static func readWorkingDirectory(pid: pid_t) -> String? {
        var info = proc_vnodepathinfo()
        let size = Int32(MemoryLayout<proc_vnodepathinfo>.stride)
        guard proc_pidinfo(pid, PROC_PIDVNODEPATHINFO, 0, &info, size) == size else { return nil }
        return withUnsafeBytes(of: info.pvi_cdir.vip_path) { buffer in
            let bytes = buffer.prefix { $0 != 0 }
            return bytes.isEmpty ? nil : String(decoding: bytes, as: UTF8.self)
        }
    }

    private static func readThreadCount(pid: pid_t) -> Int? {
        var info = proc_taskinfo()
        let size = Int32(MemoryLayout<proc_taskinfo>.stride)
        guard proc_pidinfo(pid, PROC_PIDTASKINFO, 0, &info, size) == size else { return nil }
        return Int(info.pti_threadnum)
    }

    private static func readRusage(pid: pid_t) -> rusage_info_v4? {
        var info = rusage_info_v4()
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) {
                proc_pid_rusage(pid, RUSAGE_INFO_V4, $0)
            }
        }
        return result == 0 ? info : nil
    }

    /// Apple Siliconのrusageの時間はmach時間の単位で返るので、timebaseでナノ秒へ換算する。
    private static func cpuSeconds(from info: rusage_info_v4) -> Double {
        var timebase = mach_timebase_info_data_t()
        mach_timebase_info(&timebase)
        let ticks = Double(info.ri_user_time) + Double(info.ri_system_time)
        return ticks * Double(timebase.numer) / Double(timebase.denom) / nanosecondsPerSecond
    }
}
