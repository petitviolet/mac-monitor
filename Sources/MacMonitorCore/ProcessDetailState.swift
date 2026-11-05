import Darwin

public struct ProcessDetailResult: Equatable, Sendable {
    public let pid: pid_t
    /// nilはプロセスが存在しないことを表す。
    public let detail: ProcessDetail?

    public init(pid: pid_t, detail: ProcessDetail?) {
        self.pid = pid
        self.detail = detail
    }
}

public enum ProcessDetailState: Equatable, Sendable {
    case noSelection
    case loading
    case exited
    case loaded(ProcessDetail)

    public static func selecting(_ pid: pid_t?) -> ProcessDetailState {
        pid == nil ? .noSelection : .loading
    }

    /// 詳細は別のキューで読むので、選択を切り替えた後に前の選択の結果が届くことがある。それは捨てる。
    public func applying(_ result: ProcessDetailResult, selectedPID: pid_t?) -> ProcessDetailState {
        guard result.pid == selectedPID else { return self }
        return result.detail.map(ProcessDetailState.loaded) ?? .exited
    }
}
