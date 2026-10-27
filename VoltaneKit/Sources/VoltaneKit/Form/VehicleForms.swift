import Foundation

private func number(_ text: String) -> Double? { JSNumber.parse(text.trimmingCharacters(in: .whitespaces)) }
private func cents(_ text: String) -> Int? {
    let t = text.trimmingCharacters(in: .whitespaces)
    return t.isEmpty ? nil : Decimal(plain: t)?.cents
}
/// 取整数（格数、月数），超出合理范围时返回 nil，避免 Int 转换溢出。
private func wholeNumber(_ text: String) -> Int? {
    guard let x = number(text), abs(x) < 1_000_000 else { return nil }
    return Int(x.rounded())
}
private func dayOnly(_ d: LocalDateTime?) -> LocalDateTime? { d.map { LocalDateTime(year: $0.year, month: $0.month, day: $0.day, hasTime: false) } }

/// 油表读数与百分比的换算：百分比 / 格数 / 升，对应网页版 `fuelUnit`。
public struct FuelGaugeUnit: Sendable {
    public let label: String
    public let placeholder: String
    public let toPct: @Sendable (Double) -> Double
    public let fromPct: @Sendable (Double) -> Double

    public init(mode: String?, tankL: Double?, bars: Int?) {
        if mode == "liters", let tank = tankL, tank > 0 {
            label = "L"; placeholder = "0–\(Fmt.num(tank))"
            toPct = { $0 / tank * 100 }
            fromPct = { Double(JSNumber.trimmed($0 / 100 * tank, 1)) ?? 0 }
        } else if mode == "bars", let n = bars, n > 0 {
            label = "/\(n) 格"; placeholder = "0–\(n)"
            toPct = { $0 / Double(n) * 100 }
            fromPct = { ($0 / 100 * Double(n)).rounded(.toNearestOrAwayFromZero) }
        } else {
            label = "%"; placeholder = "0–100"
            toPct = { $0 }
            fromPct = { $0 }
        }
    }
}

/// 车辆参数编辑：文本字段进，请求体出。提车信息走专门接口，见 `deliveryChange`。
public struct VehicleParamsDraft: Equatable, Sendable {
    public static let colors = ["#4F46E5", "#0EA5E9", "#10B981", "#F59E0B", "#EF4444", "#8B5CF6", "#EC4899", "#111827", "#64748B"]

    public var name: String
    public var plate: String
    public var model: String
    public var color: String
    public var tank: String
    public var battery: String
    public var chargeLimit: String
    public var fuelGrade: String
    public var chargeType: String
    public var gaugeMode: String
    public var gaugeBars: String
    public var recordStyle: String
    public var deliveryDate: LocalDateTime?
    public var deliveryOdo: String
    public var minSegmentKm: String
    public var kwhPerL: String
    public var gaugeErrPct: String
    public var allowGaugeAnchor: Bool

    public init(vehicle v: Vehicle) {
        let c = v.calcSettings ?? [:]
        func calc(_ k: String, _ d: String) -> String {
            switch c[k] {
            case .int(let x): String(x)
            case .double(let x): JSNumber.trimmed(x, 4)
            default: d
            }
        }
        name = v.name; plate = v.plate ?? ""; model = v.model ?? ""; color = v.color ?? Self.colors[0]
        tank = v.tankCapacityL.map { JSNumber.trimmed($0, 2) } ?? ""
        battery = v.batteryUsableKwh.map { JSNumber.trimmed($0, 2) } ?? ""
        chargeLimit = JSNumber.trimmed(v.chargeLimitPct ?? 100, 1)
        fuelGrade = v.defaultFuelGrade ?? "92"
        chargeType = Labels.chargeKey(v.defaultChargeType) ?? "home"
        gaugeMode = v.fuelGaugeMode ?? "pct"
        gaugeBars = v.fuelGaugeBars.map(String.init) ?? ""
        recordStyle = v.recordStyle ?? "detailed"
        deliveryDate = dayOnly(v.deliveryDate)
        deliveryOdo = v.deliveryDate != nil ? (v.initialOdometerKm.map { JSNumber.trimmed($0, 1) } ?? "") : ""
        minSegmentKm = calc("min_segment_km", "30")
        kwhPerL = calc("kwh_per_l", "8.9")
        gaugeErrPct = calc("gauge_err_pct", "5")
        allowGaugeAnchor = c["allow_gauge_anchor"]?.boolValue ?? true
    }

