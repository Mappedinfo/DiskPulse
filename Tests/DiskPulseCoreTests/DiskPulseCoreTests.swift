import Foundation
import Testing
import SQLite3
@testable import DiskPulseCore

private func utcCalendar() -> Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    return calendar
}

private func date(_ string: String) -> Date { ISO8601DateFormatter().date(from: string)! }

private func sample(_ timestamp: String, free: Int64 = 40) throws -> DiskSample {
    try DiskSample(date: date(timestamp), totalBytes: 100, freeBytes: free)
}

private func withStore(_ body: (URL) throws -> Void) throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("DiskPulseTests-\(UUID())")
    defer { try? FileManager.default.removeItem(at: directory) }
    try body(directory.appendingPathComponent("history.sqlite"))
}

@Test func capacityRejectsImpossibleValues() throws {
    #expect(throws: DiskPulseError.self) { try DiskSample(date: Date(), totalBytes: 0, freeBytes: 0) }
    #expect(throws: DiskPulseError.self) { try DiskSample(date: Date(), totalBytes: 10, freeBytes: 11) }
    #expect(throws: DiskPulseError.self) { try DiskSample(date: Date(), totalBytes: 10, freeBytes: -1) }
    #expect(try sample("2026-10-27T10:10:00Z").usedBytes == 60)
}

@Test func repeatedSamplesUpdateOneHourAndSurviveReopen() throws {
    try withStore { url in
        do {
            let store = try HistoryStore(url: url)
            try store.save(sample("2026-10-27T10:01:00Z"), calendar: utcCalendar())
            try store.save(sample("2026-10-27T10:59:00Z", free: 35), calendar: utcCalendar())
            try store.save(sample("2026-10-27T11:00:01Z", free: 30), calendar: utcCalendar())
        }
        let reopened = try HistoryStore(url: url)
        let rows = try reopened.samples()
        #expect(rows.count == 2)
        #expect(rows.first?.freeBytes == 35)
        #expect(rows.last?.usedBytes == 70)
        #expect(try reopened.containsHour(at: date("2026-10-27T10:20:00Z"), calendar: utcCalendar()))
        #expect(try reopened.samples(since: date("2026-10-27T11:00:00Z")).count == 1)
    }
}

@Test func wakeGapNeverCreatesSyntheticRows() throws {
    try withStore { url in
        let store = try HistoryStore(url: url)
        try store.save(sample("2026-10-27T10:01:00Z"), calendar: utcCalendar())
        try store.save(sample("2026-10-27T18:23:00Z"), calendar: utcCalendar())
        let rows = try store.samples()
        #expect(rows.count == 2)
        #expect(try !store.containsHour(at: date("2026-10-27T14:00:00Z"), calendar: utcCalendar()))
        #expect(HistoryPoint.make(from: rows).map(\.segment) == [0, 1])
    }
}

@Test func nextHourHandlesBoundaryAndHalfHourTimeZone() {
    let calendar = utcCalendar()
    #expect(HourlySchedule.next(after: date("2026-10-27T10:00:00Z"), calendar: calendar) == date("2026-10-27T11:00:00Z"))
    #expect(HourlySchedule.next(after: date("2026-10-27T10:59:59Z"), calendar: calendar) == date("2026-10-27T11:00:00Z"))
    var india = utcCalendar()
    india.timeZone = TimeZone(identifier: "Asia/Kolkata")!
    #expect(HourlySchedule.next(after: date("2026-10-27T10:01:00Z"), calendar: india) == date("2026-10-27T10:30:00Z"))
}

@Test func repeatedDSTHourHasDistinctBuckets() throws {
    var calendar = utcCalendar()
    calendar.timeZone = TimeZone(identifier: "America/New_York")!
    let before = date("2026-11-01T05:30:00Z")
    let after = date("2026-11-01T06:30:00Z")
    #expect(HourlySchedule.start(of: before, calendar: calendar) != HourlySchedule.start(of: after, calendar: calendar))
    try withStore { url in
        let store = try HistoryStore(url: url)
        try store.save(sample("2026-11-01T05:30:00Z"), calendar: calendar)
        try store.save(sample("2026-11-01T06:30:00Z"), calendar: calendar)
        #expect(try store.samples().count == 2)
    }
}

@Test func csvPreservesExactBytesAndUTCTime() throws {
    let csv = CSVExport.text([try sample("2026-10-27T10:01:00Z")])
    #expect(csv == "recorded_at_utc,total_bytes,used_bytes,free_bytes,used_percent,available_bytes,estimated_reclaimable_bytes,physical_used_bytes,capacity_basis\n2026-10-27T10:01:00Z,100,60,40,60.0000,,,60,physical_free\n")
    #expect(CSVExport.text([]).split(separator: "\n").count == 1)
}

@Test func reclaimableCapacityIsNotCountedAsDailyUsage() throws {
    let reading = try DiskSample(date: Date(), totalBytes: 1_000_000_000_000,
                                 freeBytes: 10_000_000_000, availableBytes: 360_000_000_000)
    #expect(reading.usedBytes == 640_000_000_000)
    #expect(reading.physicalUsedBytes == 990_000_000_000)
    #expect(reading.estimatedReclaimableBytes == 350_000_000_000)
    #expect(reading.fraction == 0.64)
    #expect(reading.capacityBasis == "important_usage_available")
}

