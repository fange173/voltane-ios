import Foundation

/// `PUT /api/vehicles/{id}` 与新建车辆的车辆参数。可空字段一律显式写 null。
public struct VehiclePayload: Encodable, Sendable, Equatable {
    public var name = ""
    public var plate = ""
    public var brand = ""
    public var model = ""
    public var year: Int?
    public var energyType = "phev"
    public var tankCapacityL: Double?
    public var batteryUsableKwh: Double?
    public var chargeLimitPct = 100.0
    public var defaultFuelGrade = "92"
    public var defaultChargeType = "home"
    public var fuelGaugeMode = "pct"
    public var fuelGaugeBars: Int?
    public var factoryFuelL = 5.0
    public var recordStyle = "detailed"
    public var initialOdometerKm: Double?
    public var deliveryDate: LocalDateTime?
    public var purchasePriceCents: Int?
    public var color = "#4F46E5"
    public var calcSettings: [String: JSONValue] = [:]

    public init() {}

    enum Keys: String, CodingKey {
        case name, plate, brand, model, year, energyType = "energy_type", tankCapacityL = "tank_capacity_l"
        case batteryUsableKwh = "battery_usable_kwh", chargeLimitPct = "charge_limit_pct"
        case defaultFuelGrade = "default_fuel_grade", defaultChargeType = "default_charge_type"
        case fuelGaugeMode = "fuel_gauge_mode", fuelGaugeBars = "fuel_gauge_bars", factoryFuelL = "factory_fuel_l"
        case recordStyle = "record_style", initialOdometerKm = "initial_odometer_km", deliveryDate = "delivery_date"
        case purchasePriceCents = "purchase_price_cents", color, calcSettings = "calc_settings"
        case start, summary, reminders
    }

    func encodeFields(_ c: inout KeyedEncodingContainer<Keys>) throws {
        try c.encode(name, forKey: .name)
        try c.encode(plate, forKey: .plate)
        try c.encode(brand, forKey: .brand)
        try c.encode(model, forKey: .model)
        try c.encode(year, forKey: .year)
        try c.encode(energyType, forKey: .energyType)
        try c.encode(tankCapacityL, forKey: .tankCapacityL)
        try c.encode(batteryUsableKwh, forKey: .batteryUsableKwh)
        try c.encode(chargeLimitPct, forKey: .chargeLimitPct)
        try c.encode(defaultFuelGrade, forKey: .defaultFuelGrade)
        try c.encode(defaultChargeType, forKey: .defaultChargeType)
        try c.encode(fuelGaugeMode, forKey: .fuelGaugeMode)
        try c.encode(fuelGaugeBars, forKey: .fuelGaugeBars)
        try c.encode(factoryFuelL, forKey: .factoryFuelL)
        try c.encode(recordStyle, forKey: .recordStyle)
        try c.encode(initialOdometerKm, forKey: .initialOdometerKm)
        try c.encode(deliveryDate.map { LocalDateTime(year: $0.year, month: $0.month, day: $0.day, hasTime: false) }, forKey: .deliveryDate)
        try c.encode(purchasePriceCents, forKey: .purchasePriceCents)
        try c.encode(color, forKey: .color)
        try c.encode(calcSettings, forKey: .calcSettings)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: Keys.self)
        try encodeFields(&c)
    }
}

/// 新车向导提交的请求体：车辆参数加起点、历史汇总、提醒。
public struct VehicleCreatePayload: Encodable, Sendable, Equatable {
    public struct Start: Encodable, Sendable, Equatable {
        public var mode: String
        public var deliveryOdo: Double?
        public var deliveryFillL: Double?
        public var deliveryFillCents: Int?
        public var currentOdo: Double?
        public var currentFuelPct: Double?
        public var currentSoc: Double?

        enum Keys: String, CodingKey {
            case mode, deliveryOdo = "delivery_odo", deliveryFillL = "delivery_fill_l", deliveryFillCents = "delivery_fill_cents"
            case currentOdo = "current_odo", currentFuelPct = "current_fuel_pct", currentSoc = "current_soc"
        }

