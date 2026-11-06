import SwiftUI
import Charts
import AppKit
import Darwin

@MainActor
final class PowerSentryRuntime {
    static let shared = PowerSentryRuntime()
    let monitor = MonitorEngine()
    private init() {}
}

@MainActor
final class DashboardWindowController: NSObject, NSWindowDelegate {
    static let shared = DashboardWindowController()
    private var window: NSWindow?

    func show() {
        NSApp.activate(ignoringOtherApps: true)

        if let window {
            if window.isMiniaturized {
                window.deminiaturize(nil)
            }
            window.makeKeyAndOrderFront(nil)
            return
        }

        let content = DashboardView()
            .environmentObject(PowerSentryRuntime.shared.monitor)
        let hostingController = NSHostingController(rootView: content)
        let newWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 820, height: 760),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        newWindow.identifier = NSUserInterfaceItemIdentifier("com.aniss.powersentry.dashboard")
        newWindow.title = "PowerSentry"
        newWindow.contentViewController = hostingController
        newWindow.minSize = NSSize(width: 760, height: 680)
        newWindow.isReleasedWhenClosed = false
        newWindow.delegate = self
        newWindow.center()

        // Keep all three standard macOS title-bar controls enabled.
        newWindow.standardWindowButton(.closeButton)?.isEnabled = true
        newWindow.standardWindowButton(.miniaturizeButton)?.isEnabled = true
        newWindow.standardWindowButton(.zoomButton)?.isEnabled = true

        window = newWindow
        newWindow.makeKeyAndOrderFront(nil)
        newWindow.orderFrontRegardless()
        NSApp.activate(ignoringOtherApps: true)
        NSRunningApplication.current.activate(options: [.activateAllWindows])

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            newWindow.makeKeyAndOrderFront(nil)
            newWindow.orderFrontRegardless()
            NSApp.activate(ignoringOtherApps: true)
            NSRunningApplication.current.activate(options: [.activateAllWindows])
        }

    }

    func closeForLifecycleTest() {
        window?.performClose(nil)
    }

    func lifecycleTestPassed() -> Bool {
        guard let window else { return false }
        return window.isVisible &&
            window.isKeyWindow &&
            (window.standardWindowButton(.closeButton)?.isEnabled ?? false) &&
            (window.standardWindowButton(.miniaturizeButton)?.isEnabled ?? false) &&
            (window.standardWindowButton(.zoomButton)?.isEnabled ?? false)
    }

    func windowWillClose(_ notification: Notification) {
        guard let closedWindow = notification.object as? NSWindow,
              closedWindow === window else { return }
        window = nil
    }
}

final class PowerSentryAppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Accessory apps keep their menu-bar extra and windows, but do not appear in the Dock or Cmd+Tab.
        NSApp.setActivationPolicy(.accessory)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            DashboardWindowController.shared.show()

            guard CommandLine.arguments.contains("--window-lifecycle-test") else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                DashboardWindowController.shared.closeForLifecycleTest()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    let monitorStayedAlive = NSApp.isRunning
                    DashboardWindowController.shared.show()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        let passed = monitorStayedAlive &&
                            NSApp.activationPolicy() == .accessory &&
                            DashboardWindowController.shared.lifecycleTestPassed()
                        NSLog("PowerSentry menu-bar-only/window lifecycle test: %@ (policy=%ld, monitorAlive=%d)", passed ? "PASS" : "FAIL", NSApp.activationPolicy().rawValue, monitorStayedAlive)
                        Darwin.exit(passed ? 0 : 3)
                    }
                }
            }
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        DashboardWindowController.shared.show()
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        // Closing the dashboard must leave the menu-bar monitor alive.
        false
    }
}

@main
struct PowerSentryApp: App {
    @NSApplicationDelegateAdaptor(PowerSentryAppDelegate.self) private var appDelegate
    @StateObject private var monitor = PowerSentryRuntime.shared.monitor

