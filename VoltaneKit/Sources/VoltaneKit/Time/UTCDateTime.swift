import Foundation

/// 系统时间：服务端存 UTC 且不带时区（`created_at`、`updated_at`、`deleted_at`、邀请的 `expires_at`、动态日志时间），按 UTC 解析后显示成本地时间。
public struct UTCDateTime: Hashable, Comparable, Sendable, Codable {
    public let date: Date

    public init(date: Date) { self.date = date }

    public init?(_ text: String) {
        guard let s = Stamp(text) else { return nil }
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0)!
        guard let base = cal.date(from: s.components()) else { return nil }
        self.date = base.addingTimeInterval(-Double((s.offsetMinutes ?? 0) * 60))
    }

    public init(from decoder: Decoder) throws {
        let text = try decoder.singleValueContainer().decode(String.self)
        guard let v = UTCDateTime(text) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "无法解析系统时间 \(text)"))
        }
        self = v
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(wire)
    }

    /// `YYYY-MM-DDTHH:MM:SSZ`
    public var wire: String {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0)!
        let c = cal.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        return String(format: "%04d-%02d-%02dT%02d:%02d:%02dZ", c.year!, c.month!, c.day!, c.hour!, c.minute!, c.second!)
    }

    /// 设备时区下的墙上时间，用于显示。
    public func local(calendar: Calendar = .current) -> LocalDateTime {
        LocalDateTime(date: date, calendar: calendar)
    }

    public static func < (a: UTCDateTime, b: UTCDateTime) -> Bool { a.date < b.date }
}
