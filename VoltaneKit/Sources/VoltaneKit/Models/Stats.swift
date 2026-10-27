import Foundation

/// 统计、报表、管理类接口的响应。外层结构强类型，随页面逐步细化的部分先用 JSONValue 承接。
public struct StatsEnergy: Decodable, Sendable {
    public struct Charging: Decodable, Sendable {
        public var capacityEst: Double?
        public var k: Double?
        public var kAc: Double?
        public var kDc: Double?
        public var kSource: String?
        public var samples: [JSONValue]
        public var socStart: [Double]
        public var types: [ChargeTypeStat]
    }

    public struct ChargeTypeStat: Decodable, Sendable, Hashable {
        public var avgPrice: Double?
        public var cents: Int?
        public var count: Int?
        public var kwh: Double?
        public var type: String
    }

    public struct Month: Decodable, Sendable {
        public var month: String
        public var combined: CombinedStat?
        public var elec: EnergyBlock?
        public var fuel: EnergyBlock?
        public var energyCostPerKm: Double?
        public var mileage: Double?
    }

    public struct Segments: Decodable, Sendable {
        public var combined: [Segment]
        public var elec: [Segment]
        public var fuel: [Segment]
    }

    public var charging: Charging
    public var energyType: String
    public var from: LocalDateTime?
    public var to: LocalDateTime?
    public var months: [Month]
    public var segments: Segments
    public var totals: JSONValue?
}

public struct StatsCost: Decodable, Sendable {
    public struct Category: Decodable, Sendable, Hashable {
        public var cents: Int
        public var count: Int?
        public var key: String
        public var label: String?
        public var share: Double?
    }

    public struct Month: Decodable, Sendable, Hashable {
        public var month: String
        public var costPerKm: Double?
        public var cumulative: Int?
        public var elec: Int?
        public var fuel: Int?
        public var insurance: Int?
        public var maintenance: Int?
        public var mileage: Double?
        public var other: Int?
        public var summary: Int?
        public var total: Int?
    }

    public var categories: [Category]
    public var costPerKm: Double?
    public var from: LocalDateTime?
    public var to: LocalDateTime?
    public var mileage: Double?
    public var months: [Month]
    public var places: [JSONValue]
    public var prices: JSONValue?
    public var totalCents: Int
}

public struct StatsMileage: Decodable, Sendable {
    public struct Month: Decodable, Sendable, Hashable {
        public var month: String
        public var days: Int?
        public var km: Double?
        public var lastYear: Double?
    }

    public struct Point: Decodable, Sendable, Hashable {
        public var odo: Double
        public var ts: LocalDateTime
    }

    public var dailyAvg: Double?
    public var latestOdo: Double?
    public var months: [Month]
    public var points: [Point]
    public var recentDaily: Double?
}

public struct StatsCalendar: Decodable, Sendable {
    public struct Day: Decodable, Sendable {
        public var cents: Int
        public var items: [TimelineItem]
        public var kinds: [String]
    }

    public var days: [String: Day]
    public var month: String
    public var report: PeriodReport
}

public struct MonthlyReport: Decodable, Sendable {
    public var month: String
    public var prev: PeriodReport?
    public var report: PeriodReport
    public var sentence: String?
}

public struct YearlyReport: Decodable, Sendable {
    public var year: Int
    public var years: [Int]
    public var report: PeriodReport
    public var bestMonth: JSONValue?
    public var months: [JSONValue]
    public var topItem: JSONValue?
    public var prev: PeriodReport?
}

public struct PeriodSummary: Decodable, Sendable, Identifiable {
    public let id: Int
    public var vehicleId: Int?
    public var startDate: LocalDateTime?
    public var endDate: LocalDateTime?
    public var mode: String?
    public var startOdometerKm: Double?
    public var endOdometerKm: Double?
    public var fuelLiters: Double?
    public var fuelCents: Int?
    public var fuelPrice: Double?
    public var elecKwh: Double?
    public var elecCents: Int?
    public var elecPrice: Double?
    public var note: String?
    public var version: Int?
    public var diff: Diff?

    /// 与同期逐条记录的对比；`warnings` 非空表示汇总总量小于已记录量。
    public struct Diff: Decodable, Sendable {
        public var recordedFuelL: Double?
        public var recordedElecKwh: Double?
        public var fuelL: Double?
        public var elecKwh: Double?
        public var warnings: [String]?
    }
}

public struct OdometerLatest: Decodable, Sendable { public let latest: Double? }

public struct Calibration: Decodable, Sendable {
    public var capacityEst: Double?
    public var k: Double?
    public var kAc: Double?
    public var kDc: Double?
    public var source: String?
    public var samples: [JSONValue]
}

public struct VehicleHealth: Decodable, Sendable {
    public struct Issue: Decodable, Sendable, Hashable, Identifiable {
        public var key: String
        public var level: String
        public var text: String
        public var action: String?
        public var afterId: Int?
        public var beforeId: Int?
        public var kind: String?
        public var recordId: Int?
        public var odometerKm: Double?
        public var deliveryDate: LocalDateTime?
        public var id: String { key }
    }

    public struct Coverage: Decodable, Sendable {
        public var elec: Double?
        public var fuel: Double?
    }

    public var coverage: Coverage?
    public var issues: [Issue]
    public var k: Double?
    public var kSource: String?
    public var latestOdo: Double?
    public var ledgerKm: Double?
}

public struct AdminUser: Decodable, Sendable, Identifiable {
    public let id: Int
    public var username: String
    public var name: String
    public var color: String?
    public var role: String
    public var isActive: Bool
    public var vehicleCount: Int?
    public var createdAt: UTCDateTime?
}

public struct AdminSystem: Decodable, Sendable {
    public var allowSignup: Bool
    public var backupKeep: Int?
    public var backups: [JSONValue]
    public var dbSize: Int?
    public var orphanVehicles: [JSONValue]
    public var records: Int?
    public var users: Int?
    public var vehicles: Int?
}
