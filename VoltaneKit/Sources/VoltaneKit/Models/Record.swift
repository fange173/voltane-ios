import Foundation

/// 加油、充电、快照记录。时间字段按业务时间和系统时间区分类型。
public struct Record: Codable, Sendable, Hashable, Identifiable {
    public let id: Int
    public let vehicleId: Int
    public var type: String?
    public var kind: String
    public var status: String?
    public var occurredAt: LocalDateTime
    public var odometerKm: Double?
    public var odometerEstimated: Bool?
    public var source: String?
    public var estimatedFields: [String]?
    public var fuelGrade: String?
    public var fuelLiters: Double?
    public var fuelUnitPrice: Double?
    public var fuelIsFull: Bool?
    public var fuelLevelBeforePct: Double?
    public var fuelLevelAfterPct: Double?
    public var chargeType: String?
    public var chargeKwh: Double?
    public var chargeUnitPrice: Double?
    public var chargeMinutes: Int?
    public var chargeToLimit: Bool?
    public var energyFeeCents: Int?
    public var serviceFeeCents: Int?
    public var socBeforePct: Double?
    public var socAfterPct: Double?
    public var amountCents: Int?
    public var extraFeeCents: Int?
    public var placeId: Int?
    public var placeName: String?
    public var lat: Double?
    public var lng: Double?
    public var missedBefore: Bool?
    public var snapshotTag: String?
    public var note: String?
    public var version: Int?
    public var clientId: String?
    public var createdAt: UTCDateTime?
    public var updatedAt: UTCDateTime?
    public var deletedAt: UTCDateTime?
    public var createdBy: UserBrief?
    public var updatedBy: UserBrief?
    public var badges: [Badge]?
    public var canEdit: Bool?
    public var canDelete: Bool?
    public var segments: [Segment]?

    public var isInProgress: Bool { status == "in_progress" }
    public var isOdometerEstimated: Bool { odometerEstimated == true }
    public var estimated: Set<String> { Set(estimatedFields ?? []) }

    public struct Badge: Codable, Sendable, Hashable {
        public let energy: String
        public let kind: String
        public let quality: String
        public let tag: String?
        public let anomaly: String?
        public let excluded: Bool?
        public let per100: Double?
        public let perDay: Double?
    }
}

public struct Expense: Codable, Sendable, Hashable, Identifiable {
    public let id: Int
    public let vehicleId: Int
    public var type: String?
    public var category: String
    public var title: String?
    public var occurredAt: LocalDateTime
    public var odometerKm: Double?
    public var amountCents: Int
    public var vendor: String?
    public var periodStart: LocalDateTime?
    public var periodEnd: LocalDateTime?
    public var subItems: [SubItem]?
    public var note: String?
    public var version: Int?
    public var clientId: String?
    public var deletedAt: UTCDateTime?
    public var createdBy: UserBrief?
    public var badges: [Record.Badge]?
    public var canEdit: Bool?
    public var canDelete: Bool?

    public struct SubItem: Codable, Sendable, Hashable {
        public let name: String
        public let cents: Int
    }
}

/// 时间线条目：记录或费用。
public enum TimelineItem: Decodable, Sendable, Hashable, Identifiable {
    case record(Record)
    case expense(Expense)

    private enum Keys: String, CodingKey { case type }

    public init(from decoder: Decoder) throws {
        let t = try decoder.container(keyedBy: Keys.self).decodeIfPresent(String.self, forKey: .type)
        if t == "expense" { self = .expense(try Expense(from: decoder)) } else { self = .record(try Record(from: decoder)) }
    }

    public var id: String {
        switch self { case .record(let r): "r\(r.id)"; case .expense(let e): "e\(e.id)" }
    }
    public var occurredAt: LocalDateTime {
        switch self { case .record(let r): r.occurredAt; case .expense(let e): e.occurredAt }
    }
    public var vehicleId: Int {
        switch self { case .record(let r): r.vehicleId; case .expense(let e): e.vehicleId }
    }
}

public struct TimelinePage: Decodable, Sendable {
    public let items: [TimelineItem]
    public let next: LocalDateTime?
}

public struct SaveResult: Decodable, Sendable {
    public let record: Record
    public let segments: [Segment]?
    public let warnings: [String]?
    public let replayed: Bool?
}

public struct ExpenseSaveResult: Decodable, Sendable {
    public let expense: Expense?
    public let replayed: Bool?
    public let insuranceReminder: InsuranceReminder?
    public let suggestComplete: [SuggestedReminder]?

    public struct InsuranceReminder: Decodable, Sendable, Hashable {
        public let title: String
        public let dueDate: LocalDateTime?
    }

    public struct SuggestedReminder: Decodable, Sendable, Hashable {
        public let id: Int
        public let title: String
    }
}

public struct Segment: Codable, Sendable, Hashable {
    public var amount: Double?
    public var anomaly: String?
    public var costCents: Int?
    public var costPerKm: Double?
    public var days: Double?
    public var distance: Double?
    public var elecErr: Double?
    public var elecKwh: Double?
    public var elecPer100: Double?
    public var elecQuality: String?
    public var elecShare: Double?
    public var endId: Int?
    public var endOdo: Double?
    public var endTs: LocalDateTime?
    public var energy: String
    public var equivPer100: Double?
    public var err: Double?
    public var err100: Double?
    public var excluded: Bool?
    public var kind: String?
    public var per100: Double?
    public var perDay: Double?
    public var prevPer100: Double?
    public var quality: String?
    public var recordIds: [Int]?
    public var startId: Int?
    public var startOdo: Double?
    public var startTs: LocalDateTime?
    public var status: String?
    public var tag: String?
    public var explain: Explain?

    public struct Explain: Codable, Sendable, Hashable {
        public var distance: Double?
        public var parts: [Part]?
    }

    public struct Part: Codable, Sendable, Hashable {
        public var text: String?
        public var energy: String?
        public var start: String?
        public var end: String?
        public var startValue: Double?
        public var endValue: Double?
        public var added: Double?
        public var amount: Double?
        public var unit: String?
        public var k: Double?
    }
}
