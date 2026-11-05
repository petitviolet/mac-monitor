import Darwin

public struct CPUTicks: Equatable, Sendable {
    public let user: UInt32
    public let system: UInt32
    public let idle: UInt32
    public let nice: UInt32

    public init(user: UInt32, system: UInt32, idle: UInt32, nice: UInt32) {
        self.user = user
        self.system = system
        self.idle = idle
        self.nice = nice
    }
}

/// 値はすべて0から1の割合。
public struct CPUUsage: Equatable, Sendable {
    public let overall: Double
    public let perCore: [Double]

    public static func between(previous: [CPUTicks], current: [CPUTicks]) -> CPUUsage? {
        guard !current.isEmpty, previous.count == current.count else { return nil }

        var busyTotal: UInt64 = 0
        var allTotal: UInt64 = 0
        var perCore: [Double] = []
        for (before, after) in zip(previous, current) {
            // カウンタはUInt32で一周するので、ラップアラウンド減算で差を取る。
            let busy = UInt64(after.user &- before.user)
                + UInt64(after.system &- before.system)
                + UInt64(after.nice &- before.nice)
            let all = busy + UInt64(after.idle &- before.idle)
            busyTotal += busy
            allTotal += all
            perCore.append(fraction(busy, of: all))
        }
        return CPUUsage(overall: fraction(busyTotal, of: allTotal), perCore: perCore)
    }

    private static func fraction(_ part: UInt64, of whole: UInt64) -> Double {
        whole == 0 ? 0 : Double(part) / Double(whole)
    }
}

enum CPUTicksReader {
    private static let host = mach_host_self()

    static func read() -> [CPUTicks]? {
        var coreCount: natural_t = 0
        var info: processor_info_array_t?
        var infoCount: mach_msg_type_number_t = 0
        let result = host_processor_info(host, PROCESSOR_CPU_LOAD_INFO, &coreCount, &info, &infoCount)
        guard result == KERN_SUCCESS, let info else { return nil }
        defer {
            vm_deallocate(
                mach_task_self_,
                vm_address_t(bitPattern: info),
                vm_size_t(infoCount) * vm_size_t(MemoryLayout<integer_t>.stride)
            )
        }

        let stride = Int(CPU_STATE_MAX)
        return (0..<Int(coreCount)).map { core in
            func ticks(_ state: Int32) -> UInt32 {
                UInt32(bitPattern: info[core * stride + Int(state)])
            }
            return CPUTicks(
                user: ticks(CPU_STATE_USER),
                system: ticks(CPU_STATE_SYSTEM),
                idle: ticks(CPU_STATE_IDLE),
                nice: ticks(CPU_STATE_NICE)
            )
        }
    }
}