    public func validate() -> String? {
        if name.trimmingCharacters(in: .whitespaces).isEmpty { return "请填写车名" }
        if (deliveryDate != nil) != (number(deliveryOdo) != nil) { return "提车日期和提车里程要一起填，不填就都留空" }
        return nil
    }

    /// 提车日期和里程都填了且与原值不同时，需要再调一次提车接口。
    public func deliveryChange(for v: Vehicle) -> (date: LocalDateTime, odometerKm: Double)? {
        guard let d = deliveryDate, let o = number(deliveryOdo) else { return nil }
        return (dayOnly(v.deliveryDate) != d || v.initialOdometerKm != o) ? (d, o) : nil
    }

    public func payload(for v: Vehicle) -> VehiclePayload {
        var p = VehiclePayload()
        p.name = name.trimmingCharacters(in: .whitespaces)
        p.plate = plate.trimmingCharacters(in: .whitespaces)
        p.brand = v.brand ?? ""
        p.model = model.trimmingCharacters(in: .whitespaces)
        p.year = v.year
        p.energyType = v.energyType
        p.tankCapacityL = v.hasFuel ? number(tank) : nil
        p.batteryUsableKwh = v.hasElec ? number(battery) : nil
        p.chargeLimitPct = v.hasElec ? (number(chargeLimit) ?? v.chargeLimitPct ?? 100) : (v.chargeLimitPct ?? 100)
        p.defaultFuelGrade = v.hasFuel ? fuelGrade : (v.defaultFuelGrade ?? "92")
        p.defaultChargeType = v.hasElec ? chargeType : (Labels.chargeKey(v.defaultChargeType) ?? "home")
        p.fuelGaugeMode = v.hasFuel ? gaugeMode : (v.fuelGaugeMode ?? "pct")
        p.fuelGaugeBars = v.hasFuel ? wholeNumber(gaugeBars) : v.fuelGaugeBars
        p.factoryFuelL = v.factoryFuelL ?? 5
        p.recordStyle = recordStyle
        p.initialOdometerKm = v.initialOdometerKm
        p.deliveryDate = dayOnly(v.deliveryDate)
        p.purchasePriceCents = v.purchasePriceCents
        p.color = color
        p.calcSettings = [
            "min_segment_km": .double(number(minSegmentKm) ?? 30),
            "kwh_per_l": .double(number(kwhPerL) ?? 8.9),
            "gauge_err_pct": .double(number(gaugeErrPct) ?? 5),
            "allow_gauge_anchor": .bool(v.hasFuel ? allowGaugeAnchor : (v.calcSettings?["allow_gauge_anchor"]?.boolValue ?? true)),
        ]
        return p
    }
}

/// 新车向导里的提醒模板：周期只是常见值，到期日和到期里程由用户填。
public struct WizardReminderTemplate: Sendable, Identifiable {
    public let key: String
    public let title: String
    public var months: Int?
    public var km: Int?
    public var iceKm: Int?
    public var useKm = false
    public var hint: String?
    public var hasInterval = true
    public var id: String { key }

    public static let all: [WizardReminderTemplate] = [
        .init(key: "insurance", title: "保险到期", months: 12, hint: "看保单上的保险止期"),
        .init(key: "inspection", title: "年检", months: 24, hint: "看行驶证副页或检验标志；6 年内新车一般 2 年申领一次，以当地规定为准"),
        .init(key: "maintenance", title: "保养", months: 12, km: 10000, iceKm: 7500, useKm: true, hint: "看上次保养单或保养手册上的「下次保养」"),
        .init(key: "tires", title: "轮胎检查/更换", months: 60, km: 50000, useKm: true),
        .init(key: "brake_fluid", title: "更换刹车油", months: 24),
        .init(key: "cabin_filter", title: "更换空调滤芯", months: 12, km: 20000, useKm: true),
        .init(key: "battery_12v", title: "12V 小电瓶检查", months: 36),
        .init(key: "license", title: "驾驶证换证（个人）", hint: "看驾驶证上的有效期", hasInterval: false),
    ]
}

