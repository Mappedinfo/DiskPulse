import Foundation

public struct DiskSample: Codable, Identifiable, Equatable, Sendable {
    public let date: Date
    public let totalBytes: Int64
    public let freeBytes: Int64
    // nil 表示旧记录或系统未返回估算；不能用今天的估算倒推历史。
    public let availableBytes: Int64?
    public var id: Date { date }
    public var displayAvailableBytes: Int64 { availableBytes ?? freeBytes }
    public var usedBytes: Int64 { totalBytes - displayAvailableBytes }
    public var physicalUsedBytes: Int64 { totalBytes - freeBytes }
    public var estimatedReclaimableBytes: Int64? { availableBytes.map { max(0, $0 - freeBytes) } }
    public var capacityBasis: String { availableBytes == nil ? "physical_free" : "important_usage_available" }
    public var fraction: Double { Double(usedBytes) / Double(totalBytes) }

    public init(date: Date, totalBytes: Int64, freeBytes: Int64, availableBytes: Int64? = nil) throws {
        guard totalBytes > 0, freeBytes >= 0, freeBytes <= totalBytes,
              availableBytes.map({ $0 >= 0 && $0 <= totalBytes }) ?? true,
              date.timeIntervalSince1970.isFinite else {
            throw DiskPulseError.invalidCapacity
        }
        self.date = date
        self.totalBytes = totalBytes
        self.freeBytes = freeBytes
        self.availableBytes = availableBytes
    }

    private enum CodingKeys: String, CodingKey {
        case date, totalBytes, freeBytes, availableBytes, usedBytes, physicalUsedBytes
        case estimatedReclaimableBytes, capacityBasis
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(date: values.decode(Date.self, forKey: .date),
                      totalBytes: values.decode(Int64.self, forKey: .totalBytes),
                      freeBytes: values.decode(Int64.self, forKey: .freeBytes),
                      availableBytes: values.decodeIfPresent(Int64.self, forKey: .availableBytes))
    }

    public func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(date, forKey: .date)
        try values.encode(totalBytes, forKey: .totalBytes)
        try values.encode(freeBytes, forKey: .freeBytes)
        try values.encodeIfPresent(availableBytes, forKey: .availableBytes)
        try values.encode(usedBytes, forKey: .usedBytes)
        try values.encode(physicalUsedBytes, forKey: .physicalUsedBytes)
        try values.encodeIfPresent(estimatedReclaimableBytes, forKey: .estimatedReclaimableBytes)
        try values.encode(capacityBasis, forKey: .capacityBasis)
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
        // 单独读取估算键，失败时仍保留物理容量，并在界面明确标出回退口径。
        let estimate = try? url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
            .volumeAvailableCapacityForImportantUsage
        let available = estimate.flatMap { (0...Int64(total)).contains($0) ? $0 : nil }
        return try DiskSample(date: date, totalBytes: Int64(total), freeBytes: Int64(free), availableBytes: available)
    }
}

public enum HistoryMetric: String, CaseIterable, Identifiable, Sendable {
    case estimatedUsed, physicalUsed
    public var id: String { rawValue }
    public var title: String { self == .estimatedUsed ? "已用空间" : "物理占用" }

    public func bytes(for sample: DiskSample) -> Int64? {
        switch self {
        case .estimatedUsed: sample.availableBytes.map { sample.totalBytes - $0 }
        case .physicalUsed: sample.physicalUsedBytes
        }
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
