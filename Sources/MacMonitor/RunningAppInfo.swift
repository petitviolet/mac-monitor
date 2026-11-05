import AppKit
import Foundation

/// 同じPIDが別のアプリに再利用されても取り違えないように、起動時刻も含めて識別する。
struct RunningAppKey: Hashable {
    let pid: pid_t
    let launchDate: Date?
}

struct RunningAppInfo: Identifiable {
    let key: RunningAppKey
    let name: String
    let bundleID: String?
    let path: String?
    let version: String?
    let architecture: String?

    var id: pid_t { key.pid }
    var pid: pid_t { key.pid }
    var launchDate: Date? { key.launchDate }
}

/// バージョンの読み取りはファイルを読むので、起動中のアプリごとに1回だけにする。キャッシュを持つので同じキューからのみ呼ぶ。
final class RunningAppReader {
    private static let versionKey = "CFBundleShortVersionString"
    private static let unknownName = "名前なし"

    private var versions: [RunningAppKey: String?] = [:]

    func read() -> [RunningAppInfo] {
        let apps = NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular }
            .map { app -> RunningAppInfo in
                let key = RunningAppKey(pid: app.processIdentifier, launchDate: app.launchDate)
                return RunningAppInfo(
                    key: key,
                    name: app.localizedName ?? Self.unknownName,
                    bundleID: app.bundleIdentifier,
                    path: app.bundleURL?.path,
                    version: version(of: app, key: key),
                    architecture: Self.architectureName(app.executableArchitecture)
                )
            }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }

        let liveKeys = Set(apps.map(\.key))
        versions = versions.filter { liveKeys.contains($0.key) }
        return apps
    }

    private func version(of app: NSRunningApplication, key: RunningAppKey) -> String? {
        if let cached = versions[key] { return cached }
        let version = app.bundleURL.flatMap { Bundle(url: $0)?.infoDictionary?[Self.versionKey] as? String }
        versions[key] = .some(version)
        return version
    }

    private static func architectureName(_ architecture: Int) -> String? {
        switch architecture {
        case NSBundleExecutableArchitectureARM64: return "arm64"
        case NSBundleExecutableArchitectureX86_64: return "x86_64"
        default: return nil
        }
    }
}
