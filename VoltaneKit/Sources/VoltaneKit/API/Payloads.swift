import Foundation

/// 提交给 `/api/records` 的请求体。可选字段一律显式写成 null，编辑时服务端按整条替换处理。
public struct RecordPayload: Encodable, Sendable, Equatable {
    public var vehicleId: Int
    public var kind: String
    public var status = "done"
    public var occurredAt: LocalDateTime
    public var odometerKm: Double?
    public var odometerEstimated = false
    public var source = "manual"
    public var note = ""
    public var missedBefore = false
    public var amountCents: Int?
    public var extraFeeCents: Int?
    public var socBeforePct: Double?
    public var fuelLevelBeforePct: Double?
    public var placeId: Int?
    public var placeName: String?
    public var lat: Double?
    public var lng: Double?
    public var fuelGrade: String?
    public var fuelLiters: Double?
    public var fuelUnitPrice: Double?
    public var fuelIsFull = false
    public var fuelLevelAfterPct: Double?
    public var chargeType: String?
    public var chargeKwh: Double?
    public var chargeUnitPrice: Double?
    public var chargeToLimit = false
    public var socAfterPct: Double?
    public var chargeMinutes: Int?
    public var energyFeeCents: Int?
    public var serviceFeeCents: Int?
    public var snapshotTag: String?
    public var estimatedFields: [String] = []
    public var clientId: String?
    public var version: Int?
    public var force = false

    public init(vehicleId: Int, kind: String, occurredAt: LocalDateTime) {
        self.vehicleId = vehicleId; self.kind = kind; self.occurredAt = occurredAt
    }

    private enum Keys: String, CodingKey {
        case vehicleId = "vehicle_id", kind, status, occurredAt = "occurred_at", odometerKm = "odometer_km"
        case odometerEstimated = "odometer_estimated", source, note, missedBefore = "missed_before"
        case amountCents = "amount_cents"
        case extraFeeCents = "extra_fee_cents", socBeforePct = "soc_before_pct", fuelLevelBeforePct = "fuel_level_before_pct"
        case placeId = "place_id", placeName = "place_name", lat, lng, fuelGrade = "fuel_grade", fuelLiters = "fuel_liters"
        case fuelUnitPrice = "fuel_unit_price", fuelIsFull = "fuel_is_full", fuelLevelAfterPct = "fuel_level_after_pct"
        case chargeType = "charge_type", chargeKwh = "charge_kwh", chargeUnitPrice = "charge_unit_price"
        case chargeToLimit = "charge_to_limit", socAfterPct = "soc_after_pct", chargeMinutes = "charge_minutes"
        case energyFeeCents = "energy_fee_cents", serviceFeeCents = "service_fee_cents", snapshotTag = "snapshot_tag"
        case estimatedFields = "estimated_fields", clientId = "client_id", version, force
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: Keys.self)
        try c.encode(vehicleId, forKey: .vehicleId)
        try c.encode(kind, forKey: .kind)
        try c.encode(status, forKey: .status)
        try c.encode(occurredAt, forKey: .occurredAt)
        try c.encode(odometerKm, forKey: .odometerKm)
        try c.encode(odometerEstimated, forKey: .odometerEstimated)
        try c.encode(source, forKey: .source)
        try c.encode(note, forKey: .note)
        try c.encode(missedBefore, forKey: .missedBefore)
        try c.encode(amountCents, forKey: .amountCents)
        try c.encode(extraFeeCents, forKey: .extraFeeCents)
        try c.encode(socBeforePct, forKey: .socBeforePct)
        try c.encode(fuelLevelBeforePct, forKey: .fuelLevelBeforePct)
        try c.encode(placeId, forKey: .placeId)
        try c.encode(placeName, forKey: .placeName)
        try c.encode(lat, forKey: .lat)
        try c.encode(lng, forKey: .lng)
        try c.encode(fuelGrade, forKey: .fuelGrade)
        try c.encode(fuelLiters, forKey: .fuelLiters)
        try c.encode(fuelUnitPrice, forKey: .fuelUnitPrice)
        try c.encode(fuelIsFull, forKey: .fuelIsFull)
        try c.encode(fuelLevelAfterPct, forKey: .fuelLevelAfterPct)
        try c.encode(chargeType, forKey: .chargeType)
        try c.encode(chargeKwh, forKey: .chargeKwh)
        try c.encode(chargeUnitPrice, forKey: .chargeUnitPrice)
        try c.encode(chargeToLimit, forKey: .chargeToLimit)
        try c.encode(socAfterPct, forKey: .socAfterPct)
        try c.encode(chargeMinutes, forKey: .chargeMinutes)
        try c.encode(energyFeeCents, forKey: .energyFeeCents)
        try c.encode(serviceFeeCents, forKey: .serviceFeeCents)
        try c.encode(snapshotTag, forKey: .snapshotTag)
        try c.encode(estimatedFields, forKey: .estimatedFields)
        try c.encode(clientId, forKey: .clientId)
        try c.encode(version, forKey: .version)
        try c.encode(force, forKey: .force)
    }
}

/// 提交给 `/api/expenses` 的请求体。
public struct ExpensePayload: Encodable, Sendable, Equatable {
    public struct SubItem: Codable, Sendable, Equatable {
        public var name: String
        public var cents: Int
        public init(name: String, cents: Int) { self.name = name; self.cents = cents }
    }

    public var vehicleId: Int
    public var category: String
    public var title = ""
    public var occurredAt: LocalDateTime
    public var odometerKm: Double?
    public var amountCents: Int
    public var vendor = ""
    public var note = ""
    public var periodStart: LocalDateTime?
    public var periodEnd: LocalDateTime?
    public var subItems: [SubItem] = []
    public var clientId: String?
    public var version: Int?

    public init(vehicleId: Int, category: String, occurredAt: LocalDateTime, amountCents: Int) {
        self.vehicleId = vehicleId; self.category = category; self.occurredAt = occurredAt; self.amountCents = amountCents
    }

    private enum Keys: String, CodingKey {
        case vehicleId = "vehicle_id", category, title, occurredAt = "occurred_at", odometerKm = "odometer_km"
        case amountCents = "amount_cents", vendor, note, periodStart = "period_start"
        case periodEnd = "period_end", subItems = "sub_items", clientId = "client_id", version
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: Keys.self)
        try c.encode(vehicleId, forKey: .vehicleId)
        try c.encode(category, forKey: .category)
        try c.encode(title, forKey: .title)
        try c.encode(occurredAt, forKey: .occurredAt)
        try c.encode(odometerKm, forKey: .odometerKm)
        try c.encode(amountCents, forKey: .amountCents)
        try c.encode(vendor, forKey: .vendor)
        try c.encode(note, forKey: .note)
        try c.encode(periodStart.map { LocalDateTime(year: $0.year, month: $0.month, day: $0.day, hasTime: false) }, forKey: .periodStart)
        try c.encode(periodEnd.map { LocalDateTime(year: $0.year, month: $0.month, day: $0.day, hasTime: false) }, forKey: .periodEnd)
        try c.encode(subItems, forKey: .subItems)
        try c.encode(clientId, forKey: .clientId)
        try c.encode(version, forKey: .version)
    }
}