@Test func missingEstimateStaysExplicitAndInvalidEstimatesFail() throws {
    let legacy = try sample("2026-10-27T10:01:00Z")
    #expect(legacy.availableBytes == nil)
    #expect(legacy.estimatedReclaimableBytes == nil)
    #expect(legacy.usedBytes == legacy.physicalUsedBytes)
    #expect(HistoryMetric.estimatedUsed.bytes(for: legacy) == nil)
    #expect(throws: DiskPulseError.self) {
        try DiskSample(date: Date(), totalBytes: 100, freeBytes: 10, availableBytes: 101)
    }
    #expect(throws: DiskPulseError.self) {
        try DiskSample(date: Date(), totalBytes: 100, freeBytes: 10, availableBytes: -1)
    }
}

private func legacyDatabase(at url: URL, version: Int = 1) throws {
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    var database: OpaquePointer?
    try #require(sqlite3_open(url.path, &database) == SQLITE_OK)
    defer { sqlite3_close(database) }
    let timestamp = date("2026-10-27T10:00:00Z").timeIntervalSince1970
    try #require(sqlite3_exec(database, """
        CREATE TABLE samples(hour INTEGER PRIMARY KEY, recorded_at REAL NOT NULL,
                             total_bytes INTEGER NOT NULL, free_bytes INTEGER NOT NULL);
        INSERT INTO samples VALUES (\(Int64(timestamp)), \(timestamp), 100, 10);
        PRAGMA user_version=\(version);
        """, nil, nil, nil) == SQLITE_OK)
}

@Test func versionOneMigrationPreservesHistoryAndPersistsNewEstimates() throws {
    try withStore { url in
        try legacyDatabase(at: url)
        do {
            let store = try HistoryStore(url: url)
            let old = try #require(store.samples().first)
            #expect(old.freeBytes == 10 && old.usedBytes == 90)
            #expect(old.availableBytes == nil)
            try store.save(DiskSample(date: date("2026-10-27T11:00:00Z"), totalBytes: 100,
                                      freeBytes: 10, availableBytes: 36), calendar: utcCalendar())
        }
        let store = try HistoryStore(url: url)
        let rows = try store.samples()
        #expect(rows.count == 2)
        #expect(rows[0].availableBytes == nil)
        #expect(rows[1].availableBytes == 36 && rows[1].freeBytes == 10 && rows[1].usedBytes == 64)
        // 零是有效读数，不能误读成旧版的缺失值。
        try store.save(DiskSample(date: date("2026-10-27T11:15:00Z"), totalBytes: 100,
                                  freeBytes: 0, availableBytes: 0), calendar: utcCalendar())
        #expect(try store.samples().last?.availableBytes == 0)
    }
}

@Test func futureDatabaseVersionIsNotDowngraded() throws {
    try withStore { url in
        try legacyDatabase(at: url, version: 99)
        #expect(throws: DiskPulseError.self) { _ = try HistoryStore(url: url) }
        var database: OpaquePointer?
        try #require(sqlite3_open(url.path, &database) == SQLITE_OK)
        defer { sqlite3_close(database) }
        var statement: OpaquePointer?
        try #require(sqlite3_prepare_v2(database, "PRAGMA user_version;", -1, &statement, nil) == SQLITE_OK)
        defer { sqlite3_finalize(statement) }
        try #require(sqlite3_step(statement) == SQLITE_ROW)
        #expect(sqlite3_column_int(statement, 0) == 99)
    }
}

@Test func historyNeverMixesPhysicalAndEstimatedUsage() throws {
    let old = try sample("2026-10-27T10:01:00Z", free: 10)
    let new = try DiskSample(date: date("2026-10-27T11:01:00Z"), totalBytes: 100, freeBytes: 10, availableBytes: 36)
    let adjusted = HistoryPoint.make(from: [old, new], metric: .estimatedUsed)
    #expect(adjusted.count == 1 && adjusted.first?.bytes == 64)
    let physical = HistoryPoint.make(from: [old, new], metric: .physicalUsed)
    #expect(physical.map(\.bytes) == [90, 90])
    #expect(physical.map(\.segment) == [0, 0])
}

@Test func exportsIncludeBothCapacityMeanings() throws {
    let reading = try DiskSample(date: date("2026-10-27T10:01:00Z"), totalBytes: 100,
                                 freeBytes: 10, availableBytes: 36)
    let csv = CSVExport.text([reading])
    #expect(csv.hasSuffix("2026-10-27T10:01:00Z,100,64,10,64.0000,36,26,90,important_usage_available\n"))
    let data = try JSONEncoder().encode(reading)
    let json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    #expect(json["usedBytes"] as? Int == 64)
    #expect(json["physicalUsedBytes"] as? Int == 90)
    #expect(try JSONDecoder().decode(DiskSample.self, from: data) == reading)
}

@Test func corruptHistoryIsNotSilentlyReset() throws {
    try withStore { url in
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let original = Data("this is not a database".utf8)
        try original.write(to: url)
        #expect(throws: DiskPulseError.self) { _ = try HistoryStore(url: url) }
        #expect(try Data(contentsOf: url) == original)
    }
}

@Test func gapSegmentsDoNotBreakContinuousHours() throws {
    let points = HistoryPoint.make(from: [
        try sample("2026-10-27T10:01:00Z"),
        try sample("2026-10-27T11:59:20Z"),
        try sample("2026-10-27T13:00:10Z")
    ])
    #expect(points.map(\.segment) == [0, 0, 1])
}
