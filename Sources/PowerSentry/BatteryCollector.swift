import Foundation
import IOKit

final class BatteryCollector {
    func sample(now: Date = Date()) -> BatterySnapshot? {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }

        var properties: Unmanaged<CFMutableDictionary>?
        let result = IORegistryEntryCreateCFProperties(service, &properties, kCFAllocatorDefault, 0)
        guard result == KERN_SUCCESS,
              let dictionary = properties?.takeRetainedValue() as? [String: Any] else {
            return nil
        }

        func number(_ key: String) -> NSNumber? { dictionary[key] as? NSNumber }
        func int(_ key: String, default fallback: Int = 0) -> Int {
            number(key)?.intValue ?? fallback
        }
        func signedInt(_ key: String) -> Int {
            guard let n = number(key) else { return 0 }
            let raw = n.uint64Value
            if raw > UInt64(Int64.max) { return Int(Int64(bitPattern: raw)) }
            return n.intValue
        }

        let currentCapacity = Double(int("CurrentCapacity"))
        let maxCapacity = max(1.0, Double(int("MaxCapacity", default: 100)))
        let percentage = min(100, max(0, currentCapacity / maxCapacity * 100))
        let voltage = int("Voltage")
        let current = signedInt("InstantAmperage")
        let external = number("ExternalConnected")?.boolValue ?? false
        let charging = number("IsCharging")?.boolValue ?? false
        let watts = abs(Double(current) * Double(voltage)) / 1_000_000.0
        let dischargeWatts = external ? 0 : watts

        let rawMax = Double(int("AppleRawMaxCapacity"))
        let nominalVoltage = 11.4
        let fullCapacityWh = rawMax > 0 ? rawMax * nominalVoltage / 1000.0 : nil
        let minutesTo20 = fullCapacityWh.flatMap {
            PowerSentryMath.estimateMinutes(
                percentage: percentage, threshold: 20,
                fullCapacityWh: $0, dischargeWatts: dischargeWatts
            )
        }
        let minutesToEmpty = fullCapacityWh.flatMap {
            PowerSentryMath.estimateMinutes(
                percentage: percentage, threshold: 0,
                fullCapacityWh: $0, dischargeWatts: dischargeWatts
            )
        }

        let temperature = number("Temperature").map { $0.doubleValue / 100.0 }
        let cycles = number("CycleCount")?.intValue

        return BatterySnapshot(
            timestamp: now,
            percentage: percentage,
            voltageMillivolts: voltage,
            currentMilliamps: current,
            powerWatts: watts,
            externalPower: external,
            charging: charging,
            temperatureCelsius: temperature,
            cycleCount: cycles,
            fullCapacityWh: fullCapacityWh,
            minutesTo20Percent: external ? nil : minutesTo20,
            minutesToEmpty: external ? nil : minutesToEmpty
        )
    }
}
