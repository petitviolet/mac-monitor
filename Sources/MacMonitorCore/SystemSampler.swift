import Foundation

public struct SystemSnapshot: Sendable {
    /// nilは取得に失敗したことを表す。
    public let processes: [ProcessEntry]?
    /// 端末から起動したと判定したプロセス。
    public let terminalLaunchedPIDs: Set<pid_t>
    /// 差分で求める値なので、初回はnilになる。
    public let cpu: CPUUsage?
    public let memory: MemoryUsage?
    public let disk: DiskUsage?
    /// 差分で求める値なので、初回はnilになる。
    public let network: NetworkRate?
}

/// 前回のカウンタを持つので、同じキューからのみ呼ぶ。
public final class SystemSampler {
    private static let nanosecondsPerSecond = 1_000_000_000.0

    private var previousTicks: [CPUTicks]?
    private var previousCounters: [UInt16: NetworkCounters]?
    private var previousCountersTime: UInt64?

    public init() {}

    public func sample() -> SystemSnapshot {
        let processes = PSRunner.run()
        return SystemSnapshot(
            processes: processes,
            terminalLaunchedPIDs: TerminalLaunch.pids(in: processes ?? []),
            cpu: sampleCPU(),
            memory: MemoryUsageReader.read(),
            disk: DiskUsageReader.read(),
            network: sampleNetwork()
        )
    }

    private func sampleCPU() -> CPUUsage? {
        let current = CPUTicksReader.read()
        defer { previousTicks = current }
        guard let current, let previousTicks else { return nil }
        return CPUUsage.between(previous: previousTicks, current: current)
    }

    private func sampleNetwork() -> NetworkRate? {
        let current = NetworkCountersReader.read()
        // スリープ中も進む時計で測り、復帰直後の速度が実際より高く出ないようにする。
        let now = clock_gettime_nsec_np(CLOCK_MONOTONIC)
        defer {
            previousCounters = current
            previousCountersTime = now
        }
        guard let current, let previousCounters, let previousCountersTime else { return nil }
        let elapsed = Double(now - previousCountersTime) / Self.nanosecondsPerSecond
        return NetworkRate.between(previous: previousCounters, current: current, elapsedSeconds: elapsed)
    }
}
