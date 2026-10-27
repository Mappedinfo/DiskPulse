import Foundation
import SQLite3

// 只在 Recorder actor 中使用；每次写入均由 SQLite 事务原子提交。
public final class HistoryStore {
    private var database: OpaquePointer?

    public init(url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard sqlite3_open_v2(url.path, &database, SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK else {
            let detail = database.map { String(cString: sqlite3_errmsg($0)) } ?? "无法打开数据库"
            sqlite3_close(database)
            database = nil
            throw DiskPulseError.database(detail)
        }
        do {
            sqlite3_busy_timeout(database, 3_000)
            try execute("PRAGMA journal_mode=WAL;")
            try execute("""
                CREATE TABLE IF NOT EXISTS samples (
                    hour INTEGER PRIMARY KEY,
                    recorded_at REAL NOT NULL,
                    total_bytes INTEGER NOT NULL CHECK(total_bytes > 0),
                    free_bytes INTEGER NOT NULL CHECK(free_bytes >= 0 AND free_bytes <= total_bytes)
                );
                PRAGMA user_version=1;
                """)
        } catch {
            sqlite3_close(database)
            database = nil
            throw error
        }
    }

    deinit { sqlite3_close(database) }

    public func save(_ sample: DiskSample, calendar: Calendar = .current) throws {
        let statement = try prepare("""
            INSERT INTO samples(hour, recorded_at, total_bytes, free_bytes) VALUES (?, ?, ?, ?)
            ON CONFLICT(hour) DO UPDATE SET
                recorded_at=excluded.recorded_at, total_bytes=excluded.total_bytes, free_bytes=excluded.free_bytes;
            """)
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_int64(statement, 1, Int64(HourlySchedule.start(of: sample.date, calendar: calendar).timeIntervalSince1970))
        sqlite3_bind_double(statement, 2, sample.date.timeIntervalSince1970)
        sqlite3_bind_int64(statement, 3, sample.totalBytes)
        sqlite3_bind_int64(statement, 4, sample.freeBytes)
        guard sqlite3_step(statement) == SQLITE_DONE else { throw error() }
    }

    public func samples(since date: Date = .distantPast) throws -> [DiskSample] {
        let statement = try prepare("SELECT recorded_at, total_bytes, free_bytes FROM samples WHERE recorded_at >= ? ORDER BY recorded_at;")
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_double(statement, 1, date.timeIntervalSince1970)
        var rows: [DiskSample] = []
        while true {
            switch sqlite3_step(statement) {
            case SQLITE_ROW:
                rows.append(try DiskSample(
                    date: Date(timeIntervalSince1970: sqlite3_column_double(statement, 0)),
                    totalBytes: sqlite3_column_int64(statement, 1),
                    freeBytes: sqlite3_column_int64(statement, 2)
                ))
            case SQLITE_DONE: return rows
            default: throw error()
            }
        }
    }

    public func containsHour(at date: Date, calendar: Calendar = .current) throws -> Bool {
        let statement = try prepare("SELECT 1 FROM samples WHERE hour = ?;")
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_int64(statement, 1, Int64(HourlySchedule.start(of: date, calendar: calendar).timeIntervalSince1970))
        switch sqlite3_step(statement) {
        case SQLITE_ROW: return true
        case SQLITE_DONE: return false
        default: throw error()
        }
    }

    private func error() -> DiskPulseError {
        .database(String(cString: sqlite3_errmsg(database)))
    }

    private func execute(_ sql: String) throws {
        guard sqlite3_exec(database, sql, nil, nil, nil) == SQLITE_OK else { throw error() }
    }

    private func prepare(_ sql: String) throws -> OpaquePointer {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw error()
        }
        return statement
    }
}

public actor Recorder {
    public static var defaultDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("DiskPulse", isDirectory: true)
    }

    private let directory: URL
    private var store: HistoryStore?

    public init(directory: URL = Recorder.defaultDirectory) { self.directory = directory }

    private func database() throws -> HistoryStore {
        if let store { return store }
        let opened = try HistoryStore(url: directory.appendingPathComponent("history.sqlite"))
        store = opened
        return opened
    }

    @discardableResult
    public func capture(force: Bool = false, at date: Date = Date()) throws -> DiskSample? {
        let database = try database()
        if !force, try database.containsHour(at: date) { return nil }
        let sample = try DiskReader.read(at: date)
        try database.save(sample)
        return sample
    }

    public func history(since date: Date = Date().addingTimeInterval(-30 * 86_400)) throws -> [DiskSample] {
        try database().samples(since: date)
    }

    public func export(to url: URL) throws {
        let samples = try database().samples()
        try CSVExport.text(samples).write(to: url, atomically: true, encoding: .utf8)
    }
}

public enum CSVExport {
    public static func text(_ samples: [DiskSample]) -> String {
        let format = ISO8601DateFormatter()
        var text = "recorded_at_utc,total_bytes,used_bytes,free_bytes,used_percent\n"
        for sample in samples {
            text += "\(format.string(from: sample.date)),\(sample.totalBytes),\(sample.usedBytes),\(sample.freeBytes),\(String(format: "%.4f", locale: Locale(identifier: "en_US_POSIX"), sample.fraction * 100))\n"
        }
        return text
    }
}

public struct HistoryPoint: Identifiable, Sendable {
    public let sample: DiskSample
    public let segment: Int
    public var id: Date { sample.date }

    public static func make(from samples: [DiskSample]) -> [HistoryPoint] {
        var segment = 0
        var previous: Date?
        return samples.map { sample in
            if let previous,
               HourlySchedule.start(of: sample.date).timeIntervalSince(HourlySchedule.start(of: previous)) > 3_601 {
                segment += 1
            }
            previous = sample.date
            return HistoryPoint(sample: sample, segment: segment)
        }
    }
}
