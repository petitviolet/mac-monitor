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
    static let noValue = "なし"
    /// 環境変数が1つも返らなかったときに使う。権限がない場合と、env -iで空にして起動した場合を区別できない。
    static let unreadable = "読み取れません"
    static let exited = "プロセスは終了しました"
    static let measuring = "計測中"

    static func date(_ date: Date) -> String {
        date.formatted(date: .numeric, time: .standard)
    }
}

/// 詳細ペインは中身で幅が変わると一覧ごと揺れるので、固定の幅にする。
/// 列の幅はGridが中身から決めるので、ここの2つの値はペインの幅を求めるための想定値で、実際の列には当てていない。
/// どちらも13ptのシステムフォントでの実測に基づくので、フォントを変えたら測り直す。
enum DetailPaneLayout {
    /// 想定する最長ラベル「コマンドを実行した場所(INIT_CWD)」の幅。実測206pt。
    private static let assumedLongestLabelWidth: CGFloat = 210
    /// /System/Library/CoreServices/launchservicesd(実測281pt)ほどのパスが1行で読める値の幅。長いパスは折り返す。
    private static let assumedValueWidth: CGFloat = 300
    private static let columnSpacing: CGFloat = 12
    static let padding: CGFloat = 12
    static let width = padding * 2 + assumedLongestLabelWidth + columnSpacing + assumedValueWidth
}

/// 一覧と詳細ペインを並べる2つのタブで共通の寸法。
/// HSplitViewはツールバーを含むウィンドウ全体の高さで作られ、区切り線がツールバーの上まで描かれるので、
/// 両タブともHStackとDividerで並べる。
enum SplitLayout {
    static let dividerWidth: CGFloat = 1
    static let killColumnWidth: CGFloat = 24
}

/// 表の見出しに並べ替えの矢印を出すための比較器。どの見出しが押されたかをkeyで伝えるだけで、
/// 実際の並べ替えはCoreの関数(ProcessRanking、AppRanking)で行うので、compareは常に同じとみなす。
struct HeaderSort<Compared, Key: Hashable>: SortComparator, Hashable {
    let key: Key
    var order: SortOrder

    func compare(_ lhs: Compared, _ rhs: Compared) -> ComparisonResult {
        .orderedSame
    }
}
