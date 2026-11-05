import SwiftUI

/// 詳細ペインの共通レイアウト。値は選択してコピーできる。
struct DetailRow: View {
    let label: String
    let value: String

    var body: some View {
        GridRow(alignment: .firstTextBaseline) {
            Text(label)
                .foregroundStyle(.secondary)
                .gridColumnAlignment(.trailing)
            Text(value)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct DetailPlaceholder: View {
    let text: String

    var body: some View {
        Text(text)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

enum DetailText {
    static let denied = "権限なし"
    static let unknown = "不明"
    static let exited = "プロセスは終了しました"
    static let measuring = "計測中"

    static func date(_ date: Date) -> String {
        date.formatted(date: .numeric, time: .standard)
    }
}