    init() {
        if CommandLine.arguments.contains("--localization-test") {
            Darwin.exit(PowerSentryLocalization.validateResources() ? 0 : 4)
        }
        if CommandLine.arguments.contains("--self-test") {
            Darwin.exit(SelfTests.run())
        }
        if CommandLine.arguments.contains("--network-check") {
            let collector = NetworkCollector()
            _ = collector.sample()
            Thread.sleep(forTimeInterval: 3)
            let values = collector.sample()
            print("NETWORK_CHECK: \(values.count) processes with traffic")
            for item in values.prefix(12) {
                print(String(format: "%@ PID %d ↓ %.1f KB/s ↑ %.1f KB/s",
                             item.processName, item.pid,
                             item.downloadBytesPerSecond / 1024,
                             item.uploadBytesPerSecond / 1024))
            }
            Darwin.exit(0)
        }
        if CommandLine.arguments.contains("--diagnose") {
            let collector = SystemCollector()
            _ = collector.tick()
            Thread.sleep(forTimeInterval: 2)
            if let update = collector.tick() {
                let snapshot = update.snapshot
                print("POWERSENTRY_DIAGNOSTIC_OK")
                print(String(format: "battery=%.0f%% external=%@ charging=%@ voltage=%dmV current=%dmA power=%.2fW",
                             snapshot.battery.percentage,
                             snapshot.battery.externalPower.description,
                             snapshot.battery.charging.description,
                             snapshot.battery.voltageMillivolts,
                             snapshot.battery.currentMilliamps,
                             snapshot.battery.powerWatts))
                print("baseline=\(snapshot.baselineWatts)W learning=\(snapshot.baselineLearning)")
                print("processes=\(snapshot.topProcesses.count) network=\(snapshot.topNetwork.count)")
                for process in snapshot.topProcesses.prefix(8) {
                    print(String(format: "CPU %.1f%% | %@ | PID %d | %@",
                                 process.cpuPercent, process.name, process.identity.pid,
                                 ByteText.memory(process.memoryBytes)))
                }
                print("assertions=\(snapshot.powerState.assertions.count) darkWake10m=\(snapshot.powerState.darkWakeCount10m)")
                print("sqlite_samples=\(collector.sampleCount())")
            } else {
                fputs("PowerSentry could not read AppleSmartBattery.\n", stderr)
                Darwin.exit(2)
            }
            Darwin.exit(0)
        }
    }

    var body: some Scene {
        MenuBarExtra {
            MenuPanel()
                .environmentObject(monitor)
        } label: {
            MenuBatteryStatusLabel(battery: monitor.snapshot?.battery)
        }
        .menuBarExtraStyle(.window)
    }
}

struct MenuPanel: View {
    @EnvironmentObject private var monitor: MonitorEngine
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("PowerSentry").font(.headline)
                Spacer()
                Circle()
                    .fill(monitor.snapshot == nil ? .gray : .green)
                    .frame(width: 8, height: 8)
                Text(monitor.snapshot == nil ? tr("status.starting") : tr("status.local_monitoring"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let snapshot = monitor.snapshot {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(String(format: "%.0f%%", snapshot.battery.percentage))
                        .font(.system(size: 34, weight: .semibold, design: .rounded))
                    Text(snapshot.battery.externalPower ? tr("detail.external_power") : snapshot.battery.powerLabel)
                        .foregroundStyle(.secondary)
                }
                if !snapshot.battery.externalPower,
                   let minutes = snapshot.battery.minutesTo20Percent {
                    Text(trf("menu.eta_to_20", DurationText.format(minutes: minutes)))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text(trf("menu.baseline", snapshot.baselineLearning ? tr("status.learning") : String(format: "%.2f W", snapshot.baselineWatts)))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(trf("menu.open_incidents", monitor.incidents.filter { $0.status == .open }.count))
                    .font(.caption)
            } else {
                Text(monitor.status).foregroundStyle(.secondary)
            }

            Divider()
            Button(tr("menu.open_dashboard")) { DashboardWindowController.shared.show() }
                .keyboardShortcut(.return)
            Button(tr("button.sample_now")) { monitor.refresh() }
            Divider()
            Button(tr("menu.quit")) { NSApp.terminate(nil) }
        }
        .padding(16)
        .frame(width: 300)
    }

}

