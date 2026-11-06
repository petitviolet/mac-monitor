import Foundation
import MacMonitorCore

/// メインスレッドの外で値を集める。プロパティはすべてSerialTickerのキューの上でだけ触る。
final class SamplingPipeline {
    /// nilの項目は、その回に変化がないことを表す。
    struct Update {
        var snapshot: SystemSnapshot? = nil
        var apps: [RunningAppInfo]? = nil
        /// アプリの本体と子孫の合算。appsと同じ回のpsの結果から計算する。
        var appAggregates: [pid_t: ProcessAggregate]? = nil
        /// 起動時のPWD。検索中で、前回から変わったときだけ渡す。
        var launchPWDs: [pid_t: String]? = nil
        var detail: ProcessDetailResult? = nil
    }

    private static let interval: TimeInterval = 5

    private let sampler = SystemSampler()
    private let appReader = RunningAppReader()
    private let pwdCache = LaunchPWDCache.live()
    private var searchActive = false
    private let deliver: @Sendable (Update) -> Void
    private var ticker: SerialTicker?
    private var selectedPID: pid_t?
    private var latestProcesses: [ProcessEntry] = []

    init(deliver: @escaping @Sendable (Update) -> Void) {
        self.deliver = deliver
    }

    func start() {
        let ticker = SerialTicker(interval: Self.interval) { [unowned self] in
            self.tick()
        }
        self.ticker = ticker
        ticker.start()
    }

    /// 選択を変えたら次の周期を待たずに詳細を読む。
    func select(pid: pid_t?) {
        ticker?.perform { [unowned self] in
            self.selectedPID = pid
            guard let detail = self.readSelectedDetail() else { return }
            self.deliver(Update(detail: detail))
        }
    }

    /// 検索を始めたら次の周期を待たずにPWDを読み、変化の有無によらず渡す。止めてもキャッシュは捨てない。
    func setSearchActive(_ active: Bool) {
        ticker?.perform { [unowned self] in
            self.searchActive = active
            guard active else { return }
            let refreshed = self.pwdCache.refresh(pids: self.latestProcesses.map(\.pid))
            self.deliver(Update(launchPWDs: refreshed.pwds))
        }
    }

    private func tick() {
        let snapshot = sampler.sample()
        latestProcesses = snapshot.processes ?? []
        let apps = appReader.read()
        let aggregates = ProcessTree.aggregates(rootPIDs: apps.map(\.pid), entries: snapshot.processes ?? [])
        let refreshed = searchActive ? pwdCache.refresh(pids: latestProcesses.map(\.pid)) : nil
        deliver(Update(
            snapshot: snapshot,
            apps: apps,
            appAggregates: aggregates,
            launchPWDs: refreshed.flatMap { $0.changed ? $0.pwds : nil },
            detail: readSelectedDetail()
        ))
    }

    private func readSelectedDetail() -> ProcessDetailResult? {
        guard let selectedPID else { return nil }
        let entry = latestProcesses.first { $0.pid == selectedPID }
        return ProcessDetailResult(pid: selectedPID, detail: ProcessDetailReader.read(pid: selectedPID, psEntry: entry))
    }
}
