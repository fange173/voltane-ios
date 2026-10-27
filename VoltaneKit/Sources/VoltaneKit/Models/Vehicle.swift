import Foundation

public struct Vehicle: Codable, Sendable, Hashable, Identifiable {
    public let id: Int
    public var name: String
    public var plate: String?
    public var brand: String?
    public var model: String?
    public var year: Int?
    public var energyType: String
    public var energyLabel: String?
    public var tankCapacityL: Double?
    public var batteryUsableKwh: Double?
    public var chargeLimitPct: Double?
    public var defaultFuelGrade: String?
    public var defaultChargeType: String?
    public var fuelGaugeMode: String?
    public var fuelGaugeBars: Int?
    public var factoryFuelL: Double?
    public var recordStyle: String?
    public var initialOdometerKm: Double?
    public var deliveryDate: LocalDateTime?
    public var purchasePriceCents: Int?
    public var color: String?
    public var calcSettings: [String: JSONValue]?
    public var isArchived: Bool
    public var hasFuel: Bool
    public var hasElec: Bool
    public var role: String?
    public var dataVersion: Int?
    public var memberCount: Int?
    public var latestOdo: Double?

    public var isOwner: Bool { role == "owner" }
    /// 车主和共同记录者在未归档的车辆上可以记账。
    public var canEdit: Bool { (role == "owner" || role == "editor") && !isArchived }
    public var displayLabel: String { energyLabel ?? Labels.energy[energyType] ?? energyType }

    public init(id: Int, name: String, energyType: String, hasFuel: Bool, hasElec: Bool, isArchived: Bool = false,
                role: String? = "owner", tankCapacityL: Double? = nil, batteryUsableKwh: Double? = nil,
                chargeLimitPct: Double? = 100, fuelGaugeMode: String? = "pct", fuelGaugeBars: Int? = nil,
                defaultFuelGrade: String? = "92", defaultChargeType: String? = "home", recordStyle: String? = "detailed") {
        self.id = id; self.name = name; self.energyType = energyType; self.hasFuel = hasFuel; self.hasElec = hasElec
        self.isArchived = isArchived; self.role = role; self.tankCapacityL = tankCapacityL
        self.batteryUsableKwh = batteryUsableKwh; self.chargeLimitPct = chargeLimitPct
        self.fuelGaugeMode = fuelGaugeMode; self.fuelGaugeBars = fuelGaugeBars
        self.defaultFuelGrade = defaultFuelGrade; self.defaultChargeType = defaultChargeType; self.recordStyle = recordStyle
    }
}
