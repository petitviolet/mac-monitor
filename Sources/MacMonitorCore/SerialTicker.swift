import Foundation

/// 1本の直列キューで処理を繰り返す。処理が間隔より長引いたときは、完了を待ってからすぐ次を始める。
public final class SerialTicker {
    /// asyncAfterの既定の許容幅では、2秒の間隔が実測で約2.18秒に延びた。
    private static let leeway = DispatchTimeInterval.milliseconds(50)

    private let interval: TimeInterval
    private let work: () -> Void
    private let queue = DispatchQueue(label: "net.petitviolet.MacMonitor.sampling", qos: .utility)
    private var timer: DispatchSourceTimer?

    public init(interval: TimeInterval, work: @escaping () -> Void) {
        self.interval = interval
        self.work = work
    }

    /// 前のタイマーを止めてから作り直すので、startを繰り返しても動くタイマーは1つだけになる。
    public func start() {
        queue.async {
            self.timer?.cancel()
            let timer = DispatchSource.makeTimerSource(queue: self.queue)
            timer.schedule(deadline: .now(), repeating: self.interval, leeway: Self.leeway)
            timer.setEventHandler { [work = self.work] in work() }
            timer.resume()
            self.timer = timer
        }
    }

    public func stop() {
        queue.async {
            self.timer?.cancel()
            self.timer = nil
        }
    }

    /// サンプリングと同じキューで処理を実行する。
    public func perform(_ block: @escaping () -> Void) {
        queue.async(execute: block)
    }
}
