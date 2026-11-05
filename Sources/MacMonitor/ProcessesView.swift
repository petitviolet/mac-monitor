import MacMonitorCore
import SwiftUI

struct ProcessesView: View {
    private static let listMinimumWidth: CGFloat = 500
    private static let detailMinimumWidth: CGFloat = 300

    @Bindable var model: AppModel

    var body: some View {
        HSplitView {
            VStack(alignment: .leading, spacing: 8) {
                Picker("並び順", selection: $model.sortKey) {
                    Text("CPU順").tag(ProcessSortKey.cpu)
                    Text("メモリ順").tag(ProcessSortKey.memory)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
                processList
                Text("CPUとメモリはpsの値です。CPUは直近最大1分の減衰平均、メモリはRSSです。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(8)
            .frame(minWidth: Self.listMinimumWidth, maxWidth: .infinity, maxHeight: .infinity)

            ProcessDetailPane(model: model)
                .frame(minWidth: Self.detailMinimumWidth, maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    @ViewBuilder
    private var processList: some View {
        if let snapshot = model.snapshot {
            if snapshot.processes == nil {
                DetailPlaceholder(text: "プロセス一覧を取得できませんでした")
            } else {
                processTable
            }
        } else {
            DetailPlaceholder(text: DetailText.measuring)
        }
    }

    private var processTable: some View {
        Table(model.topProcesses, selection: $model.selectedPID) {
            TableColumn("名前", value: \.name)
                .width(min: 120)
            TableColumn("PID") { Text(String($0.pid)).monospacedDigit() }
                .width(56)
            TableColumn("CPU") { Text(Formatting.cpuPercent($0.cpuPercent)).monospacedDigit() }
                .width(60)
            TableColumn("メモリ") { Text(Formatting.bytes($0.rssBytes)).monospacedDigit() }
                .width(76)
            TableColumn("ユーザー", value: \.user)
                .width(96)
        }
        .contextMenu(forSelectionType: pid_t.self) { pids in
            if let pid = pids.first, let entry = model.topProcesses.first(where: { $0.pid == pid }) {
                Button("シグナルを送る…") { model.requestKill(pid: pid, listedName: entry.name) }
            }
        }
    }
}

private struct ProcessDetailPane: View {
    let model: AppModel

    var body: some View {
        switch model.processDetail {
        case .noSelection:
            DetailPlaceholder(text: "プロセスを選択してください")
        case .loading:
            DetailPlaceholder(text: "読み込み中")
        case .exited:
            DetailPlaceholder(text: DetailText.exited)
        case .loaded(let detail):
            content(detail)
        }
    }

    private func content(_ detail: ProcessDetail) -> some View {
        let name = model.snapshot?.processes?.first { $0.pid == detail.pid }?.name ?? String(detail.pid)
        return ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text(name).font(.title3).bold().textSelection(.enabled)
                Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 6) {
                    DetailRow(label: "PID", value: String(detail.pid))
                    DetailRow(label: "親PID", value: String(detail.parentPID))
                    DetailRow(label: "ユーザー", value: detail.user ?? DetailText.denied)
                    DetailRow(label: "実行パス", value: detail.path ?? DetailText.denied)
                    DetailRow(label: "引数", value: detail.arguments?.joined(separator: " ") ?? DetailText.denied)
                    DetailRow(label: "起動時刻", value: detail.startTime.map(DetailText.date) ?? DetailText.denied)
                    DetailRow(label: "スレッド数", value: detail.threadCount.map { String($0) } ?? DetailText.denied)
                    DetailRow(label: "CPU時間", value: detail.cpuTimeSeconds.map { Formatting.cpuTime(seconds: $0) } ?? DetailText.denied)
                    DetailRow(label: "phys_footprint", value: detail.footprintBytes.map(Formatting.bytes) ?? DetailText.denied)
                    DetailRow(label: "RSS", value: detail.rssBytes.map(Formatting.bytes) ?? DetailText.denied)
                }
                Button("シグナルを送る…") { model.requestKill(pid: detail.pid, listedName: name) }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
