import Foundation
import Combine
import Darwin

final class SystemCollector {
    private let batteryCollector = BatteryCollector()
    private let processCollector = ProcessCollector()
    private let networkCollector = NetworkCollector()
    private let powerCollector = PowerEventCollector()
    private let store = Store()
    private let detector: AnomalyDetector

    init() {
        detector = AnomalyDetector(initialSamples: store.loadBaselineSamples())
    }

    private var lastNetworkSample = Date.distantPast
    private var lastPowerSample = Date.distantPast
    private var lastPersistedSample = Date.distantPast
    private var cachedNetwork: [NetworkSnapshot] = []
    private var cachedPower = PowerStateSnapshot(timestamp: .distantPast, recentEvents: [], darkWakeCount10m: 0, assertions: [])

    func tick(now: Date = Date()) -> MonitorUpdate? {
        guard let battery = batteryCollector.sample(now: now) else { return nil }

        let processes = processCollector.sample(now: now)
        if now.timeIntervalSince(lastNetworkSample) >= 30 {
            cachedNetwork = networkCollector.sample(now: now)
            lastNetworkSample = now
        }
        if now.timeIntervalSince(lastPowerSample) >= 60 || lastPowerSample == .distantPast {
            cachedPower = powerCollector.sample(now: now)
            lastPowerSample = now
        }

        let provisional = SystemSnapshot(
            timestamp: now,
            battery: battery,
            topProcesses: Array(processes.prefix(40)),
            topNetwork: Array(cachedNetwork.prefix(40)),
            powerState: cachedPower,
            baselineWatts: 2.0,
            baselineLearning: true
        )
        let detection = detector.evaluate(provisional, activeKinds: store.openIncidentKinds())
        store.saveBaselineSamples(detection.baselineSamples)
        let snapshot = SystemSnapshot(
            timestamp: now,
            battery: battery,
            topProcesses: provisional.topProcesses,
            topNetwork: provisional.topNetwork,
            powerState: cachedPower,
            baselineWatts: detection.baselineWatts,
            baselineLearning: detection.baselineLearning
        )

        if now.timeIntervalSince(lastPersistedSample) >= 30 || lastPersistedSample == .distantPast {
            let persistedSnapshot = SystemSnapshot(
                timestamp: snapshot.timestamp,
                battery: snapshot.battery,
                topProcesses: Array(snapshot.topProcesses.prefix(20)),
                topNetwork: Array(snapshot.topNetwork.prefix(12)),
                powerState: snapshot.powerState,
                baselineWatts: snapshot.baselineWatts,
                baselineLearning: snapshot.baselineLearning
            )
            store.saveSample(persistedSnapshot)
            lastPersistedSample = now
        }
        for incident in detection.incidents {
            store.saveIncident(incident)
            NotificationManager.notify(incident)
        }

        let incidentList = store.loadIncidents(limit: 30)
        let history = store.loadRecentSamples(limit: 60)
        let status = battery.externalPower
            ? (battery.charging ? tr("status.power_charging") : tr("status.power_connected"))
            : tr("status.battery_monitoring")
        return MonitorUpdate(snapshot: snapshot, history: history, incidents: incidentList,
                             newIncidents: detection.incidents, status: status)
    }

    func terminate(_ incident: Incident) -> String {
        guard let identity = incident.process else { return tr("action.no_process_target") }
        let collector = ProcessCollector()
        guard let current = collector.currentIdentity(pid: identity.pid) else {
            return tr("action.process_missing")
        }
        guard current.executablePath == identity.executablePath,
              abs(current.startTime - identity.startTime) < 1.0 else {
            return tr("action.pid_reused")
        }
        guard let currentCPU = collector.currentCPUPercent(pid: identity.pid), currentCPU >= 80 else {
            return tr("action.cpu_recovered")
        }
        guard let finalIdentity = collector.currentIdentity(pid: identity.pid),
              finalIdentity.executablePath == identity.executablePath,
              abs(finalIdentity.startTime - identity.startTime) < 1.0 else {
            return tr("action.identity_changed")
        }
        guard identity.pid > 100,
              !identity.executablePath.hasPrefix("/System/"),
              !identity.executablePath.hasPrefix("/usr/libexec/"),
              identity.executablePath != "unknown" else {
            return tr("action.protected_system")
        }

        let result = Darwin.kill(identity.pid, SIGTERM)
        guard result == 0 else {
            return trf("action.sigterm_failed", String(cString: strerror(errno)))
        }

        Thread.sleep(forTimeInterval: 2)
        if Darwin.kill(identity.pid, 0) != 0 && errno == ESRCH {
            return tr("action.sigterm_exited")
        }
        return tr("action.sigterm_still_running")
    }

    func updateIncident(_ id: String, status: IncidentStatus, resolution: String? = nil) {
        guard var incident = store.loadIncidents(limit: 100).first(where: { $0.id == id }) else { return }
        incident.status = status
        incident.resolution = resolution
        store.updateIncident(incident)
    }

    func sampleCount() -> Int { store.sampleCount() }
}

final class MonitorEngine: ObservableObject {
    @Published private(set) var snapshot: SystemSnapshot?
    @Published private(set) var incidents: [Incident] = []
    @Published private(set) var history: [SystemSnapshot] = []
    @Published private(set) var status = tr("status.starting")
    @Published private(set) var actionMessage: String?
    @Published private(set) var sampleCount = 0

    private let queue = DispatchQueue(label: "com.aniss.powersentry.monitor", qos: .utility)
    private let collector = SystemCollector()
    private var timer: Timer?

    init() {
        NotificationManager.requestAuthorization()
        timer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in
            self?.refresh()
        }
        refresh()
    }

    deinit { timer?.invalidate() }

    func refresh() {
        queue.async { [weak self] in
            guard let self else { return }
            guard let update = self.collector.tick() else {
                DispatchQueue.main.async { self.status = tr("status.unable_battery_telemetry") }
                return
            }
            let count = self.collector.sampleCount()
            DispatchQueue.main.async {
                self.snapshot = update.snapshot
                self.incidents = update.incidents
                self.history = update.history
                self.status = update.status
                self.sampleCount = count
            }
        }
    }

    func approveTermination(_ incident: Incident) {
        queue.async { [weak self] in
            guard let self else { return }
            let result = self.collector.terminate(incident)
            self.collector.updateIncident(incident.id, status: .actionTaken, resolution: result)
            DispatchQueue.main.async {
                self.actionMessage = result
                self.refresh()
            }
        }
    }

    func ignore(_ incident: Incident) {
        queue.async { [weak self] in
            guard let self else { return }
            self.collector.updateIncident(incident.id, status: .ignored, resolution: tr("resolution.ignored"))
            DispatchQueue.main.async { self.refresh() }
        }
    }

    func acknowledge(_ incident: Incident) {
        queue.async { [weak self] in
            guard let self else { return }
            self.collector.updateIncident(incident.id, status: .acknowledged, resolution: tr("resolution.acknowledged"))
            DispatchQueue.main.async { self.refresh() }
        }
    }

}