public struct WizardReminderDraft: Equatable, Sendable {
    public var on = false
    public var dueDate: LocalDateTime?
    public var dueOdo = ""
    public var months = ""
    public var km = ""
}

/// 新车向导的全部输入与校验，逻辑对应网页版 `wizardPage`。
public struct VehicleWizardState: Equatable, Sendable {
    public enum StartMode: String, Sendable, CaseIterable { case existing, new, skip }

    public static let stepTitles = ["基本信息", "能源参数", "怎么开始记", "提醒"]
    public static let energyTypes = ["phev", "erev", "bev", "hev", "ice"]
    public static let energyDesc = [
        "phev": "既加油又充电，如比亚迪 DM-i", "erev": "增程，如理想、问界", "bev": "只充电",
        "hev": "不插电的油混，如丰田双擎", "ice": "只加油",
    ]

    public var step = 1
    public var name = ""
    public var plate = ""
    public var model = ""
    public var energyType = "phev"
    public var color = VehicleParamsDraft.colors[0]
    public var tank = ""
    public var battery = ""
    public var chargeLimit = "100"
    public var chargeType = "home"
    public var fuelGrade = "92"
    public var gaugeMode = "pct"
    public var gaugeBars = "8"
    public var recordStyle = "detailed"
    public var mode = StartMode.existing
    public var currentOdo = ""
    public var currentFuel = ""
    public var currentSoc = ""
    public var deliveryDate: LocalDateTime?
    public var deliveryOdo = ""
    public var factoryFuel = "5"
    public var deliveryFillL = ""
    public var deliveryFillYuan = ""
    public var summaryStart: LocalDateTime?
    public var summaryFuelYuan = ""
    public var summaryFuelL = ""
    public var summaryFuelPrice = ""
    public var summaryElecKwh = ""
    public var summaryElecYuan = ""
    public var summaryElecPrice = ""
    public var reminders: [String: WizardReminderDraft] = [:]

    public init() {}

    /// 除了当前步骤外还没填过任何内容，取消时不需要确认。
    public var isPristine: Bool {
        var copy = self
        copy.step = 1
        return copy == VehicleWizardState()
    }

    public var hasFuel: Bool { ["ice", "hev", "phev", "erev"].contains(energyType) }
    public var hasElec: Bool { ["phev", "erev", "bev"].contains(energyType) }
    public var isIce: Bool { ["ice", "hev"].contains(energyType) }

    public var gaugeUnit: FuelGaugeUnit {
        FuelGaugeUnit(mode: gaugeMode, tankL: number(tank), bars: wholeNumber(gaugeBars))
    }

    /// 换油表显示方式时，把已填的当前油量换算成新单位，避免数值含义变掉。
    public mutating func setGaugeMode(_ new: String) {
        let pct = number(currentFuel).map { gaugeUnit.toPct($0) }
        gaugeMode = new
        if let pct { currentFuel = JSNumber.trimmed(gaugeUnit.fromPct(min(max(pct, 0), 100)), 1) }
    }

    public mutating func reminder(_ t: WizardReminderTemplate) -> WizardReminderDraft {
        if let r = reminders[t.key] { return r }
        var r = WizardReminderDraft()
        r.months = t.months.map(String.init) ?? ""
        if t.useKm, let km = (isIce ? t.iceKm : nil) ?? t.km { r.km = String(km) }
        reminders[t.key] = r
        return r
    }

