import Foundation

final class PowerEventCollector {
    private var lastEventLine = ""

    func sample(now: Date = Date()) -> PowerStateSnapshot {
        let log = run("/bin/zsh", arguments: ["-lc", "/usr/bin/pmset -g log | tail -n 1200"])
        let assertionText = run("/usr/bin/pmset", arguments: ["-g", "assertions"])
        let lines = log.split(whereSeparator: \.isNewline).map(String.init)

        let interesting = lines.filter { line in
            line.contains("DarkWake") ||
            line.contains("Wake from") ||
            line.contains("Entering Sleep state") ||
            line.contains("Clamshell Sleep") ||
            line.contains("Maintenance Sleep")
        }

        let recentEvents = interesting.suffix(120).compactMap(parseEvent)
        let cutoff = now.addingTimeInterval(-600)
        let darkWakeCount = recentEvents.filter { $0.kind == "DarkWake" && $0.timestamp >= cutoff }.count

        let assertions = assertionText.split(whereSeparator: \.isNewline).compactMap(parseAssertion)
        lastEventLine = interesting.last ?? lastEventLine

        return PowerStateSnapshot(
            timestamp: now,
            recentEvents: Array(recentEvents.suffix(60)),
            darkWakeCount10m: darkWakeCount,
            assertions: assertions
        )
    }

    private func parseEvent(_ line: String) -> PowerEvent? {
        guard line.count >= 19 else { return nil }
        let stamp = String(line.prefix(19))
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        guard let date = formatter.date(from: stamp) else { return nil }

        let kind: String
        if line.contains("DarkWake") {
            kind = "DarkWake"
        } else if line.contains("Maintenance Sleep") {
            kind = "MaintenanceSleep"
        } else if line.contains("Clamshell Sleep") || line.contains("Entering Sleep state") {
            kind = "Sleep"
        } else if line.contains("Wake from") {
            kind = "Wake"
        } else {
            return nil
        }
        return PowerEvent(timestamp: date, kind: kind, detail: line)
    }

    private func parseAssertion(_ line: Substring) -> PowerAssertion? {
        let text = String(line)
        guard let regex = try? NSRegularExpression(pattern: #"pid\s+(\d+)\(([^)]+)\)"#),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let pidRange = Range(match.range(at: 1), in: text),
              let nameRange = Range(match.range(at: 2), in: text),
              let pid = Int32(text[pidRange]) else {
            return nil
        }
        guard let namedRange = text.range(of: #"named:\s*"[^"]+""#, options: .regularExpression) else {
            return nil
        }
        let named = String(text[namedRange])
        let name = named
            .replacingOccurrences(of: #"^named:\s*""#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #""$"#, with: "", options: .regularExpression)
        let assertionType = text.contains("PreventUserIdleSystemSleep")
            ? "PreventUserIdleSystemSleep"
            : (text.contains("PreventSystemSleep") ? "PreventSystemSleep" : "Other")
        return PowerAssertion(pid: pid, processName: String(text[nameRange]), assertionType: assertionType, name: name)
    }

    private func run(_ path: String, arguments: [String]) -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            return String(data: data, encoding: .utf8) ?? ""
        } catch {
            return ""
        }
    }
}
