import AppKit
import SwiftUI

struct MenuBarContent: View {
    private static let gaugeDiameter: CGFloat = 72
    private static let gaugeLineWidth: CGFloat = 8
    private static let width: CGFloat = 220

    let model: AppModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 16) {
                gauge(title: "CPU", fraction: model.snapshot?.cpu?.overall)
                gauge(title: "メモリ", fraction: model.snapshot?.memory?.usedFraction)
            }
            Divider()
            Button("ウィンドウを開く") {
                MainWindow.activateApp()
                openWindow(id: SceneID.mainWindow)
                DispatchQueue.main.async { MainWindow.makeKey() }
            }
            .frame(maxWidth: .infinity)
            Button("MacMonitorを終了") {
                NSApp.terminate(nil)
            }
            .frame(maxWidth: .infinity)
        }
        .padding(14)
        .frame(width: Self.width)
    }

    private func gauge(title: String, fraction: Double?) -> some View {
        RingGauge(
            title: title,
            fraction: fraction,
            diameter: Self.gaugeDiameter,
            lineWidth: Self.gaugeLineWidth,
            valueFont: .callout
        )
    }
}