    public func validate(step s: Int) -> String? {
        switch s {
        case 1:
            if name.trimmingCharacters(in: .whitespaces).isEmpty { return "请填写车名" }
        case 2:
            if let t = number(tank), t <= 0 || t > 300 { return "油箱容积不太对" }
            if let b = number(battery), b <= 0 || b > 300 { return "电池容量不太对" }
        case 3 where mode != .skip:
            guard let cur = number(currentOdo) else { return "请填写当前里程" }
            if let soc = number(currentSoc), soc < 0 || soc > 100 { return "电量要在 0–100% 之间" }
            if mode == .existing {
                if let d = number(deliveryOdo), d > cur { return "提车里程不能大于当前里程" }
                let hasDelivery = deliveryDate != nil && number(deliveryOdo) != nil
                if (number(deliveryFillL) ?? 0) != 0 && !hasDelivery { return "填「提车时加了多少油」需要同时填提车日期和提车里程" }
                let sumData = [summaryFuelYuan, summaryFuelL, summaryElecKwh, summaryElecYuan].contains { number($0) != nil }
                if sumData && summaryStart == nil && deliveryDate == nil { return "历史汇总需要填「从哪天开始算」" }
            }
        case 4:
            for t in WizardReminderTemplate.all {
                guard let r = reminders[t.key], r.on else { continue }
                if r.dueDate == nil && !(t.useKm && number(r.dueOdo) != nil) { return "「\(t.title)」请填下次到期的日期或里程，不需要就取消勾选" }
            }
        default: break
        }
        return nil
    }

    public func payload() -> VehicleCreatePayload {
        var v = VehiclePayload()
        v.name = name.trimmingCharacters(in: .whitespaces)
        v.plate = plate.trimmingCharacters(in: .whitespaces)
        v.model = model.trimmingCharacters(in: .whitespaces)
        v.energyType = energyType
        v.color = color
        v.tankCapacityL = hasFuel ? number(tank) : nil
        v.batteryUsableKwh = hasElec ? number(battery) : nil
        v.chargeLimitPct = number(chargeLimit) ?? 100
        v.defaultFuelGrade = fuelGrade
        v.defaultChargeType = chargeType
        v.fuelGaugeMode = gaugeMode
        v.fuelGaugeBars = gaugeMode == "bars" ? wholeNumber(gaugeBars) : nil
        v.factoryFuelL = number(factoryFuel) ?? 5
        v.recordStyle = recordStyle
        v.deliveryDate = mode == .existing ? dayOnly(deliveryDate) : nil

        var start: VehicleCreatePayload.Start?
        if mode != .skip {
            let fuelPct = number(currentFuel).map { min(max(gaugeUnit.toPct($0), 0), 100) }
            start = .init(mode: mode.rawValue,
                          deliveryOdo: mode == .existing && deliveryDate != nil ? number(deliveryOdo) : nil,
                          deliveryFillL: number(deliveryFillL),
                          deliveryFillCents: cents(deliveryFillYuan),
                          currentOdo: number(currentOdo), currentFuelPct: hasFuel ? fuelPct : nil,
                          currentSoc: hasElec ? number(currentSoc) : nil)
        }

        var summary: VehicleCreatePayload.Summary?
        let sumValues: [Bool] = [summaryStart != nil] + [summaryFuelYuan, summaryFuelL, summaryFuelPrice, summaryElecKwh, summaryElecYuan, summaryElecPrice].map { number($0) != nil }
        if mode == .existing && sumValues.contains(true) {
            summary = .init(startDate: dayOnly(summaryStart),
                            fuelLiters: hasFuel ? number(summaryFuelL) : nil, fuelCents: hasFuel ? cents(summaryFuelYuan) : nil,
                            fuelPrice: hasFuel ? number(summaryFuelPrice) : nil,
                            elecKwh: hasElec ? number(summaryElecKwh) : nil, elecCents: hasElec ? cents(summaryElecYuan) : nil,
                            elecPrice: hasElec ? number(summaryElecPrice) : nil)
        }

        var list: [VehicleCreatePayload.Reminder] = []
        for t in WizardReminderTemplate.all {
            guard let r = reminders[t.key], r.on else { continue }
            let odo = t.useKm ? number(r.dueOdo) : nil
            guard r.dueDate != nil || odo != nil else { continue }
            list.append(.init(templateKey: t.key, dueDate: dayOnly(r.dueDate), dueOdometerKm: odo,
                              intervalMonths: t.hasInterval ? wholeNumber(r.months) : nil,
                              intervalKm: t.hasInterval && t.useKm ? number(r.km) : nil))
        }
        return VehicleCreatePayload(vehicle: v, start: start, summary: summary, reminders: list)
    }
}

