import Foundation

/// 某一类能耗的汇总：每百公里数值、质量等级、误差范围。
public struct EnergyStat: Codable, Sendable, Hashable {
    public var amount: Double?
    public var distance: Double?
    public var err100: Double?
    public var fromTs: LocalDateTime?
    public var toTs: LocalDateTime?
    public var high100: Double?
    public var low100: Double?
    public var per100: Double?
    public var quality: String?
}

public struct IdleStat: Codable, Sendable, Hashable {
    public var amount: Double?
    public var count: Int?
    public var days: Double?
    public var perDay: Double?
    public var share: Double?
}

/// 行驶、静置、含静置合计三种口径，行驶能耗和综合能耗分开展示。
public struct EnergyBlock: Codable, Sendable, Hashable {
    public var drive: EnergyStat?
    public var idle: IdleStat?
    public var overall: EnergyStat?
}

public struct CombinedStat: Codable, Sendable, Hashable {
    public var costPerKm: Double?
    public var count: Int?
    public var distance: Double?
    public var elecPer100: Double?
    public var elecShare: Double?
    public var equivPer100: Double?
    public var fuelPer100: Double?
    public var quality: String?
}

public struct PeriodReport: Codable, Sendable, Hashable {
    public var categories: [String: Int]?
    public var combined: CombinedStat?
    public var elec: EnergyBlock?
    public var fuel: EnergyBlock?
    public var elecCents: Int?
    public var elecCount: Int?
    public var elecKwh: Double?
    public var energyCents: Int?
    public var energyCostPerKm: Double?
    public var from: LocalDateTime?
    public var to: LocalDateTime?
    public var fuelCents: Int?
    public var fuelCount: Int?
    public var fuelL: Double?
    public var homeShare: Double?
    public var mileage: Double?
    public var otherCents: Int?
    public var summaryCents: Int?
    public var totalCents: Int?
    public var totalCostPerKm: Double?
}

/// 概览里「最近能耗」的单项：质量等级 D 时只有 hint 没有数值。
public struct LatestEnergy: Codable, Sendable, Hashable {
    public var per100: Double?
    public var quality: String?
    public var hint: String?
    public var distance: Double?
    public var segments: Int?
    public var endTs: LocalDateTime?
    public var costPerKm: Double?
    public var err100: Double?
    public var low100: Double?
    public var high100: Double?
    public var scope: String?
}

public struct SparkPoint: Codable, Sendable, Hashable {
    public var ts: LocalDateTime?
    public var per100: Double?
    public var quality: String?
}

public struct HistoryStat: Codable, Sendable, Hashable {
    public var days: Int
    public var elec: EnergyStat?
    public var fuel: EnergyStat?
    public var energyCents: Int?
    public var energyCostPerKm: Double?
    public var hasSummary: Bool?
    public var mileage: Double?
    public var scope: String?
    public var since: LocalDateTime?
    public var summaryBeforeCents: Int?
    public var totalCents: Int?
    public var totalCostPerKm: Double?
}

public struct PendingItem: Codable, Sendable, Hashable, Identifiable {
    public var key: String
    public var text: String
    public var type: String
    public var anomaly: String?
    public var endId: Int?
    public var energy: String?
    public var afterId: Int?
    public var beforeId: Int?
    public var id: String { key }
}

public struct SinceLastFull: Codable, Sendable, Hashable {
    public var km: Double?
}

public struct Overview: Decodable, Sendable {
    public struct Latest: Decodable, Sendable {
        public var fuel: LatestEnergy?
        public var elec: LatestEnergy?
        public var elecTotals: EnergyBlock?
        public var combined: Segment?
    }

    public struct Range: Decodable, Sendable, Hashable {
        public var key: String
        public var from: LocalDateTime?
        public var to: LocalDateTime?
    }

    public struct Spark: Decodable, Sendable {
        public var fuel: [SparkPoint]
        public var elec: [SparkPoint]
    }

    public var vehicle: Vehicle
    public var range: Range
    public var period: PeriodReport
    public var prev: PeriodReport?
    public var latest: Latest
    public var spark: Spark
    public var sinceLastFull: SinceLastFull?
    public var history: HistoryStat?
    public var inProgress: [Record]
    public var pending: [PendingItem]
    public var reminders: [Reminder]
    public var recent: [TimelineItem]
    public var latestOdo: Double?
    public var dailyKm: Double?
    public var recordCount: Int?
    public var k: Double?
}
