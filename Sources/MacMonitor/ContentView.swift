import MacMonitorCore
import SwiftUI

private enum MainTab: String {
    case resources
    case processes
    case apps
}

struct ContentView: View {
    static let minimumWidth = max(ProcessesView.minimumWidth, AppsView.minimumWidth)
    static let minimumHeight: CGFloat = 560
    private static let tabGlyphSize: CGFloat = 15
    private static let tabCornerRadius: CGFloat = 6

    let model: AppModel
    @AppStorage("selectedTab") private var selectedTab = MainTab.resources

    var body: some View {
        VStack(spacing: 0) {
            if let message = model.killMessage {
                KillResultBanner(message: message) { model.killMessage = nil }
            }
            selectedContent
        }
        .frame(minWidth: Self.minimumWidth, minHeight: Self.minimumHeight)
        .toolbar { tabBarItem }
        .modifier(KillConfirmation(model: model))
    }

    /// macOS 26ではツールバーの項目にカプセル形の背景が付き、選択中のタブの背景と二重になるので消す。
    @ToolbarContentBuilder
    private var tabBarItem: some ToolbarContent {
        if #available(macOS 26.0, *) {
            ToolbarItem(placement: .principal) { tabBar }
                .sharedBackgroundVisibility(.hidden)
        } else {
            ToolbarItem(placement: .principal) { tabBar }
        }
    }

    /// macOSのTabViewはtabItemの画像を表示せず、セグメントのPickerは文字を表示しないので、ボタンを並べて作る。
    private var tabBar: some View {
        HStack(spacing: 2) {
            tabButton(.resources, title: "リソース", glyph: .tabResources)
            tabButton(.processes, title: "プロセス", glyph: .tabProcesses)
            tabButton(.apps, title: "アプリ", glyph: .tabApps)
        }
    }

    private func tabButton(_ tab: MainTab, title: String, glyph: Glyph) -> some View {
        Button {
            selectedTab = tab
        } label: {
            HStack(spacing: 5) {
                glyph.image
                    .resizable()
                    .frame(width: Self.tabGlyphSize, height: Self.tabGlyphSize)
                Text(title)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .contentShape(Rectangle())
            .background(
                selectedTab == tab ? AnyShapeStyle(.quaternary) : AnyShapeStyle(.clear),
                in: RoundedRectangle(cornerRadius: Self.tabCornerRadius)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityAddTraits(selectedTab == tab ? .isSelected : [])
    }

    @ViewBuilder
    private var selectedContent: some View {
        switch selectedTab {
        case .resources:
            ResourcesView(model: model)
        case .processes:
            ProcessesView(model: model)
        case .apps:
            AppsView(model: model)
        }
    }
}
