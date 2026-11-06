import Darwin

public struct LaunchPWDRefresh: Equatable, Sendable {
    /// 読めたプロセスだけの、PIDから起動時のPWDへの対応表。
    public let pwds: [pid_t: String]
    /// 前回のrefreshから対応表が変わったか。変わっていなければ、画面へ渡し直さなくてよい。
    public let changed: Bool
}

/// 全プロセスの起動時のPWDを持つ。PWDはプロセスの生存中に変わらないとみなし、PIDと起動時刻が同じ間は読み直さない。
/// 同じPIDのままexecで環境変数を差し替えたプロセスも、起動時刻が変わらないので読み直さない。
/// 状態を持つので、サンプリングのキューからのみ呼ぶ。
public final class LaunchPWDCache {
    private struct Cached {
        let startTime: ProcessStartTime
        /// nilは読めなかったことを表す。読めなかったものも覚えて、毎回読み直さない。
        let pwd: String?
    }

    private let readStartTimes: () -> [pid_t: ProcessStartTime]?
    private let readPWD: (pid_t) -> String?
    private var cache: [pid_t: Cached] = [:]
    private var pwds: [pid_t: String] = [:]

    public init(readStartTimes: @escaping () -> [pid_t: ProcessStartTime]?, readPWD: @escaping (pid_t) -> String?) {
        self.readStartTimes = readStartTimes
        self.readPWD = readPWD
    }

    public static func live() -> LaunchPWDCache {
        let reader = ProcArgsReader()
        return LaunchPWDCache(
            readStartTimes: { ProcessStartTimeReader.readAll() },
            readPWD: { reader.readLaunchEnvironment(pid: $0)?.workingDirectoryAtLaunch }
        )
    }

    /// テストで、消えたプロセスを捨てたことを確かめるためだけに使う。
    var cachedCount: Int { cache.count }

    /// 新しく現れたプロセスと、同じPIDで起動時刻が変わったプロセスだけを読み、pidsにないものは捨てる。
    /// 起動時刻を読めなかった回は、キャッシュを変えずに前回の結果を返す。
    public func refresh(pids: [pid_t]) -> LaunchPWDRefresh {
        guard let startTimes = readStartTimes() else { return LaunchPWDRefresh(pwds: pwds, changed: false) }

        var changed = false
        let alive = Set(pids.filter { startTimes[$0] != nil })
        for pid in cache.keys where !alive.contains(pid) {
            cache[pid] = nil
            if pwds.removeValue(forKey: pid) != nil { changed = true }
        }
        for pid in alive {
            let startTime = startTimes[pid]!
            if let cached = cache[pid], cached.startTime == startTime { continue }
            let pwd = readPWD(pid)
            cache[pid] = Cached(startTime: startTime, pwd: pwd)
            if pwds[pid] != pwd {
                pwds[pid] = pwd
                changed = true
            }
        }
        return LaunchPWDRefresh(pwds: pwds, changed: changed)
    }
}
