import Foundation

struct DetectionResult {
    let baselineWatts: Double
    let baselineLearning: Bool
    let baselineSamples: [Double]
    let incidents: [Incident]
}

final class AnomalyDetector {
    private var baselineSamples: [Double]
    private var baselineWatts = 2.0

    init(initialSamples: [Double] = []) {
        self.baselineSamples = Array(initialSamples.suffix(180))
        if self.baselineSamples.count >= 30,
           let median = PowerSentryMath.median(self.baselineSamples) {
            self.baselineWatts = min(5.0, max(0.4, median))
        }
    }
    private var powerStreak = 0
    private var cpuStreaks: [String: Int] = [:]
    private var networkStreaks: [Int32: Int] = [:]
    private var lastNetworkSampleAt: [Int32: Date] = [:]
    private var lastDarkWakeIncident: Date?

    func evaluate(_ snapshot: SystemSnapshot, activeKinds: Set<String>) -> DetectionResult {
        let battery = snapshot.battery
        let maxCPU = snapshot.topProcesses.first?.cpuPercent ?? 0
        let maxNetwork = snapshot.topNetwork.first?.downloadBytesPerSecond ?? 0
        let stableForBaseline = !battery.externalPower &&
            battery.powerWatts >= 0.2 && battery.powerWatts < 5.0 &&
            maxCPU < 35 && maxNetwork < 256 * 1024 &&
            snapshot.powerState.darkWakeCount10m < 3

        if stableForBaseline {
            baselineSamples.append(battery.powerWatts)
            if baselineSamples.count > 180 { baselineSamples.removeFirst(baselineSamples.count - 180) }
            if baselineSamples.count >= 30,
               let median = PowerSentryMath.median(baselineSamples) {
                baselineWatts = min(5.0, max(0.4, median))
            }
        }

        var incidents: [Incident] = []

        if !battery.externalPower {
            if PowerSentryMath.shouldFlagPower(current: battery.powerWatts, baseline: baselineWatts) {
                powerStreak += 1
            } else {
                powerStreak = 0
            }

            if powerStreak >= 12 && !activeKinds.contains("power-runaway") {
                incidents.append(Incident(
                    kind: "power-runaway",
                    severity: .critical,
                    title: tr("incident.title.power"),
                    detail: trf("incident.detail.power", battery.powerWatts, baselineWatts),
                    recommendation: tr("incident.recommendation.power")
                ))
            }
        } else {
            powerStreak = 0
        }

        var nextCPUStreaks: [String: Int] = [:]
        for process in snapshot.topProcesses.prefix(30) {
            let path = process.identity.executablePath
            guard process.identity.pid > 100,
                  process.name != "PowerSentry",
                  path != "unknown",
                  !path.hasPrefix("/System/"),
                  !path.hasPrefix("/usr/libexec/") else { continue }

            if process.cpuPercent >= 85 {
                let streak = (cpuStreaks[process.identity.key] ?? 0) + 1
                nextCPUStreaks[process.identity.key] = streak
                let kind = "cpu-runaway:\(process.identity.key)"
                if streak >= 12 && !activeKinds.contains(kind) {
                    incidents.append(Incident(
                        kind: kind,
                        severity: .critical,
                        title: tr("incident.title.cpu"),
                        detail: trf("incident.detail.cpu", process.name, process.identity.pid, process.cpuPercent),
                        recommendation: tr("incident.recommendation.cpu"),
                        process: process.identity
                    ))
                }
            }
        }
        cpuStreaks = nextCPUStreaks

        for network in snapshot.topNetwork.prefix(20) {
            let sampleTime = network.sampledAt ?? snapshot.timestamp
            if let previousTime = lastNetworkSampleAt[network.pid], sampleTime <= previousTime {
                continue
            }
            if let previousTime = lastNetworkSampleAt[network.pid],
               sampleTime.timeIntervalSince(previousTime) > 45 {
                networkStreaks[network.pid] = 0
            }
            lastNetworkSampleAt[network.pid] = sampleTime

            if network.downloadBytesPerSecond >= 1_000_000 {
                let streak = (networkStreaks[network.pid] ?? 0) + 1
                networkStreaks[network.pid] = streak
                let kind = "network-heavy:\(network.pid)"
                if streak >= 2 && !activeKinds.contains(kind) {
                    let process = snapshot.topProcesses.first { $0.identity.pid == network.pid }
                    incidents.append(Incident(
                        kind: kind,
                        severity: .warning,
                        title: tr("incident.title.network"),
                        detail: trf("incident.detail.network", network.processName, network.pid, network.downloadBytesPerSecond / 1_000_000),
                        recommendation: tr("incident.recommendation.network"),
                        process: process?.identity
                    ))
                }
            } else {
                networkStreaks[network.pid] = 0
            }
        }

        if snapshot.powerState.darkWakeCount10m >= 10 {
            let canReport = lastDarkWakeIncident.map { Date().timeIntervalSince($0) > 3600 } ?? true
            if canReport && !activeKinds.contains("darkwake-frequent") {
                lastDarkWakeIncident = Date()
                incidents.append(Incident(
                    kind: "darkwake-frequent",
                    severity: .warning,
                    title: tr("incident.title.darkwake"),
                    detail: trf("incident.detail.darkwake", snapshot.powerState.darkWakeCount10m),
                    recommendation: tr("incident.recommendation.darkwake")
                ))
            }
        }

        return DetectionResult(
            baselineWatts: baselineWatts,
            baselineLearning: baselineSamples.count < 30,
            baselineSamples: baselineSamples,
            incidents: incidents
        )
    }
}
