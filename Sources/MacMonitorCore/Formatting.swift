import Foundation

public enum Formatting {
    private static let bytesPerUnit: UInt64 = 1024
    private static let units = ["B", "KB", "MB", "GB", "TB", "PB"]
    private static let unmeasured = "--"
    private static let secondsPerMinute = 60
    private static let secondsPerHour = 3600
    private static let centisecondsPerSecond = 100.0

    public static func bytes(_ value: UInt64) -> String {
        var scaled = Double(value)
        var unit = 0
        while scaled >= Double(bytesPerUnit), unit < units.count - 1 {
            scaled /= Double(bytesPerUnit)
            unit += 1
        }
        if unit == 0 { return "\(value) B" }
        return String(format: "%.1f %@", scaled, units[unit])
    }

    public static func rate(_ bytesPerSecond: UInt64) -> String {
        bytes(bytesPerSecond) + "/s"
    }

    public static func percent(fraction: Double) -> String {
        String(format: "%.0f%%", fraction * 100)
    }

    public static func cpuPercent(_ percent: Double) -> String {
        String(format: "%.1f%%", percent)
    }

    public static func menuBarLabel(cpuFraction: Double?, memoryFraction: Double?) -> String {
        let cpu = cpuFraction.map { percent(fraction: $0) } ?? unmeasured
        let memory = memoryFraction.map { percent(fraction: $0) } ?? unmeasured
        return "CPU \(cpu) MEM \(memory)"
    }

    /// 表示の桁で丸めてから分解する。分解してから丸めると、59.999秒が0:00:60.00になる。
    public static func cpuTime(seconds: Double) -> String {
        let centiseconds = Int((seconds * centisecondsPerSecond).rounded())
        let wholeSeconds = centiseconds / Int(centisecondsPerSecond)
        return String(
            format: "%ld:%02ld:%02ld.%02ld",
            wholeSeconds / secondsPerHour,
            wholeSeconds % secondsPerHour / secondsPerMinute,
            wholeSeconds % secondsPerMinute,
            centiseconds % Int(centisecondsPerSecond)
        )
    }
}
