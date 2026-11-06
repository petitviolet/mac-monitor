import Foundation

public enum ProcessSearch {
    /// 前後の空白と改行を除いた検索語を返す。空になるときは絞り込まないので、nilを返す。
    public static func normalized(_ query: String) -> String? {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return needle.isEmpty ? nil : needle
    }

    public static func isActive(_ query: String) -> Bool {
        normalized(query) != nil
    }

    /// needleはnormalizedで正規化した検索語。名前か起動時のPWDに、大文字と小文字を区別せず部分一致すれば残す。
    public static func matches(name: String, launchPWD: String?, needle: String) -> Bool {
        if name.range(of: needle, options: .caseInsensitive) != nil { return true }
        guard let launchPWD else { return false }
        return launchPWD.range(of: needle, options: .caseInsensitive) != nil
    }
}
