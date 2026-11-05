import Foundation

final class NetworkCollector {
    private struct Counter {
        let received: UInt64
        let sent: UInt64
        let timestamp: Date
        let name: String
    }

    private var previous: [Int32: Counter] = [:]

    func sample(now: Date = Date()) -> [NetworkSnapshot] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/nettop")
        process.arguments = ["-P", "-L", "1", "-n", "-J", "bytes_in,bytes_out"]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
        } catch {
            return []
        }

        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard let text = String(data: data, encoding: .utf8) else { return [] }

        var current: [Int32: Counter] = [:]
        var results: [NetworkSnapshot] = []

        for line in text.split(whereSeparator: \.isNewline) {
            let fields = line.split(separator: ",", omittingEmptySubsequences: false)
            guard fields.count >= 3 else { continue }
            let label = fields[0].trimmingCharacters(in: .whitespaces)
            guard let dot = label.lastIndex(of: "."),
                  let pid = Int32(label[label.index(after: dot)...]),
                  let received = UInt64(fields[1].trimmingCharacters(in: .whitespaces)),
                  let sent = UInt64(fields[2].trimmingCharacters(in: .whitespaces)) else {
                continue
            }

            let name = String(label[..<dot]).trimmingCharacters(in: .whitespaces)
            let counter = Counter(received: received, sent: sent, timestamp: now, name: name)
            current[pid] = counter

            guard let old = previous[pid] else { continue }
            let elapsed = max(0.1, now.timeIntervalSince(old.timestamp))
            let receivedDelta = received >= old.received ? received - old.received : received
            let sentDelta = sent >= old.sent ? sent - old.sent : sent
            if receivedDelta > 0 || sentDelta > 0 {
                results.append(NetworkSnapshot(
                    sampledAt: now,
                    pid: pid,
                    processName: name,
                    downloadBytesPerSecond: Double(receivedDelta) / elapsed,
                    uploadBytesPerSecond: Double(sentDelta) / elapsed,
                    totalDownloadedBytes: received,
                    totalUploadedBytes: sent
                ))
            }
        }

        previous = current
        return results.sorted {
            $0.downloadBytesPerSecond + $0.uploadBytesPerSecond >
            $1.downloadBytesPerSecond + $1.uploadBytesPerSecond
        }
    }
}
