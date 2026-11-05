import Foundation

enum SelfTests {
    static func run() -> Int32 {
        var failures = 0
        func check(_ name: String, _ condition: Bool) {
            if condition {
                print("PASS  \(name)")
            } else {
                print("FAIL  \(name)")
                failures += 1
            }
        }

        check("median odd", PowerSentryMath.median([9, 1, 5]) == 5)
        check("median even", PowerSentryMath.median([1, 9, 5, 3]) == 4)
        check("power threshold below", !PowerSentryMath.shouldFlagPower(current: 3.4, baseline: 1.5))
        check("power threshold above", PowerSentryMath.shouldFlagPower(current: 3.6, baseline: 1.5))

        let estimate = PowerSentryMath.estimateMinutes(
            percentage: 80, threshold: 20, fullCapacityWh: 60, dischargeWatts: 3
        )
        check("runtime estimate", abs((estimate ?? 0) - 720) < 0.001)
        check("runtime threshold passed", PowerSentryMath.estimateMinutes(
            percentage: 15, threshold: 20, fullCapacityWh: 60, dischargeWatts: 3
        ) == nil)

        check("power runaway sustained rule", testPowerRunaway())
        check("per-process CPU runaway rule", testCPURunaway())
        check("per-process network rule", testNetworkRunaway())
        check("cached network sample does not advance streak", testNetworkNeedsFreshSamples())
        check("DarkWake frequency rule", testDarkWakeRule())

        print("SELF_TESTS: \(failures == 0 ? "PASS" : "FAIL") (\(failures) failures)")
        return failures == 0 ? 0 : 1
    }

    private static func baseSnapshot(now: Date, power: Double = 1.5,
                                     processes: [ProcessSnapshot] = [],
                                     network: [NetworkSnapshot] = [],
                                     darkWake: Int = 0) -> SystemSnapshot {
        let battery = BatterySnapshot(
            timestamp: now, percentage: 70, voltageMillivolts: 12000,
            currentMilliamps: -125, powerWatts: power, externalPower: false,
            charging: false, temperatureCelsius: 30, cycleCount: 30,
            fullCapacityWh: 58, minutesTo20Percent: nil, minutesToEmpty: nil
        )
        let powerState = PowerStateSnapshot(
            timestamp: now, recentEvents: [], darkWakeCount10m: darkWake, assertions: []
        )
        return SystemSnapshot(
            timestamp: now, battery: battery, topProcesses: processes,
            topNetwork: network, powerState: powerState,
            baselineWatts: 1.5, baselineLearning: false
        )
    }

    private static func testPowerRunaway() -> Bool {
        let detector = AnomalyDetector(initialSamples: Array(repeating: 1.5, count: 30))
        let start = Date()
        var found = false
        for index in 0..<12 {
            let snapshot = baseSnapshot(now: start.addingTimeInterval(Double(index * 10)), power: 6.0)
            let result = detector.evaluate(snapshot, activeKinds: [])
            found = found || result.incidents.contains { $0.kind == "power-runaway" }
        }
        return found
    }

    private static func testCPURunaway() -> Bool {
        let detector = AnomalyDetector(initialSamples: Array(repeating: 1.5, count: 30))
        let start = Date()
        let identity = ProcessIdentity(
            pid: 4567, startTime: start.timeIntervalSince1970,
            executablePath: "/Applications/Microsoft Edge.app/Contents/MacOS/Microsoft Edge"
        )
        let process = ProcessSnapshot(identity: identity, name: "Microsoft Edge Helper (Renderer)",
                                      cpuPercent: 99.2, memoryBytes: 500_000_000)
        var found = false
        for index in 0..<12 {
            let snapshot = baseSnapshot(now: start.addingTimeInterval(Double(index * 10)), processes: [process])
            let result = detector.evaluate(snapshot, activeKinds: [])
            found = found || result.incidents.contains { $0.kind == "cpu-runaway:\(identity.key)" }
        }
        return found
    }

    private static func testNetworkRunaway() -> Bool {
        let detector = AnomalyDetector(initialSamples: Array(repeating: 1.5, count: 30))
        let start = Date()
        let flow = NetworkSnapshot(sampledAt: start, pid: 543, processName: "WeChat",
                                   downloadBytesPerSecond: 1_500_000,
                                   uploadBytesPerSecond: 10_000,
                                   totalDownloadedBytes: 5_000_000,
                                   totalUploadedBytes: 100_000)
        _ = detector.evaluate(baseSnapshot(now: start, network: [flow]), activeKinds: [])
        let nextFlow = NetworkSnapshot(sampledAt: start.addingTimeInterval(30), pid: 543,
                                        processName: "WeChat", downloadBytesPerSecond: 1_500_000,
                                        uploadBytesPerSecond: 10_000, totalDownloadedBytes: 8_000_000,
                                        totalUploadedBytes: 200_000)
        let result = detector.evaluate(baseSnapshot(now: start.addingTimeInterval(30), network: [nextFlow]), activeKinds: [])
        return result.incidents.contains { $0.kind == "network-heavy:543" }
    }

    private static func testNetworkNeedsFreshSamples() -> Bool {
        let detector = AnomalyDetector(initialSamples: Array(repeating: 1.5, count: 30))
        let start = Date()
        let firstFlow = NetworkSnapshot(sampledAt: start, pid: 543, processName: "WeChat",
                                        downloadBytesPerSecond: 1_500_000, uploadBytesPerSecond: 0,
                                        totalDownloadedBytes: 5_000_000, totalUploadedBytes: 0)
        _ = detector.evaluate(baseSnapshot(now: start, network: [firstFlow]), activeKinds: [])
        let cached = detector.evaluate(baseSnapshot(now: start.addingTimeInterval(10), network: [firstFlow]), activeKinds: [])
        if cached.incidents.contains(where: { $0.kind == "network-heavy:543" }) { return false }
        let nextFlow = NetworkSnapshot(sampledAt: start.addingTimeInterval(30), pid: 543,
                                        processName: "WeChat", downloadBytesPerSecond: 1_500_000,
                                        uploadBytesPerSecond: 0, totalDownloadedBytes: 8_000_000,
                                        totalUploadedBytes: 0)
        let fresh = detector.evaluate(baseSnapshot(now: start.addingTimeInterval(30), network: [nextFlow]), activeKinds: [])
        return fresh.incidents.contains { $0.kind == "network-heavy:543" }
    }

    private static func testDarkWakeRule() -> Bool {
        let detector = AnomalyDetector(initialSamples: Array(repeating: 1.5, count: 30))
        let snapshot = baseSnapshot(now: Date(), darkWake: 10)
        let result = detector.evaluate(snapshot, activeKinds: [])
        return result.incidents.contains { $0.kind == "darkwake-frequent" }
    }
}
