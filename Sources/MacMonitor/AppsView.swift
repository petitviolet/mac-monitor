import MacMonitorCore
import SwiftUI

struct AppsView: View {
    private static let listMinimumWidth: CGFloat = 280
    private static let detailMinimumWidth: CGFloat = 380
    private static let rowIconSize: CGFloat = 20

    @Bindable var model: AppModel

    var body: some View {
        HSplitView {
            List(model.apps, selection: $model.selectedAppPID) { app in
                HStack {
                    AppIcon(image: model.icon(for: app), size: Self.rowIconSize)
                    Text(app.name)
                }
                .contextMenu {
                    Button("シグナルを送る…") { model.requestKill(app: app) }
                }
            }
            .frame(minWidth: Self.listMinimumWidth, maxWidth: .infinity, maxHeight: .infinity)

            AppDetailPane(model: model)
                .frame(minWidth: Self.detailMinimumWidth, maxWidth: .infinity, maxHeight: .infinity)
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
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
