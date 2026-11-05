import Foundation
import MacMonitorCore

/// メインスレッドの外で値を集める。プロパティはすべてSerialTickerのキューの上でだけ触る。
final class SamplingPipeline {
    struct Update {
        let snapshot: SystemSnapshot?
        let apps: [RunningAppInfo]?
        let detail: ProcessDetailResult?
    }

    private static let interval: TimeInterval = 2

    private let sampler = SystemSampler()
    private let appReader = RunningAppReader()
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
            self.deliver(Update(snapshot: nil, apps: nil, detail: detail))
        }
    }

    private func tick() {
        let snapshot = sampler.sample()
        latestProcesses = snapshot.processes ?? []
        deliver(Update(snapshot: snapshot, apps: appReader.read(), detail: readSelectedDetail()))
    }

    private func readSelectedDetail() -> ProcessDetailResult? {
        guard let selectedPID else { return nil }
        let entry = latestProcesses.first { $0.pid == selectedPID }
        return ProcessDetailResult(pid: selectedPID, detail: ProcessDetailReader.read(pid: selectedPID, psEntry: entry))
    }
}