        public func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: Keys.self)
            try c.encode(mode, forKey: .mode)
            try c.encode(deliveryOdo, forKey: .deliveryOdo)
            try c.encode(deliveryFillL, forKey: .deliveryFillL)
            try c.encode(deliveryFillCents, forKey: .deliveryFillCents)
            try c.encode(currentOdo, forKey: .currentOdo)
            try c.encode(currentFuelPct, forKey: .currentFuelPct)
            try c.encode(currentSoc, forKey: .currentSoc)
        }
    }

    public struct Summary: Encodable, Sendable, Equatable {
        public var startDate: LocalDateTime?
        public var fuelLiters: Double?
        public var fuelCents: Int?
        public var fuelPrice: Double?
        public var elecKwh: Double?
        public var elecCents: Int?
        public var elecPrice: Double?

        enum Keys: String, CodingKey {
            case startDate = "start_date", fuelLiters = "fuel_liters", fuelCents = "fuel_cents", fuelPrice = "fuel_price"
            case elecKwh = "elec_kwh", elecCents = "elec_cents", elecPrice = "elec_price"
        }

        public func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: Keys.self)
            try c.encode(startDate, forKey: .startDate)
            try c.encode(fuelLiters, forKey: .fuelLiters)
            try c.encode(fuelCents, forKey: .fuelCents)
            try c.encode(fuelPrice, forKey: .fuelPrice)
            try c.encode(elecKwh, forKey: .elecKwh)
            try c.encode(elecCents, forKey: .elecCents)
            try c.encode(elecPrice, forKey: .elecPrice)
        }
    }

    public struct Reminder: Encodable, Sendable, Equatable {
        public var templateKey: String
        public var dueDate: LocalDateTime?
        public var dueOdometerKm: Double?
        public var intervalMonths: Int?
        public var intervalKm: Double?

        enum Keys: String, CodingKey {
            case templateKey = "template_key", dueDate = "due_date", dueOdometerKm = "due_odometer_km"
            case intervalMonths = "interval_months", intervalKm = "interval_km"
        }

        public func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: Keys.self)
            try c.encode(templateKey, forKey: .templateKey)
            try c.encode(dueDate, forKey: .dueDate)
            try c.encode(dueOdometerKm, forKey: .dueOdometerKm)
            try c.encode(intervalMonths, forKey: .intervalMonths)
            try c.encode(intervalKm, forKey: .intervalKm)
        }
    }

    public var vehicle: VehiclePayload
    public var start: Start?
    public var summary: Summary?
    public var reminders: [Reminder] = []

    public init(vehicle: VehiclePayload, start: Start? = nil, summary: Summary? = nil, reminders: [Reminder] = []) {
        self.vehicle = vehicle; self.start = start; self.summary = summary; self.reminders = reminders
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: VehiclePayload.Keys.self)
        try vehicle.encodeFields(&c)
        try c.encode(start, forKey: .start)
        try c.encode(summary, forKey: .summary)
        try c.encode(reminders, forKey: .reminders)
    }
}

/// 邀请码请求体：`days`、`maxUses` 为 nil 时显式写 null，表示长期有效、不限次数。
public struct InviteBody: Encodable, Sendable, Equatable {
    public var role: String
    public var days: Int?
    public var maxUses: Int?
    public var allowSignup: Bool

    public init(role: String = "editor", days: Int? = 7, maxUses: Int? = 1, allowSignup: Bool = false) {
        self.role = role; self.days = days; self.maxUses = maxUses; self.allowSignup = allowSignup
    }

    enum Keys: String, CodingKey { case role, days, maxUses = "max_uses", allowSignup = "allow_signup" }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: Keys.self)
        try c.encode(role, forKey: .role)
        try c.encode(days, forKey: .days)
        try c.encode(maxUses, forKey: .maxUses)
        try c.encode(allowSignup, forKey: .allowSignup)
    }
}

/// 历史 / 周期汇总的请求体。
public struct SummaryPayload: Encodable, Sendable, Equatable {
    public var vehicleId: Int
    public var startDate: LocalDateTime
    public var endDate: LocalDateTime
    public var mode = "extra"
    public var fuelLiters: Double?
    public var fuelCents: Int?
    public var fuelPrice: Double?
    public var elecKwh: Double?
    public var elecCents: Int?
    public var elecPrice: Double?
    public var note = ""
    public var version: Int?

    public init(vehicleId: Int, startDate: LocalDateTime, endDate: LocalDateTime) {
        self.vehicleId = vehicleId; self.startDate = startDate; self.endDate = endDate
    }

    enum Keys: String, CodingKey {
        case vehicleId = "vehicle_id", startDate = "start_date", endDate = "end_date", mode
        case fuelLiters = "fuel_liters", fuelCents = "fuel_cents", fuelPrice = "fuel_price"
        case elecKwh = "elec_kwh", elecCents = "elec_cents", elecPrice = "elec_price", note, version
    }

    public func encode(to encoder: Encoder) throws {
        func day(_ d: LocalDateTime) -> LocalDateTime { LocalDateTime(year: d.year, month: d.month, day: d.day, hasTime: false) }
        var c = encoder.container(keyedBy: Keys.self)
        try c.encode(vehicleId, forKey: .vehicleId)
        try c.encode(day(startDate), forKey: .startDate)
        try c.encode(day(endDate), forKey: .endDate)
        try c.encode(mode, forKey: .mode)
        try c.encode(fuelLiters, forKey: .fuelLiters)
        try c.encode(fuelCents, forKey: .fuelCents)
        try c.encode(fuelPrice, forKey: .fuelPrice)
        try c.encode(elecKwh, forKey: .elecKwh)
        try c.encode(elecCents, forKey: .elecCents)
        try c.encode(elecPrice, forKey: .elecPrice)
        try c.encode(note, forKey: .note)
        try c.encode(version, forKey: .version)
    }
}
