import Foundation

public struct DiskSample: Codable, Identifiable, Equatable, Sendable {
    public let date: Date
    public let totalBytes: Int64
    public let freeBytes: Int64
    public var id: Date { date }
    public var usedBytes: Int64 { totalBytes - freeBytes }
    public var fraction: Double { Double(usedBytes) / Double(totalBytes) }

    public init(date: Date, totalBytes: Int64, freeBytes: Int64) throws {
        guard totalBytes > 0, freeBytes >= 0, freeBytes <= totalBytes,
              date.timeIntervalSince1970.isFinite else {
            throw DiskPulseError.invalidCapacity
        }
        self.date = date
        self.totalBytes = totalBytes
        self.freeBytes = freeBytes
    }
}

public enum DiskPulseError: LocalizedError {
    case invalidCapacity
    case database(String)

    public var errorDescription: String? {
        switch self {
        case .invalidCapacity: "暂时无法读取磁盘容量，请稍后重试。"
        case .database(let detail): "无法读写容量记录：\(detail)"
        }
    }
}

public enum HourlySchedule {
    public static func start(of date: Date, calendar: Calendar = .current) -> Date {
        calendar.dateInterval(of: .hour, for: date)!.start
    }

    public static func next(after date: Date, calendar: Calendar = .current) -> Date {
        calendar.dateInterval(of: .hour, for: date)!.end
    }
}

public enum DiskReader {
    // 读取启动磁盘的数据卷容量元数据；不遍历文件，也不读取文件内容。
    public static func read(at date: Date = Date()) throws -> DiskSample {
        let dataVolume = URL(fileURLWithPath: "/System/Volumes/Data", isDirectory: true)
        let url = FileManager.default.fileExists(atPath: dataVolume.path)
            ? dataVolume : URL(fileURLWithPath: "/", isDirectory: true)
        let values = try url.resourceValues(forKeys: [.volumeTotalCapacityKey, .volumeAvailableCapacityKey])
        guard let total = values.volumeTotalCapacity, let free = values.volumeAvailableCapacity else {
            throw DiskPulseError.invalidCapacity
        }
        return try DiskSample(date: date, totalBytes: Int64(total), freeBytes: Int64(free))
    }
}

public enum CapacityFormat {
    public static func bytes(_ value: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: value, countStyle: .decimal)
    }

    public static func change(_ value: Int64) -> String {
        (value > 0 ? "+" : value < 0 ? "−" : "") + bytes(abs(value))
    }
}
