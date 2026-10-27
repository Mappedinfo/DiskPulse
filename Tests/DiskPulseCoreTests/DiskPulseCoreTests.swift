import Foundation
import Testing
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
    #expect(csv == "recorded_at_utc,total_bytes,used_bytes,free_bytes,used_percent\n2026-10-27T10:01:00Z,100,60,40,60.0000\n")
    #expect(CSVExport.text([]).split(separator: "\n").count == 1)
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
