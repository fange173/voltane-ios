import Foundation

/// 表单字段，取值与网页版 input 的 name 一致。
public enum FormField: String, CaseIterable, Sendable, Codable {
    case odometer = "odometer_km"
    case fuelLiters = "fuel_liters"
    case fuelUnitPrice = "fuel_unit_price"
    case amount
    case extraFee = "extra_fee"
    case fuelBefore = "fuel_level_before_pct"
    case fuelAfter = "fuel_level_after_pct"
    case socBefore = "soc_before_pct"
    case socAfter = "soc_after_pct"
    case chargeKwh = "charge_kwh"
    case chargeUnitPrice = "charge_unit_price"
    case chargeMinutes = "charge_minutes"
    case energyFee = "energy_fee"
    case serviceFee = "service_fee"

    /// 金额类字段按算式解析，其余按数字解析。
    public var isMoney: Bool {
        switch self { case .amount, .extraFee, .energyFee, .serviceFee: true; default: false }
    }

    /// 对应 `estimated_fields` 里的引擎字段名。
    var estimateName: String? {
        switch self {
        case .fuelLiters: "fuel_l"
        case .fuelBefore: "fuel_before_pct"
        case .fuelAfter: "fuel_after_pct"
        case .chargeKwh: "charge_kwh"
        case .socAfter: "soc_after"
        case .socBefore: "soc_before"
        default: nil
        }
    }

    /// 用户改了这个字段后要去掉的估算标记。
    var unstickName: String? {
        switch self {
        case .odometer: "odometer_km"
        default: estimateName
        }
    }
}

/// 字段的三种状态：空、用户填的、自动推算的。
public struct FieldState: Equatable, Sendable {
    public var text = ""
    public var isUser = false
    public var isAuto = false
    /// 已保存记录里带估算标记的值，按用户值载入，只是显示成估算样式。
    public var showsEstimate = false
}

public enum RecordKind: String, Sendable, Codable { case fuel, charge, snapshot }

/// 两个单选胶囊之外的开关项。
public enum FormFlag: String, Sendable, Codable {
    case fuelIsFull = "fuel_is_full"
    case chargeToLimit = "charge_to_limit"
    case tripMode = "trip_mode"
    case odoUnknown = "odo_unknown"
    case missedBefore = "missed_before"
}

public enum FormChip: String, Sendable, Codable {
    case grade, chargeType, snapshotTag
}

public struct OdoHint: Equatable, Sendable {
    public var text: String
    public var warn: Bool
    public var placeholder: String
}

/// 表单草稿：按「车辆 + 类型」保存用户填过的内容，24 小时内有效。
public struct FormDraft: Codable, Sendable, Equatable {
    public var fields: [String: String]
    public var flags: [String: Bool]
    public var fuelGrade: String?
    public var chargeType: String?
    public var snapshotTag: String?
    public var place: Place?
    public var savedAt: Date
    public var note: String

    public var isFresh: Bool { Date().timeIntervalSince(savedAt) <= 24 * 3600 }
    public var hasContent: Bool { !fields.isEmpty || !note.isEmpty }
}

public struct SavePlan: Sendable {
    public var payload: RecordPayload
    public var error: String?
}
