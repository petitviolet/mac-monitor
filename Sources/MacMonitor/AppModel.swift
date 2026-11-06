import AppKit
import Foundation
import MacMonitorCore
import Observation

@MainActor
@Observable
final class AppModel {
    private static let topProcessCount = 30

    private(set) var snapshot: SystemSnapshot?
    private(set) var apps: [RunningAppInfo] = []
    private(set) var processDetail: ProcessDetailState = .noSelection
    var sortKey: ProcessSortKey = .cpu
    var terminalOnly = false
    var selectedAppPID: pid_t?
    var pendingKill: KillTicket?
    var killMessage: String?

    var selectedPID: pid_t? {
        didSet {
            guard selectedPID != oldValue else { return }
            processDetail = .selecting(selectedPID)
            pipeline?.select(pid: selectedPID)
        }
    }

    @ObservationIgnored private var pipeline: SamplingPipeline?
    @ObservationIgnored private var icons: [RunningAppKey: NSImage] = [:]
    @ObservationIgnored private let killer = ProcessKiller.live

    init() {
        let pipeline = SamplingPipeline { [weak self] update in
            // キューのFIFOで届くので、古い値が新しい値を上書きしない。
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    self?.apply(update)
                }
            }
        }
        self.pipeline = pipeline
        pipeline.start()
    }

    var topProcesses: [ProcessEntry] {
        ProcessRanking.top(
            snapshot?.processes ?? [],
            by: sortKey,
            limit: Self.topProcessCount,
            includedPIDs: terminalOnly ? snapshot?.terminalLaunchedPIDs ?? [] : nil
        )
    }

    func isLaunchedFromTerminal(_ pid: pid_t) -> Bool {
        snapshot?.terminalLaunchedPIDs.contains(pid) ?? false
    }

    var menuBarLabel: String {
        Formatting.menuBarLabel(cpuFraction: snapshot?.cpu?.overall, memoryFraction: snapshot?.memory?.usedFraction)
    }

    func aggregate(rootPID: pid_t) -> ProcessAggregate? {
        ProcessTree.aggregate(rootPID: rootPID, entries: snapshot?.processes ?? [])
    }

    func icon(for app: RunningAppInfo) -> NSImage? {
        icons[app.key]
    }

    func requestKill(pid: pid_t, listedName: String) {
        killMessage = nil
        switch killer.prepare(pid: pid, name: listedName) {
        case .success(let ticket):
            pendingKill = ticket
        case .failure(let outcome):
            killMessage = outcome.message
        }
    }

    /// アプリの表示名はローカライズされていてpsの名前と比べられないので、比較にはpsの名前を使う。
    func requestKill(app: RunningAppInfo) {
        let processName = snapshot?.processes?.first { $0.pid == app.pid }?.name
        requestKill(pid: app.pid, listedName: processName ?? app.name)
    }

    func confirmKill(_ ticket: KillTicket, signal: KillSignal) {
        pendingKill = nil
        killMessage = killer.send(ticket, signal: signal).message
    }

    private func apply(_ update: SamplingPipeline.Update) {
        if let snapshot = update.snapshot {
            self.snapshot = snapshot
        }
        if let apps = update.apps {
            refreshIcons(for: apps)
            self.apps = apps
        }
        if let result = update.detail {
            processDetail = processDetail.applying(result, selectedPID: selectedPID)
        }
    }

    /// NSRunningApplicationのアイコンはメインスレッドで、起動中のアプリごとに1回だけ取得する。
    private func refreshIcons(for apps: [RunningAppInfo]) {
        var refreshed: [RunningAppKey: NSImage] = [:]
        for app in apps {
            refreshed[app.key] = icons[app.key] ?? NSRunningApplication(processIdentifier: app.pid)?.icon
        }
        icons = refreshed
    }
}
