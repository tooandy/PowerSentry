import Foundation

struct BatterySnapshot: Codable {
    let timestamp: Date
    let percentage: Double
    let voltageMillivolts: Int
    let currentMilliamps: Int
    let powerWatts: Double
    let externalPower: Bool
    let charging: Bool
    let temperatureCelsius: Double?
    let cycleCount: Int?
    let fullCapacityWh: Double?
    let minutesTo20Percent: Double?
    let minutesToEmpty: Double?

    var powerLabel: String {
        if externalPower {
            return charging ? trf("battery.power_charging", String(format: "%.1f W", powerWatts)) : tr("battery.ac_connected")
        }
        return String(format: "%.1f W", powerWatts)
    }
}

struct ProcessSnapshot: Codable, Identifiable {
    var id: String { identity.key }
    let identity: ProcessIdentity
    let name: String
    let cpuPercent: Double
    let memoryBytes: UInt64
}

struct ProcessIdentity: Codable, Equatable {
    let pid: Int32
    let startTime: Double
    let executablePath: String

    var key: String { "\(pid):\(Int64(startTime * 1_000_000))" }
}

struct NetworkSnapshot: Codable, Identifiable {
    var id: Int32 { pid }
    let sampledAt: Date?
    let pid: Int32
    let processName: String
    let downloadBytesPerSecond: Double
    let uploadBytesPerSecond: Double
    let totalDownloadedBytes: UInt64
    let totalUploadedBytes: UInt64
}

struct PowerAssertion: Codable, Identifiable {
    var id: String { "\(pid):\(name)" }
    let pid: Int32
    let processName: String
    let assertionType: String
    let name: String
}

struct PowerEvent: Codable, Identifiable {
    var id: String { timestamp.timeIntervalSince1970.description + kind }
    let timestamp: Date
    let kind: String
    let detail: String
}

struct PowerStateSnapshot: Codable {
    let timestamp: Date
    let recentEvents: [PowerEvent]
    let darkWakeCount10m: Int
    let assertions: [PowerAssertion]
}

struct SystemSnapshot: Codable {
    let timestamp: Date
    let battery: BatterySnapshot
    let topProcesses: [ProcessSnapshot]
    let topNetwork: [NetworkSnapshot]
    let powerState: PowerStateSnapshot
    let baselineWatts: Double
    let baselineLearning: Bool
}

enum IncidentSeverity: String, Codable {
    case warning
    case critical
}

enum IncidentStatus: String, Codable {
    case open
    case acknowledged
    case resolved
    case ignored
    case actionTaken
}

struct Incident: Codable, Identifiable {
    let id: String
    let createdAt: Date
    let kind: String
    let severity: IncidentSeverity
    let title: String
    let detail: String
    let recommendation: String
    let process: ProcessIdentity?
    var status: IncidentStatus
    var resolution: String?

    init(kind: String, severity: IncidentSeverity, title: String, detail: String,
         recommendation: String, process: ProcessIdentity? = nil) {
        self.id = UUID().uuidString
        self.createdAt = Date()
        self.kind = kind
        self.severity = severity
        self.title = title
        self.detail = detail
        self.recommendation = recommendation
        self.process = process
        self.status = .open
        self.resolution = nil
    }
}

struct MonitorUpdate {
    let snapshot: SystemSnapshot
    let history: [SystemSnapshot]
    let incidents: [Incident]
    let newIncidents: [Incident]
    let status: String
}

enum PowerSentryMath {
    static func estimateMinutes(percentage: Double, threshold: Double, fullCapacityWh: Double,
                                dischargeWatts: Double) -> Double? {
        guard dischargeWatts > 0.15, fullCapacityWh > 0, percentage > threshold else { return nil }
        let remainingWh = (percentage - threshold) / 100.0 * fullCapacityWh
        return remainingWh / dischargeWatts * 60.0
    }

    static func median(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        let middle = sorted.count / 2
        if sorted.count.isMultiple(of: 2) {
            return (sorted[middle - 1] + sorted[middle]) / 2
        }
        return sorted[middle]
    }

    static func shouldFlagPower(current: Double, baseline: Double) -> Bool {
        current > max(baseline * 2.2, baseline + 2.0)
    }
}
