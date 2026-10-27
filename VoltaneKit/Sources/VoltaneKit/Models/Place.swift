import Foundation

/// 峰谷电价的一个时段，价格用 Decimal 保存。
public struct TariffItem: Codable, Sendable, Hashable {
    public let from: String
    public let to: String
    public let price: Decimal

    public init(from: String, to: String, price: Decimal) { self.from = from; self.to = to; self.price = price }

    private enum Keys: String, CodingKey { case from, to, price }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Keys.self)
        from = try c.decode(String.self, forKey: .from)
        to = try c.decode(String.self, forKey: .to)
        price = Decimal(shortest: try c.decode(Double.self, forKey: .price))
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: Keys.self)
        try c.encode(from, forKey: .from)
        try c.encode(to, forKey: .to)
        try c.encode(NSDecimalNumber(decimal: price).doubleValue, forKey: .price)
    }
}

public struct Place: Codable, Sendable, Hashable, Identifiable {
    public let id: Int?
    public var vehicleId: Int?
    public var shared: Bool?
    public var name: String
    public var kind: String?
    public var lat: Double?
    public var lng: Double?
    public var touTariff: [TariffItem]
    public var defaultChargeType: String?
    public var defaultFuelGrade: String?
    public var lastUnitPrice: Double?
    public var lastUsedAt: UTCDateTime?
    public var useCount: Int?
    public var sortOrder: Int?
    public var isHidden: Bool?

    public init(id: Int?, name: String, kind: String? = nil, touTariff: [TariffItem] = [], lat: Double? = nil, lng: Double? = nil,
                defaultChargeType: String? = nil, defaultFuelGrade: String? = nil, lastUnitPrice: Double? = nil) {
        self.id = id; self.name = name; self.kind = kind; self.touTariff = touTariff; self.lat = lat; self.lng = lng
        self.defaultChargeType = defaultChargeType; self.defaultFuelGrade = defaultFuelGrade; self.lastUnitPrice = lastUnitPrice
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(Int.self, forKey: .id)
        vehicleId = try c.decodeIfPresent(Int.self, forKey: .vehicleId)
        shared = try c.decodeIfPresent(Bool.self, forKey: .shared)
        name = try c.decode(String.self, forKey: .name)
        kind = try c.decodeIfPresent(String.self, forKey: .kind)
        lat = try c.decodeIfPresent(Double.self, forKey: .lat)
        lng = try c.decodeIfPresent(Double.self, forKey: .lng)
        touTariff = try c.decodeIfPresent([TariffItem].self, forKey: .touTariff) ?? []
        defaultChargeType = try c.decodeIfPresent(String.self, forKey: .defaultChargeType)
        defaultFuelGrade = try c.decodeIfPresent(String.self, forKey: .defaultFuelGrade)
        lastUnitPrice = try c.decodeIfPresent(Double.self, forKey: .lastUnitPrice)
        lastUsedAt = try c.decodeIfPresent(UTCDateTime.self, forKey: .lastUsedAt)
        useCount = try c.decodeIfPresent(Int.self, forKey: .useCount)
        sortOrder = try c.decodeIfPresent(Int.self, forKey: .sortOrder)
        isHidden = try c.decodeIfPresent(Bool.self, forKey: .isHidden)
    }
}

/// 打开表单时的预填：上次记录、校准系数、常用地点、最近备注。
public struct Prefill: Decodable, Sendable {
    public let k: Double?
    public let kSource: String?
    public let last: Record?
    public let lastOdo: Double?
    public let lastOdoTs: LocalDateTime?
    public let lastSoc: Double?
    public let lastFuelPct: Double?
    public var places: [Place]
    public let recentNotes: [String]
    public let inProgress: [Record]
    public let dailyKm: Double?
    /// 按时间排好的里程读数，补录时用来找所选时间前后的读数。
    public let odoPoints: [OdoPoint]

    public init(k: Double? = nil, last: Record? = nil, lastOdo: Double? = nil, lastOdoTs: LocalDateTime? = nil,
                lastSoc: Double? = nil, lastFuelPct: Double? = nil, places: [Place] = [], recentNotes: [String] = [],
                odoPoints: [OdoPoint] = []) {
        self.k = k; self.kSource = nil; self.last = last; self.lastOdo = lastOdo; self.lastOdoTs = lastOdoTs
        self.lastSoc = lastSoc; self.lastFuelPct = lastFuelPct; self.places = places; self.recentNotes = recentNotes
        self.inProgress = []; self.dailyKm = nil; self.odoPoints = odoPoints
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        k = try c.decodeIfPresent(Double.self, forKey: .k)
        kSource = try c.decodeIfPresent(String.self, forKey: .kSource)
        last = try c.decodeIfPresent(Record.self, forKey: .last)
        lastOdo = try c.decodeIfPresent(Double.self, forKey: .lastOdo)
        lastOdoTs = try c.decodeIfPresent(LocalDateTime.self, forKey: .lastOdoTs)
        lastSoc = try c.decodeIfPresent(Double.self, forKey: .lastSoc)
        lastFuelPct = try c.decodeIfPresent(Double.self, forKey: .lastFuelPct)
        places = try c.decodeIfPresent([Place].self, forKey: .places) ?? []
        recentNotes = try c.decodeIfPresent([String].self, forKey: .recentNotes) ?? []
        inProgress = try c.decodeIfPresent([Record].self, forKey: .inProgress) ?? []
        dailyKm = try c.decodeIfPresent(Double.self, forKey: .dailyKm)
        odoPoints = try c.decodeIfPresent([OdoPoint].self, forKey: .odoPoints) ?? []
    }

    private enum CodingKeys: String, CodingKey {
        case k, kSource, last, lastOdo, lastOdoTs, lastSoc, lastFuelPct, places, recentNotes, inProgress, dailyKm, odoPoints
    }
}

/// 一次里程读数，接口里是 `[时间, 里程]`。
public struct OdoPoint: Decodable, Sendable, Equatable {
    public let ts: LocalDateTime
    public let odo: Double

    public init(ts: LocalDateTime, odo: Double) { self.ts = ts; self.odo = odo }

    public init(from decoder: Decoder) throws {
        var c = try decoder.unkeyedContainer()
        ts = try c.decode(LocalDateTime.self)
        odo = try c.decode(Double.self)
    }
}
