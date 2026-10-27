import Foundation

/// 业务时间：服务端本地时间，不带时区，按墙上时间原样往返（`occurred_at`、`due_date`、`delivery_date` 等）。
public struct LocalDateTime: Hashable, Comparable, Sendable, Codable, CustomStringConvertible {
    public let year: Int
    public let month: Int
    public let day: Int
    public let hour: Int
    public let minute: Int
    public let hasTime: Bool

    public init(year: Int, month: Int, day: Int, hour: Int = 0, minute: Int = 0, hasTime: Bool = true) {
        self.year = year; self.month = month; self.day = day
        self.hour = hour; self.minute = minute; self.hasTime = hasTime
    }

    public init?(_ text: String) {
        guard let s = Stamp(text) else { return nil }
        self.init(year: s.year, month: s.month, day: s.day, hour: s.hour, minute: s.minute, hasTime: s.hasTime)
    }

    /// 设备时区下的墙上时间。
    public init(date: Date, calendar: Calendar = .current) {
        let c = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        self.init(year: c.year!, month: c.month!, day: c.day!, hour: c.hour!, minute: c.minute!)
    }

    public init(from decoder: Decoder) throws {
        let text = try decoder.singleValueContainer().decode(String.self)
        guard let v = LocalDateTime(text) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "无法解析业务时间 \(text)"))
        }
        self = v
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(wire)
    }

    /// 提交给服务端的格式：有时间为 `YYYY-MM-DDTHH:MM`，只有日期为 `YYYY-MM-DD`。
    public var wire: String {
        let d = String(format: "%04d-%02d-%02d", year, month, day)
        return hasTime ? d + String(format: "T%02d:%02d", hour, minute) : d
    }

    public var description: String { wire }
    public var dateOnly: String { String(wire.prefix(10)) }
    public var monthKey: String { String(wire.prefix(7)) }
    public var timeText: String { String(format: "%02d:%02d", hour, minute) }

    public func date(calendar: Calendar = .current) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute)) ?? Date()
    }

    public static func < (a: LocalDateTime, b: LocalDateTime) -> Bool {
        (a.year, a.month, a.day, a.hour, a.minute) < (b.year, b.month, b.day, b.hour, b.minute)
    }

    /// 分钟数差（self − other），按同一时区的墙上时间计算。
    public func minutes(since other: LocalDateTime, calendar: Calendar = .current) -> Int {
        Int((date(calendar: calendar).timeIntervalSince(other.date(calendar: calendar)) / 60).rounded())
    }

    public func addingDays(_ days: Int, calendar: Calendar = .current) -> LocalDateTime {
        var cal = calendar
        cal.timeZone = calendar.timeZone
        let d = cal.date(byAdding: .day, value: days, to: date(calendar: calendar)) ?? date(calendar: calendar)
        var r = LocalDateTime(date: d, calendar: calendar)
        if !hasTime { r = LocalDateTime(year: r.year, month: r.month, day: r.day, hasTime: false) }
        return r
    }
}
