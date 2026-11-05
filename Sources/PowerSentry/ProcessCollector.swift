import Foundation
import Darwin

final class ProcessCollector {
    private struct CPUState {
        let cpuNanoseconds: UInt64
        let sampledAt: Date
    }

    private var previous: [Int32: CPUState] = [:]

    func sample(now: Date = Date()) -> [ProcessSnapshot] {
        let capacity = 8192
        var pids = [pid_t](repeating: 0, count: capacity)
        let count = pids.withUnsafeMutableBytes { raw in
            proc_listallpids(raw.baseAddress, Int32(raw.count))
        }
        let validCount = min(max(0, Int(count)), pids.count)
        var current: [Int32: CPUState] = [:]
        var results: [ProcessSnapshot] = []
        let ownPID = getpid()

        for rawPID in pids.prefix(validCount) {
            let pid = Int32(rawPID)
            guard pid > 1, pid != ownPID else { continue }

            guard let taskInfo = readTaskInfo(pid: pid) else { continue }
            let cpuTime = taskInfo.pti_total_user &+ taskInfo.pti_total_system
            current[pid] = CPUState(cpuNanoseconds: cpuTime, sampledAt: now)

            guard let old = previous[pid] else { continue }
            let elapsed = now.timeIntervalSince(old.sampledAt)
            guard elapsed > 0, cpuTime >= old.cpuNanoseconds else { continue }
            let delta = Double(cpuTime - old.cpuNanoseconds) / 1_000_000_000.0
            let cpuPercent = min(1600, max(0, delta / elapsed * 100.0))

            let path = executablePath(pid: pid)
            let startTime = processStartTime(pid: pid) ?? now.timeIntervalSince1970
            let identity = ProcessIdentity(pid: pid, startTime: startTime, executablePath: path)
            let name = URL(fileURLWithPath: path).lastPathComponent.isEmpty
                ? "pid-\(pid)"
                : URL(fileURLWithPath: path).lastPathComponent

            results.append(ProcessSnapshot(
                identity: identity,
                name: name,
                cpuPercent: cpuPercent,
                memoryBytes: taskInfo.pti_resident_size
            ))
        }

        previous = current
        return results.sorted { $0.cpuPercent > $1.cpuPercent }
    }

    func currentCPUPercent(pid: Int32, interval: TimeInterval = 1.2) -> Double? {
        guard let first = readTaskInfo(pid: pid) else { return nil }
        Thread.sleep(forTimeInterval: interval)
        guard let second = readTaskInfo(pid: pid) else { return nil }
        let before = first.pti_total_user &+ first.pti_total_system
        let after = second.pti_total_user &+ second.pti_total_system
        guard after >= before else { return nil }
        return Double(after - before) / 1_000_000_000.0 / interval * 100.0
    }

    private func readTaskInfo(pid: Int32) -> proc_taskinfo? {
        var info = proc_taskinfo()
        let size = Int32(MemoryLayout<proc_taskinfo>.size)
        let result = proc_pidinfo(pid, PROC_PIDTASKINFO, 0, &info, size)
        return result == size ? info : nil
    }

    func currentIdentity(pid: Int32) -> ProcessIdentity? {
        let path = executablePath(pid: pid)
        guard path != "unknown", let start = processStartTime(pid: pid) else { return nil }
        return ProcessIdentity(pid: pid, startTime: start, executablePath: path)
    }

    private func executablePath(pid: Int32) -> String {
        var buffer = [CChar](repeating: 0, count: 4096)
        let length = proc_pidpath(pid, &buffer, UInt32(buffer.count))
        guard length > 0 else { return "unknown" }
        return String(cString: buffer)
    }

    private func processStartTime(pid: Int32) -> Double? {
        var info = proc_bsdinfo()
        let size = Int32(MemoryLayout<proc_bsdinfo>.size)
        let result = proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size)
        guard result == size else { return nil }
        return Double(info.pbi_start_tvsec) + Double(info.pbi_start_tvusec) / 1_000_000.0
    }
}
