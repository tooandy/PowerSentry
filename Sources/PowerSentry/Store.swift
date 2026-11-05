import Foundation
import SQLite3

final class Store {
    private var database: OpaquePointer?
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("PowerSentry", isDirectory: true)
        try? FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        let url = support.appendingPathComponent("powersentry.sqlite")
        guard sqlite3_open(url.path, &database) == SQLITE_OK else {
            database = nil
            return
        }
        sqlite3_busy_timeout(database, 3000)
        execute("""
            CREATE TABLE IF NOT EXISTS samples (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                timestamp REAL NOT NULL,
                payload TEXT NOT NULL
            );
            CREATE INDEX IF NOT EXISTS idx_samples_timestamp ON samples(timestamp);
            CREATE TABLE IF NOT EXISTS incidents (
                id TEXT PRIMARY KEY,
                timestamp REAL NOT NULL,
                status TEXT NOT NULL,
                kind TEXT NOT NULL,
                payload TEXT NOT NULL
            );
            CREATE INDEX IF NOT EXISTS idx_incidents_timestamp ON incidents(timestamp);
            CREATE TABLE IF NOT EXISTS settings (
                key TEXT PRIMARY KEY,
                value TEXT NOT NULL
            );
        """)
        purgeOldSamples()
    }

    deinit {
        if let database { sqlite3_close(database) }
    }

    func saveSample(_ snapshot: SystemSnapshot) {
        guard let database, let payload = try? encoder.encode(snapshot),
              let json = String(data: payload, encoding: .utf8) else { return }
        var statement: OpaquePointer?
        let sql = "INSERT INTO samples(timestamp, payload) VALUES (?, ?)"
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_double(statement, 1, snapshot.timestamp.timeIntervalSince1970)
        bind(json, to: statement, at: 2)
        sqlite3_step(statement)
    }

    func saveIncident(_ incident: Incident) {
        guard let database, let payload = try? encoder.encode(incident),
              let json = String(data: payload, encoding: .utf8) else { return }
        var statement: OpaquePointer?
        let sql = "INSERT OR REPLACE INTO incidents(id, timestamp, status, kind, payload) VALUES (?, ?, ?, ?, ?)"
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(statement) }
        bind(incident.id, to: statement, at: 1)
        sqlite3_bind_double(statement, 2, incident.createdAt.timeIntervalSince1970)
        bind(incident.status.rawValue, to: statement, at: 3)
        bind(incident.kind, to: statement, at: 4)
        bind(json, to: statement, at: 5)
        sqlite3_step(statement)
    }

    func updateIncident(_ incident: Incident) {
        saveIncident(incident)
    }

    func loadIncidents(limit: Int = 30) -> [Incident] {
        guard let database else { return [] }
        var statement: OpaquePointer?
        let sql = "SELECT payload FROM incidents ORDER BY timestamp DESC LIMIT ?"
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_int(statement, 1, Int32(limit))
        var incidents: [Incident] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let raw = sqlite3_column_text(statement, 0) else { continue }
            let data = Data(bytes: raw, count: Int(sqlite3_column_bytes(statement, 0)))
            if let incident = try? decoder.decode(Incident.self, from: data) {
                incidents.append(incident)
            }
        }
        return incidents
    }

    func openIncidentKinds() -> Set<String> {
        let cutoff = Date().addingTimeInterval(-3600)
        return Set(loadIncidents(limit: 100).filter {
            $0.status == .open || $0.status == .acknowledged ||
            (($0.status == .ignored || $0.status == .actionTaken) && $0.createdAt >= cutoff)
        }.map(\.kind))
    }

    func loadBaselineSamples() -> [Double] {
        guard let database else { return [] }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, "SELECT value FROM settings WHERE key = 'baseline_samples'", -1, &statement, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW,
              let raw = sqlite3_column_text(statement, 0) else { return [] }
        let data = Data(bytes: raw, count: Int(sqlite3_column_bytes(statement, 0)))
        return (try? decoder.decode([Double].self, from: data)) ?? []
    }

    func saveBaselineSamples(_ samples: [Double]) {
        guard let database, let data = try? encoder.encode(samples),
              let json = String(data: data, encoding: .utf8) else { return }
        var statement: OpaquePointer?
        let sql = "INSERT OR REPLACE INTO settings(key, value) VALUES ('baseline_samples', ?)"
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(statement) }
        bind(json, to: statement, at: 1)
        sqlite3_step(statement)
    }

    func loadRecentSamples(limit: Int = 180) -> [SystemSnapshot] {
        guard let database else { return [] }
        var statement: OpaquePointer?
        let sql = "SELECT payload FROM samples ORDER BY timestamp DESC LIMIT ?"
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_int(statement, 1, Int32(limit))
        var snapshots: [SystemSnapshot] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let raw = sqlite3_column_text(statement, 0) else { continue }
            let data = Data(bytes: raw, count: Int(sqlite3_column_bytes(statement, 0)))
            if let snapshot = try? decoder.decode(SystemSnapshot.self, from: data) {
                snapshots.append(snapshot)
            }
        }
        return snapshots.reversed()
    }

    func sampleCount() -> Int {
        guard let database else { return 0 }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, "SELECT COUNT(*) FROM samples", -1, &statement, nil) == SQLITE_OK else { return 0 }
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW else { return 0 }
        return Int(sqlite3_column_int(statement, 0))
    }

    private func purgeOldSamples() {
        guard let database else { return }
        let cutoff = Date().addingTimeInterval(-7 * 24 * 60 * 60).timeIntervalSince1970
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, "DELETE FROM samples WHERE timestamp < ?", -1, &statement, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_double(statement, 1, cutoff)
        sqlite3_step(statement)
    }

    private func execute(_ sql: String) {
        guard let database else { return }
        sqlite3_exec(database, sql, nil, nil, nil)
    }

    private func bind(_ value: String, to statement: OpaquePointer?, at index: Int32) {
        _ = value.withCString { pointer in
            sqlite3_bind_text(statement, index, pointer, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
        }
    }
}
