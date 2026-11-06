import AppKit
import MacMonitorCore
import SwiftUI

enum SceneID {
    static let mainWindow = "main"
}

enum MainWindow {
    static let title = "MacMonitor"

    /// NSApp.activate()は他のアプリが譲らないと前面に出ず、パネルから開いても背面のままだった。
    @MainActor
    static func activateApp() {
        NSApp.activate(ignoringOtherApps: true)
    }

    @MainActor
    static func makeKey() {
        NSApp.windows.first { $0.title == title }?.makeKeyAndOrderFront(nil)
    }

    @MainActor
    static var isVisible: Bool {
        NSApp.windows.contains { $0.title == title && $0.isVisible }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    /// SwiftUIは閉じたまま終了したウィンドウを次の起動で開かない。openWindowはViewの中でしか使えないので、
    /// 自分のバンドルを開き直して、Dockアイコンのクリックと同じ再表示のイベントを受け取る。
    func applicationDidFinishLaunching(_ notification: Notification) {
        DispatchQueue.main.async {
            // swift runではバンドルがなく、開き直す先がない。
            guard !MainWindow.isVisible, Bundle.main.bundleURL.pathExtension == "app" else { return }
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.activates = false
            NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: configuration)
        }
    }

    /// ウィンドウを閉じてもメニューバーに常駐し続ける。
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}

@main
struct MacMonitorApp: App {
    /// 既定の幅はウィンドウの最小幅と同じにする。一覧を最小幅にして詳細ペインを並べた幅。
    private static let defaultWindowSize = CGSize(width: ContentView.minimumWidth, height: 660)

    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    /// Appの構造体はSwiftUIが複数回作ることがあるので、サンプリングを持つモデルを型に1つだけ置く。
    private static let model = AppModel()

    var body: some Scene {
        Window(MainWindow.title, id: SceneID.mainWindow) {
            ContentView(model: Self.model)
        }
        .defaultSize(Self.defaultWindowSize)

        MenuBarExtra {
            MenuBarContent(model: Self.model)
        } label: {
            Glyph.menubar.image
            Text(Self.model.menuBarLabel)
        }
        .menuBarExtraStyle(.window)
    }
}
