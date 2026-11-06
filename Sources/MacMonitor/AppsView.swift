import MacMonitorCore
import SwiftUI

struct AppsView: View {
    private static let nameColumnMinimumWidth: CGFloat = 120
    private static let cpuColumnWidth: CGFloat = 60
    private static let memoryColumnWidth: CGFloat = 76
    /// 列の間隔、行の余白、スクロールバーのために見込んだ余裕で、実測した値はない。
    private static let tableChromeAllowance: CGFloat = 80
    private static let listMinimumWidth = nameColumnMinimumWidth + cpuColumnWidth + memoryColumnWidth
        + SplitLayout.killColumnWidth + tableChromeAllowance
    private static let rowIconSize: CGFloat = 20
    /// 一覧の最小幅、区切り線、詳細ペインの固定幅を合わせた幅。ウィンドウの最小幅に使う。
    static let minimumWidth = listMinimumWidth + SplitLayout.dividerWidth + DetailPaneLayout.width

    @Bindable var model: AppModel

    var body: some View {
        HStack(spacing: 0) {
            appTable
                .frame(minWidth: Self.listMinimumWidth, maxWidth: .infinity, maxHeight: .infinity)

            Divider()

            AppDetailPane(model: model)
                .frame(width: DetailPaneLayout.width)
                .frame(maxHeight: .infinity)
        }
    }

    private typealias AppHeaderSort = HeaderSort<RunningAppInfo, AppSortKey>

    /// SwiftUIが渡す向きは使わず、押された見出しから次の並び順をCoreの規則で決める。
    private var sortOrder: Binding<[AppHeaderSort]> {
        Binding(
            get: { [AppHeaderSort(key: model.appSortOrder.key, order: model.appSortOrder.ascending ? .forward : .reverse)] },
            set: { newValue in
                guard let clicked = newValue.first?.key else { return }
                model.appSortOrder = model.appSortOrder.afterHeaderClick(clicked)
            }
        )
    }

    /// CPUとメモリは詳細と同じく本体と子孫の合算。
    private var appTable: some View {
        Table(model.sortedApps, selection: $model.selectedAppPID, sortOrder: sortOrder) {
            TableColumn("名前", sortUsing: AppHeaderSort(key: .name, order: .forward)) { app in
                HStack(spacing: 6) {
                    AppIcon(image: model.icon(for: app), size: Self.rowIconSize)
                    Text(app.name)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
            .width(min: Self.nameColumnMinimumWidth)
            TableColumn("CPU", sortUsing: AppHeaderSort(key: .cpu, order: .reverse)) { app in
                Text(model.aggregate(rootPID: app.pid).map { Formatting.cpuPercent($0.cpuPercent) } ?? DetailText.unknown)
                    .monospacedDigit()
            }
            .width(Self.cpuColumnWidth)
            TableColumn("メモリ", sortUsing: AppHeaderSort(key: .memory, order: .reverse)) { app in
                Text(model.aggregate(rootPID: app.pid).map { Formatting.bytes($0.rssBytes) } ?? DetailText.unknown)
                    .monospacedDigit()
            }
            .width(Self.memoryColumnWidth)
            TableColumn("") { app in
                KillRowButton(name: app.name) { model.requestKill(app: app) }
            }
            .width(SplitLayout.killColumnWidth)
        }
        .contextMenu(forSelectionType: pid_t.self) { pids in
            if let pid = pids.first, let app = model.apps.first(where: { $0.pid == pid }) {
                Button("シグナルを送る…") { model.requestKill(app: app) }
            }
        }
    }
}

private struct AppIcon: View {
    let image: NSImage?
    let size: CGFloat

    var body: some View {
        if let image {
            Image(nsImage: image)
                .resizable()
                .frame(width: size, height: size)
        } else {
            Color.clear.frame(width: size, height: size)
        }
    }
}

private struct AppDetailPane: View {
    private static let headerIconSize: CGFloat = 40

    let model: AppModel

    var body: some View {
        if let pid = model.selectedAppPID {
            if let app = model.apps.first(where: { $0.pid == pid }) {
                content(app)
            } else {
                DetailPlaceholder(text: DetailText.exited)
            }
        } else {
            DetailPlaceholder(text: "アプリを選択してください")
        }
    }

    private func content(_ app: RunningAppInfo) -> some View {
        let aggregate = model.aggregate(rootPID: app.pid)
        return ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    AppIcon(image: model.icon(for: app), size: Self.headerIconSize)
                    Text(app.name).font(.title3).bold().textSelection(.enabled)
                }
                Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 6) {
                    DetailRow(label: "Bundle ID", value: app.bundleID ?? DetailText.unknown)
                    DetailRow(label: "パス", value: app.path ?? DetailText.unknown)
                    DetailRow(label: "バージョン", value: app.version ?? DetailText.unknown)
                    DetailRow(label: "起動時刻", value: app.launchDate.map(DetailText.date) ?? DetailText.unknown)
                    DetailRow(label: "アーキテクチャ", value: app.architecture ?? DetailText.unknown)
                    DetailRow(label: "PID", value: String(app.pid))
                    DetailRow(label: "CPU(本体+子孫)", value: aggregate.map { Formatting.cpuPercent($0.cpuPercent) } ?? DetailText.unknown)
                    DetailRow(label: "メモリ(本体+子孫のRSS)", value: aggregate.map { Formatting.bytes($0.rssBytes) } ?? DetailText.unknown)
                    DetailRow(label: "合算したプロセス数", value: aggregate.map { String($0.processCount) } ?? DetailText.unknown)
                }
                Text("合算の対象はppidをたどれる子孫だけです。launchdの子として動くヘルパーは入りません。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button("シグナルを送る…") { model.requestKill(app: app) }
            }
            .padding(DetailPaneLayout.padding)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