struct DashboardView: View {
    @EnvironmentObject private var monitor: MonitorEngine

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                if let snapshot = monitor.snapshot {
                    batterySection(snapshot)
                    powerHistorySection
                    incidentSection
                    processSection(snapshot)
                    networkSection(snapshot)
                    powerSection(snapshot)
                    footer(snapshot)
                } else {
                    ProgressView(tr("dashboard.loading"))
                        .frame(maxWidth: .infinity, minHeight: 260)
                }
            }
            .padding(22)
        }
        .frame(minWidth: 760, minHeight: 680)
    }

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 4) {
                Text("PowerSentry").font(.system(size: 27, weight: .bold))
                Text(tr("dashboard.subtitle"))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                Text(monitor.status).font(.subheadline.weight(.medium))
                Text(trf("dashboard.last_updated", monitor.snapshot?.timestamp.formatted(date: .omitted, time: .standard) ?? "—"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private func batterySection(_ snapshot: SystemSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle(tr("section.battery_power"), subtitle: tr("section.battery_subtitle"))
            HStack(spacing: 12) {
                metricCard(tr("metric.battery_level"), value: String(format: "%.0f%%", snapshot.battery.percentage),
                           detail: snapshot.battery.externalPower ? tr("detail.external_power") : tr("detail.battery_power"),
                           icon: "battery.100percent")
                metricCard(tr("metric.current_power"), value: snapshot.battery.externalPower ? tr("value.charging") : String(format: "%.2f W", snapshot.battery.powerWatts),
                           detail: "\(snapshot.battery.voltageMillivolts) mV · \(snapshot.battery.currentMilliamps) mA",
                           icon: "bolt.fill")
                metricCard(tr("metric.to_20_percent"), value: snapshot.battery.minutesTo20Percent.map { DurationText.format(minutes: $0) } ?? "—",
                           detail: snapshot.battery.externalPower ? tr("detail.not_estimated_on_ac") : tr("detail.estimated_at_current_power"),
                           icon: "clock")
                metricCard(tr("metric.power_baseline"), value: snapshot.baselineLearning ? tr("status.learning") : String(format: "%.2f W", snapshot.baselineWatts),
                           detail: tr("detail.stable_low_load_samples"),
                           icon: "chart.line.downtrend.xyaxis")
            }
            HStack(spacing: 18) {
                if let temperature = snapshot.battery.temperatureCelsius {
                    Label(trf("label.battery_temperature", temperature), systemImage: "thermometer.medium")
                }
                if let cycles = snapshot.battery.cycleCount {
                    Label(trf("label.cycle_count", cycles), systemImage: "arrow.triangle.2.circlepath")
                }
                Text(trf("label.sample_records", monitor.sampleCount))
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    private var powerHistorySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle(tr("section.recent_discharge_power"), subtitle: tr("section.recent_discharge_subtitle"))
            let points = monitor.history.filter { !$0.battery.externalPower }
            if points.count >= 2 {
                Chart(points, id: \.timestamp) { point in
                    LineMark(
                        x: .value(tr("chart.time"), point.timestamp),
                        y: .value(tr("chart.power"), point.battery.powerWatts)
                    )
                    .interpolationMethod(.catmullRom)
                }
                .chartYAxisLabel("W")
                .frame(height: 130)
                .padding(10)
                .background(.background.secondary, in: RoundedRectangle(cornerRadius: 10))
            } else {
                Text(tr("empty.discharge_samples"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var incidentSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle(tr("section.incidents"), subtitle: tr("section.incidents_subtitle"))
            if let message = monitor.actionMessage {
                Text(message)
                    .font(.callout)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8))
            }
            let visible = monitor.incidents.filter { $0.status == .open || $0.status == .acknowledged || $0.status == .actionTaken }
            if visible.isEmpty {
                Label(tr("empty.incidents"), systemImage: "checkmark.shield")
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 10)
            } else {
                ForEach(visible.prefix(8)) { incident in
                    IncidentCard(incident: incident)
                        .environmentObject(monitor)
                }
            }
        }
    }

    private func processSection(_ snapshot: SystemSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle(tr("section.processes"), subtitle: tr("section.processes_subtitle"))
            VStack(spacing: 0) {
                HStack {
                    Text(tr("column.process_pid"))
                    Spacer()
                    Text(tr("column.cpu")).frame(width: 75, alignment: .trailing)
                    Text(tr("column.memory")).frame(width: 90, alignment: .trailing)
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                ForEach(snapshot.topProcesses.prefix(12)) { process in
                    HStack(spacing: 8) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(process.name).font(.system(.body, design: .rounded)).lineLimit(1)
                            Text("PID \(process.identity.pid) · \(process.identity.executablePath)")
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                        Spacer(minLength: 8)
                        Text(String(format: "%.1f%%", process.cpuPercent))
                            .monospacedDigit()
                            .foregroundStyle(process.cpuPercent >= 85 ? .red : .primary)
                            .frame(width: 75, alignment: .trailing)
                        Text(ByteText.memory(process.memoryBytes))
                            .monospacedDigit()
                            .frame(width: 90, alignment: .trailing)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    Divider().padding(.leading, 10)
                }
            }
            .background(.background.secondary, in: RoundedRectangle(cornerRadius: 10))
        }
    }

    private func networkSection(_ snapshot: SystemSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle(tr("section.network"), subtitle: tr("section.network_subtitle"))
            if snapshot.topNetwork.isEmpty {
                Text(tr("status.network_baseline")).foregroundStyle(.secondary)
            } else {
                VStack(spacing: 0) {
                    ForEach(snapshot.topNetwork.prefix(10)) { item in
                        HStack {
                            Text("\(item.processName) · PID \(item.pid)").lineLimit(1)
                            Spacer()
                            Text("↓ \(ByteText.rate(item.downloadBytesPerSecond))")
                                .monospacedDigit()
                            Text("↑ \(ByteText.rate(item.uploadBytesPerSecond))")
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                        }
                        .font(.caption)
                        .padding(.vertical, 6)
                        Divider()
                    }
                }
            }
        }
    }

    private func powerSection(_ snapshot: SystemSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle(tr("section.sleep_power"), subtitle: tr("section.sleep_power_subtitle"))
            HStack {
                metricCard(tr("metric.darkwake"), value: "\(snapshot.powerState.darkWakeCount10m)",
                           detail: snapshot.powerState.darkWakeCount10m >= 10 ? tr("detail.frequency_high") : tr("detail.last_10_minutes"),
                           icon: "moon.zzz")
                metricCard(tr("metric.power_assertions"), value: "\(snapshot.powerState.assertions.count)",
                           detail: tr("detail.prevent_idle"),
                           icon: "bolt.slash")
            }
            if !snapshot.powerState.assertions.isEmpty {
                ForEach(snapshot.powerState.assertions.prefix(8)) { assertion in
                    HStack {
                        Text("\(assertion.processName) (\(assertion.pid))")
                        Spacer()
                        Text(assertion.name)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    .font(.caption)
                }
            }
            if !snapshot.powerState.recentEvents.isEmpty {
                Text(tr("label.recent_power_events")).font(.subheadline.weight(.semibold)).padding(.top, 4)
                ForEach(snapshot.powerState.recentEvents.suffix(8)) { event in
                    HStack {
                        Text(event.timestamp.formatted(date: .omitted, time: .standard))
                            .monospacedDigit()
                        Text(event.kind).fontWeight(.medium)
                        Spacer()
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func footer(_ snapshot: SystemSnapshot) -> some View {
        HStack {
            Text(tr("footer.local_only"))
            Spacer()
            Text(tr("footer.sqlite_history"))
            Button(tr("button.sample_now")) { monitor.refresh() }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.top, 4)
    }

    private func sectionTitle(_ title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.title3.weight(.semibold))
            Text(subtitle).font(.caption).foregroundStyle(.secondary)
        }
    }

    private func metricCard(_ title: String, value: String, detail: String, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Label(title, systemImage: icon)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value).font(.system(size: 23, weight: .semibold, design: .rounded))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            Text(detail).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 10))
    }
}

struct IncidentCard: View {
    @EnvironmentObject private var monitor: MonitorEngine
    let incident: Incident

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: incident.severity == .critical ? "exclamationmark.triangle.fill" : "exclamationmark.circle.fill")
                    .foregroundStyle(incident.severity == .critical ? .red : .orange)
                Text(incident.title).font(.headline)
                Spacer()
                Text(tr("incident.status.\(incident.status.rawValue)"))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Text(incident.detail).font(.callout)
            Text(trf("incident.recommendation_prefix", incident.recommendation))
                .font(.caption)
                .foregroundStyle(.secondary)
            if let process = incident.process {
                Text(trf("incident.target", process.pid, process.executablePath))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .truncationMode(.middle)
            }
            HStack {
                if incident.kind.hasPrefix("cpu-runaway:") && incident.process != nil && incident.status == .open {
                    Button(tr("button.approve_terminate")) {
                        confirmTermination()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                }
                if incident.status == .open {
                    Button(tr("button.acknowledge")) { monitor.acknowledge(incident) }
                    Button(tr("button.ignore")) { monitor.ignore(incident) }
                }
                Spacer()
                Text(incident.createdAt.formatted(date: .omitted, time: .standard))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(12)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 10))
    }

    private func confirmTermination() {
        guard let process = incident.process else { return }
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = tr("alert.termination.title")
        alert.informativeText = trf("alert.termination.info", incident.title, process.pid, process.executablePath)
        alert.addButton(withTitle: tr("alert.termination.confirm"))
        alert.addButton(withTitle: tr("alert.cancel"))
        if alert.runModal() == .alertFirstButtonReturn {
            monitor.approveTermination(incident)
        }
    }
}

enum DurationText {
    static func format(minutes: Double) -> String {
        guard minutes.isFinite, minutes > 0 else { return "—" }
        let total = Int(minutes.rounded())
        let hours = total / 60
        let mins = total % 60
        if hours == 0 { return trf("duration.minutes", mins) }
        return trf("duration.hours_minutes", hours, mins)
    }
}

enum ByteText {
    static func rate(_ bytes: Double) -> String {
        if bytes >= 1_000_000 { return String(format: "%.2f MB/s", bytes / 1_000_000) }
        if bytes >= 1_000 { return String(format: "%.1f KB/s", bytes / 1_000) }
        return String(format: "%.0f B/s", bytes)
    }

    static func memory(_ bytes: UInt64) -> String {
        let mb = Double(bytes) / 1_048_576
        if mb >= 1024 { return String(format: "%.1f GB", mb / 1024) }
        return String(format: "%.0f MB", mb)
    }
}
