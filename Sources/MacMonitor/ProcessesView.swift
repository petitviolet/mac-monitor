import MacMonitorCore
import SwiftUI

struct ProcessesView: View {
    private static let listMinimumWidth: CGFloat = 590
    private static let detailMinimumWidth: CGFloat = 300
    private static let listPadding: CGFloat = 8
    /// 一覧の両側の余白と、一覧と詳細の最小幅を合わせた幅。ウィンドウの最小幅に使う。
    static let minimumWidth = listMinimumWidth + listPadding * 2 + detailMinimumWidth
    private static let killColumnWidth: CGFloat = 24

    @Bindable var model: AppModel

    var body: some View {
        HSplitView {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 16) {
                    Picker("並び順", selection: $model.sortKey) {
                        Text("CPU順").tag(ProcessSortKey.cpu)
                        Text("メモリ順").tag(ProcessSortKey.memory)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .fixedSize()
                    Toggle("端末から起動のみ", isOn: $model.terminalOnly)
                        .toggleStyle(.checkbox)
                }
                processList
                Text("CPUとメモリはpsの値です。CPUは直近最大1分の減衰平均、メモリはRSSです。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(Self.listPadding)
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
            TableColumn("名前") { entry in
                HStack(spacing: 6) {
                    Text(entry.name)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    if model.isLaunchedFromTerminal(entry.pid) {
                        TerminalTag()
                    }
                }
            }
            .width(min: 120)
            TableColumn("PID") { Text(String($0.pid)).monospacedDigit() }
                .width(56)
            TableColumn("CPU") { Text(Formatting.cpuPercent($0.cpuPercent)).monospacedDigit() }
                .width(60)
            TableColumn("メモリ") { Text(Formatting.bytes($0.rssBytes)).monospacedDigit() }
                .width(76)
            TableColumn("ユーザー", value: \.user)
                .width(96)
            TableColumn("") { entry in
                KillRowButton(name: entry.name) { model.requestKill(pid: entry.pid, listedName: entry.name) }
            }
            .width(Self.killColumnWidth)
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

    /// 引数ごと読めないときは権限の問題なので「権限なし」とする。引数は読めて環境変数だけが空のときは、
    /// 原因を区別できないので「読み取れません」とする。
    @ViewBuilder
    private func launchEnvironmentRows(_ detail: ProcessDetail) -> some View {
        if detail.arguments == nil {
            DetailRow(label: "起動時のPWD", value: DetailText.denied)
        } else if let environment = detail.launchEnvironment {
            DetailRow(label: "起動時のPWD", value: environment.workingDirectoryAtLaunch ?? DetailText.noValue)
            // INIT_CWDはnpm、yarn、pnpmがスクリプトを実行するときにだけ設定するので、ないときは行ごと出さない。
            if let commandDirectory = environment.commandDirectory {
                DetailRow(label: "コマンドを実行した場所(INIT_CWD)", value: commandDirectory)
            }
        } else {
            DetailRow(label: "起動時のPWD", value: DetailText.unreadable)
            DetailRow(label: "コマンドを実行した場所(INIT_CWD)", value: DetailText.unreadable)
        }
    }

    private func content(_ detail: ProcessDetail) -> some View {
        let entry = model.snapshot?.processes?.first { $0.pid == detail.pid }
        let name = entry?.name ?? String(detail.pid)
        return ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text(name).font(.title3).bold().textSelection(.enabled)
                    Spacer()
                    KillRowButton(name: name) { model.requestKill(pid: detail.pid, listedName: name) }
                }
                Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 6) {
                    DetailRow(label: "CPU", value: entry.map { Formatting.cpuPercent($0.cpuPercent) } ?? DetailText.unknown)
                    DetailRow(label: "メモリ(RSS)", value: entry.map { Formatting.bytes($0.rssBytes) } ?? DetailText.unknown)
                    DetailRow(label: "PID", value: String(detail.pid))
                    DetailRow(label: "親PID", value: String(detail.parentPID))
                    DetailRow(label: "ユーザー", value: detail.user ?? DetailText.denied)
                    DetailRow(label: "端末", value: entry.map { $0.tty ?? DetailText.noValue } ?? DetailText.unknown)
                    DetailRow(label: "現在の作業ディレクトリ", value: detail.workingDirectory ?? DetailText.denied)
                    launchEnvironmentRows(detail)
                    DetailRow(label: "実行パス", value: detail.path ?? DetailText.denied)
                    DetailRow(label: "引数", value: detail.arguments?.joined(separator: " ") ?? DetailText.denied)
                    DetailRow(label: "起動時刻", value: detail.startTime.map(DetailText.date) ?? DetailText.denied)
                    DetailRow(label: "スレッド数", value: detail.threadCount.map { String($0) } ?? DetailText.denied)
                    DetailRow(label: "CPU時間", value: detail.cpuTimeSeconds.map { Formatting.cpuTime(seconds: $0) } ?? DetailText.denied)
                    DetailRow(label: "phys_footprint", value: detail.footprintBytes.map(Formatting.bytes) ?? DetailText.denied)
                }
                Button("シグナルを送る…") { model.requestKill(pid: detail.pid, listedName: name) }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// 端末から起動したことを文字で示す。枠線と文字は前景色の階層に従うので、ライトとダークの両方で読める。
private struct TerminalTag: View {
    var body: some View {
        Text("端末")
            .font(.caption2)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .overlay(Capsule().strokeBorder(.secondary, lineWidth: 1))
            .fixedSize()
            .accessibilityLabel("端末から起動")
    }
}
