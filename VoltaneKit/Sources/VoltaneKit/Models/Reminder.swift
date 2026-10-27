import Foundation

public struct Reminder: Codable, Sendable, Hashable, Identifiable {
    public let id: Int
    public var vehicleId: Int?
    public var vehicleName: String?
    public var title: String
    public var templateKey: String?
    public var dueDate: LocalDateTime?
    public var dueOdometerKm: Double?
    public var intervalMonths: Int?
    public var intervalKm: Double?
    public var leadDays: Int?
    public var leadKm: Double?
    public var lastDoneAt: LocalDateTime?
    public var lastDoneOdometerKm: Double?
    public var isActive: Bool?
    public var note: String?
    public var currentOdo: Double?
    public var dateProgress: Double?
    public var daysLeft: Int?
    public var etaDate: LocalDateTime?
    public var kmLeft: Double?
    public var kmProgress: Double?
    public var muted: Bool?
    public var nextDate: LocalDateTime?
    public var personal: Bool?
    public var status: String?
}

public struct DueReminders: Decodable, Sendable {
    public let count: Int
    public let items: [Reminder]
}

public struct ReminderTemplate: Decodable, Sendable, Hashable {
    public let key: String
    public let title: String
    public var hint: String?
    public var intervalMonths: Int?
    public var intervalKm: Int?
    public var iceKm: Int?
    public var leadDays: Int?
    public var leadKm: Int?
    public var personal: Bool?
}