/// 汇总表单：文本进、请求体出。
public struct SummaryDraft: Equatable, Sendable {
    public var startDate: LocalDateTime
    public var endDate: LocalDateTime
    public var mode = "extra"
    public var fuelLiters = ""
    public var fuelYuan = ""
    public var fuelPrice = ""
    public var elecKwh = ""
    public var elecYuan = ""
    public var elecPrice = ""
    public var note = ""

    public init(today: LocalDateTime = LocalDateTime(date: Date())) {
        startDate = dayOnly(today)!; endDate = dayOnly(today)!
    }

    public init(_ s: PeriodSummary, today: LocalDateTime = LocalDateTime(date: Date())) {
        self.init(today: today)
        if let d = dayOnly(s.startDate) { startDate = d }
        if let d = dayOnly(s.endDate) { endDate = d }
        mode = s.mode ?? "extra"
        fuelLiters = s.fuelLiters.map { JSNumber.trimmed($0, 2) } ?? ""
        fuelYuan = s.fuelCents.map { (Decimal($0) / 100).plainString } ?? ""
        fuelPrice = s.fuelPrice.map { JSNumber.trimmed($0, 3) } ?? ""
        elecKwh = s.elecKwh.map { JSNumber.trimmed($0, 2) } ?? ""
        elecYuan = s.elecCents.map { (Decimal($0) / 100).plainString } ?? ""
        elecPrice = s.elecPrice.map { JSNumber.trimmed($0, 3) } ?? ""
        note = s.note ?? ""
    }

    public func validate() -> String? { endDate < startDate ? "结束日期早于开始日期" : nil }

    public func payload(vehicle v: Vehicle, version: Int?) -> SummaryPayload {
        var p = SummaryPayload(vehicleId: v.id, startDate: startDate, endDate: endDate)
        p.mode = mode
        p.fuelLiters = v.hasFuel ? number(fuelLiters) : nil
        p.fuelCents = v.hasFuel ? cents(fuelYuan) : nil
        p.fuelPrice = v.hasFuel ? number(fuelPrice) : nil
        p.elecKwh = v.hasElec ? number(elecKwh) : nil
        p.elecCents = v.hasElec ? cents(elecYuan) : nil
        p.elecPrice = v.hasElec ? number(elecPrice) : nil
        p.note = note.trimmingCharacters(in: .whitespaces)
        p.version = version
        return p
    }
}

public extension Invite {
    /// 列表副标题：角色 · 有效期 · 次数 · 是否可注册。
    var metaText: String {
        var parts = [roleLabel, expiresAt.map { "\(Fmt.date($0.local())) 过期" } ?? "长期有效"]
        if let m = maxUses, m > 0 { parts.append("已用 \(usedCount)/\(m)") } else { parts.append("不限次数 · 已加入 \(usedCount) 人") }
        if allowSignup { parts.append("可注册") }
        return parts.joined(separator: " · ")
    }

    /// 分享文案，与网页版 `copyInvite` 一致。
    func shareText(server: URL?) -> String { InviteShare.text(code: code, server: server) }
}

public enum InviteShare {
    public static func link(code: String, server: URL?) -> String {
        let base = (server?.absoluteString ?? "").trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return "\(base)/join/\(code)"
    }

    public static func text(code: String, server: URL?) -> String {
        "邀请你一起记录用车数据，打开 \(link(code: code, server: server)) 或在「我的 → 加入车辆」输入邀请码 \(code)"
    }
}

public extension UTCDateTime {
    /// 「刚刚 / N 分钟前 / N 小时前 / N 天前」，超过一周显示日期。
    func ago(now: Date = Date()) -> String {
        let s = max(0, now.timeIntervalSince(date))
        switch s {
        case ..<60: return "刚刚"
        case ..<3600: return "\(Int(s / 60)) 分钟前"
        case ..<86400: return "\(Int(s / 3600)) 小时前"
        case ..<(86400 * 7): return "\(Int(s / 86400)) 天前"
        default: return Fmt.date(local())
        }
    }
}
