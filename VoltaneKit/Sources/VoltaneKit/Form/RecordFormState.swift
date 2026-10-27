import Foundation

/// 加油、充电、快照表单的状态与自动推算，逐行对应网页版 `record-form.js` 的 `recompute` / `collect` / `validate`。
public struct RecordFormState: Sendable {
    public let vehicle: Vehicle
    public let kind: RecordKind
    public var prefill: Prefill
    public private(set) var fields: [FormField: FieldState] = [:]
    public private(set) var flags: [FormFlag: Bool] = [:]
    public private(set) var fuelGrade: String?
    public private(set) var chargeType: String?
    public private(set) var snapshotTag: String?
    public private(set) var place: Place?
    public var coords: (lat: Double, lng: Double)?
    public var occurredAt: LocalDateTime
    public var note = ""
    /// 编辑已保存的记录时的原记录。
    public let editing: Record?
    public private(set) var estimates: Set<String> = []
    private var stickyEstimates: Set<String> = []
    /// 用户上次在表单里选的油量单位（pct / liters），没选过为 nil。
    public private(set) var fuelUnitPref: String?

    public init(vehicle: Vehicle, kind: RecordKind, prefill: Prefill, now: LocalDateTime = LocalDateTime(date: Date())) {
        self.vehicle = vehicle; self.kind = kind; self.prefill = prefill; self.editing = nil; self.occurredAt = now
        if kind == .fuel { flags[.fuelIsFull] = true }
        applyDefaults()
        recompute()
    }

    /// 编辑已保存的记录：估算字段按原值载入，只有用户改了对应输入才重新推算。
    public init(vehicle: Vehicle, record: Record, prefill: Prefill, finish: Bool = false,
                now: LocalDateTime = LocalDateTime(date: Date())) {
        self.vehicle = vehicle; self.kind = RecordKind(rawValue: record.kind) ?? .fuel; self.prefill = prefill
        self.editing = record; self.occurredAt = record.occurredAt
        stickyEstimates = Set(record.estimatedFields ?? [])
        estimates = stickyEstimates
        fill(from: record, finish: finish, now: now)
        recompute()
    }

    // MARK: 读取

    public func state(_ f: FormField) -> FieldState { fields[f] ?? FieldState() }
    public func text(_ f: FormField) -> String { state(f).text }
    public func flag(_ f: FormFlag) -> Bool { flags[f] ?? false }
    public var usesDetailedStyle: Bool { vehicle.recordStyle != "simple" }

    /// 字段是否出现在当前表单里（决定能否被自动推算写入）。
    func exists(_ f: FormField) -> Bool {
        switch f {
        case .fuelLiters, .fuelUnitPrice, .fuelAfter: kind == .fuel
        case .chargeKwh, .chargeUnitPrice, .socAfter, .chargeMinutes, .energyFee, .serviceFee: kind == .charge
        case .fuelBefore: kind == .fuel || kind == .snapshot || (kind == .charge && vehicle.hasFuel)
        case .socBefore: kind == .snapshot ? vehicle.hasElec : (kind == .fuel ? vehicle.hasElec : true)
        case .amount: kind != .snapshot
        case .extraFee: kind != .snapshot
        case .odometer: true
        }
    }

    private func number(_ f: FormField) -> Double? {
        if f == .odometer && flag(.odoUnknown) { return nil }
        return JSNumber.parse(text(f))
    }

    private func money(_ f: FormField) -> Decimal? {
        AmountExpression.evaluate(text(f))
    }

    /// 数量、单价这类按数字解析、但参与金额计算的字段，用 Decimal 保持精度。
    private func decimal(_ f: FormField) -> Decimal? {
        if f.isMoney { return money(f) }
        guard let v = number(f) else { return nil }
        return Decimal(shortest: v)
    }

    private func isUser(_ f: FormField) -> Bool { state(f).isUser }

    // MARK: 用户操作

    /// 用户在输入框里改了内容：从此不再被自动覆盖；清空后可以重新被推算。
    public mutating func input(_ f: FormField, _ text: String) {
        if f == .socAfter && flag(.chargeToLimit) { return }
        if f == .chargeUnitPrice && kind == .charge { return }
        var s = FieldState()
        s.text = text
        s.isUser = !text.trimmingCharacters(in: .whitespaces).isEmpty
        fields[f] = s
        unstick(f)
        recompute()
    }

    public mutating func setFlag(_ flag: FormFlag, _ on: Bool) {
        flags[flag] = on
        if flag == .odoUnknown && on { fields[.odometer] = FieldState() }
        recompute()
    }

    public mutating func selectChip(_ chip: FormChip, _ value: String) {
        switch chip {
        case .grade: fuelGrade = value
        case .chargeType: chargeType = value
        case .snapshotTag: snapshotTag = value
        }
        recompute()
    }

    public mutating func setOccurredAt(_ t: LocalDateTime) {
        occurredAt = t
        recompute()
    }

    /// 选择或取消常用地点；选中后带出默认充电方式、标号和上次单价。
    public mutating func selectPlace(_ p: Place?) {
        applyPlace(p)
        recompute()
    }

    /// `defaults` 为 false 时只记下地点：载入已保存的记录或草稿要保持原来的方式、标号和单价。
    private mutating func applyPlace(_ p: Place?, defaults: Bool = true) {
        place = p
        guard defaults, let p, p.id != nil else { return }
        if kind == .charge, let t = p.defaultChargeType { chargeType = t }
        if kind == .fuel, let g = p.defaultFuelGrade { fuelGrade = g }
        if kind == .fuel, !isUser(.fuelUnitPrice), let last = p.lastUnitPrice, last != 0 { setUser(.fuelUnitPrice, JSNumber.jsString(last)) }
    }

    /// 液位滑块：值取整数，标记为用户填的。
    public mutating func setLevel(_ f: FormField, _ value: Double) {
        if f == .socAfter && flag(.chargeToLimit) { return }
        fields[f] = FieldState(text: JSNumber.jsString(value), isUser: true)
        unstick(f)
        recompute()
    }

    /// 充到上限后结束 SOC 固定，界面上不可修改。
    public var socAfterLocked: Bool { flag(.chargeToLimit) }

    /// 回到「未填」：空值和 0 含义不同。
    public mutating func clearLevel(_ f: FormField) { input(f, "") }

    /// 按格数的油表：点第 k 格，再点一次清除。
    public mutating func tapBar(_ f: FormField, bar k: Int) {
        guard let n = vehicle.fuelGaugeBars, n > 0 else { return }
        let cur = JSNumber.parse(text(f)).map { Int(($0 / 100 * Double(n)).rounded(.toNearestOrAwayFromZero)) } ?? 0
        let value = cur == k ? "" : JSNumber.toFixed(Double(k) / Double(n) * 100, 1)
        fields[f] = FieldState(text: value, isUser: !value.isEmpty)
        unstick(f)
        recompute()
    }

    /// 按升的油表：内部换算成百分比。
    public mutating func setLiters(_ f: FormField, _ text: String) {
        guard let tank = vehicle.tankCapacityL, tank > 0 else { return }
        let value = JSNumber.parse(text).map { JSNumber.toFixed(min($0 / tank * 100, 100), 1) } ?? ""
        fields[f] = FieldState(text: value, isUser: !value.isEmpty)
        unstick(f)
        recompute()
    }

    /// 「同上次」：复制上次的地点、方式；加油还复制标号和单价。
    public mutating func copyLast() {
        guard let l = prefill.last else { return }
        if let g = l.fuelGrade, !g.isEmpty { fuelGrade = g }
        if let t = l.chargeType, !t.isEmpty { chargeType = t }
        if kind == .fuel, let price = l.fuelUnitPrice { setUser(.fuelUnitPrice, JSNumber.jsString(price)) }
        if let pid = l.placeId, let pl = prefill.places.first(where: { $0.id == pid }) {
            applyPlace(pl)
        } else if let name = l.placeName, !name.isEmpty, l.placeId == nil {
            applyPlace(Place(id: nil, name: name))
        }
        if kind == .fuel { flags[.fuelIsFull] = l.fuelIsFull == true }
        recompute()
    }

    private mutating func unstick(_ f: FormField) {
        guard let n = f.unstickName else { return }
        estimates.remove(n)
        stickyEstimates.remove(n)
    }

    private mutating func setUser(_ f: FormField, _ text: String) {
        fields[f] = FieldState(text: text, isUser: !text.isEmpty)
    }

    private mutating func setAuto(_ f: FormField, _ text: String) {
        fields[f] = FieldState(text: text, isUser: state(f).isUser, isAuto: true)
    }

    private mutating func setAuto(_ f: FormField, _ v: Double, _ digits: Int) { setAuto(f, JSNumber.trimmed(v, digits)) }
    private mutating func setAuto(_ f: FormField, _ v: Decimal, _ digits: Int) { setAuto(f, v.rounded(scale: digits).plainString) }

    // MARK: 默认值与载入

    private mutating func applyDefaults() {
        switch kind {
        case .fuel: fuelGrade = vehicle.defaultFuelGrade ?? "92"
        case .charge: chargeType = vehicle.defaultChargeType ?? "home"
        case .snapshot: snapshotTag = "other"
        }
    }

    /// 打开新表单时：保留上一类型已填的里程和备注，按设置默认选中第一个常用地点。
    public mutating func carryOver(odometer: String?, note: String?, placeDefaultTop: Bool, preset snapshotPreset: String? = nil) {
        if let odometer, !odometer.isEmpty { setUser(.odometer, odometer) }
        if let note { self.note = note }
        if kind == .snapshot { snapshotTag = snapshotPreset ?? "other" }
        if placeDefaultTop, kind != .snapshot, let first = prefill.places.first { applyPlace(first) }
        recompute()
    }

    private mutating func fill(from r: Record, finish: Bool, now: LocalDateTime) {
        if let odo = r.odometerKm, !r.isOdometerEstimated { setUser(.odometer, JSNumber.jsString(odo)) }
        if r.isOdometerEstimated { flags[.odoUnknown] = true }
        let est = r.estimated
        func put(_ f: FormField, _ v: Double?, _ estName: String? = nil) {
            guard let v else { return }
            setUser(f, JSNumber.jsString(v))
            if let estName, est.contains(estName) { fields[f]?.showsEstimate = true }
        }
        switch RecordKind(rawValue: r.kind) ?? .fuel {
        case .fuel:
            fuelGrade = r.fuelGrade ?? "92"
            put(.fuelLiters, r.fuelLiters, "fuel_l")
            put(.fuelUnitPrice, r.fuelUnitPrice)
            flags[.fuelIsFull] = r.fuelIsFull == true
            put(.fuelBefore, r.fuelLevelBeforePct, "fuel_before_pct")
            put(.fuelAfter, r.fuelLevelAfterPct, "fuel_after_pct")
        case .charge:
            chargeType = r.chargeType ?? "home"
            put(.chargeKwh, r.chargeKwh, "charge_kwh")
            put(.socAfter, r.socAfterPct, "soc_after")
            flags[.chargeToLimit] = r.chargeToLimit == true
            put(.chargeMinutes, r.chargeMinutes.map(Double.init))
            if let c = r.energyFeeCents { setUser(.energyFee, (Decimal(c) / 100).plainString) }
            if let c = r.serviceFeeCents { setUser(.serviceFee, (Decimal(c) / 100).plainString) }
            put(.fuelBefore, r.fuelLevelBeforePct, "fuel_before_pct")
            if finish {
                let mins = now.minutes(since: r.occurredAt)
                if mins > 0 && mins < 3 * 24 * 60 { setUser(.chargeMinutes, String(mins)) }
            }
        case .snapshot:
            snapshotTag = r.snapshotTag ?? "other"
            put(.fuelBefore, r.fuelLevelBeforePct, "fuel_before_pct")
        }
        put(.socBefore, r.socBeforePct, "soc_before")
        if let a = r.amountCents { setUser(.amount, (Decimal(a) / 100).plainString) }
        if let e = r.extraFeeCents, kind != .snapshot { setUser(.extraFee, (Decimal(e) / 100).plainString) }
        flags[.missedBefore] = r.missedBefore == true
        note = r.note ?? ""
        if r.placeId != nil || (r.placeName?.isEmpty == false) {
            let pl = prefill.places.first(where: { $0.id == r.placeId && r.placeId != nil }) ?? Place(id: r.placeId, name: r.placeName ?? "")
            applyPlace(pl, defaults: false)
        }
    }

    // MARK: 自动推算

    /// 清掉之前自动填的值，按依赖重新算：先用用户填的两项算第三项，再按车辆参数推算，最后用自动值补齐。
    public mutating func recompute() {
        for f in FormField.allCases where state(f).isAuto { fields[f] = FieldState(text: "", isUser: state(f).isUser) }
        for f in FormField.allCases { if let n = f.estimateName { estimates.remove(n) } }
        estimates.formUnion(stickyEstimates)
        func markEst(_ f: FormField) { if let n = f.estimateName { estimates.insert(n) } }

        threeFillTwo(userOnly: true)

        if kind == .fuel, let tank = vehicle.tankCapacityL, tank > 0 {
            let lvDigits = fuelUnit == "pct" && vehicle.fuelGaugeMode != "bars" ? 0 : 2
            let full = flag(.fuelIsFull)
            let before = number(.fuelBefore)
            let liters = number(.fuelLiters)
            if full {
                if let before, liters == nil, !isUser(.fuelLiters) {
                    setAuto(.fuelLiters, ((100 - before) / 100) * tank, 1)
                    markEst(.fuelLiters)
                } else if let liters, before == nil, !isUser(.fuelBefore), exists(.fuelBefore) {
                    setAuto(.fuelBefore, max(0, ((tank - liters) / tank) * 100), lvDigits)
                    markEst(.fuelBefore)
                }
            } else if let before, let liters, exists(.fuelAfter), !isUser(.fuelAfter) {
                setAuto(.fuelAfter, min(100, before + (liters / tank) * 100), lvDigits)
                markEst(.fuelAfter)
            }
        }

        if kind == .charge {
            let swap = chargeType == "swap"
            let toLimit = flag(.chargeToLimit)
            // 充到上限：结束 SOC 固定为上限值，不能手改
            if toLimit { fields[.socAfter] = FieldState(text: JSNumber.trimmed(vehicle.chargeLimitPct ?? 100, 0), isUser: false, isAuto: true) }
            let s0 = number(.socBefore)
            let s1 = number(.socAfter)
            let per: Double? = swap ? vehicle.batteryUsableKwh.map { $0 / 100 } : prefill.k
            if let s0, s1 == nil, !toLimit, let per, per != 0, isUser(.chargeKwh), let kwh = number(.chargeKwh) {
                setAuto(.socAfter, min(100, s0 + kwh / per), 0)
                markEst(.socAfter)
            }
            let ef = decimal(.energyFee), sf = decimal(.serviceFee)
            if ef != nil || sf != nil, !isUser(.amount), money(.amount) == nil {
                setAuto(.amount, (ef ?? 0) + (sf ?? 0), 2)
            }
            // 单价只由金额和电量算出；缺金额或电量的旧记录保留原来的单价
            let price: String
            if let amt = decimal(.amount), let kwh = decimal(.chargeKwh), kwh > 0 {
                price = (amt / kwh).rounded(scale: 3).plainString
            } else {
                price = editing?.chargeUnitPrice.map { JSNumber.jsString($0) } ?? ""
            }
            fields[.chargeUnitPrice] = FieldState(text: price)
        }

        threeFillTwo(userOnly: false)
    }

    /// 加油的数量、单价、金额三填二：用户填的两项算第三项（userOnly），或用自动值补齐。充电单价只读，在 recompute 里算。
    private mutating func threeFillTwo(userOnly: Bool) {
        guard kind == .fuel else { return }
        let qField: FormField = .fuelLiters
        let pField: FormField = .fuelUnitPrice
        func has(_ f: FormField) -> Bool { decimal(f) != nil && (!userOnly || isUser(f)) }
        let vq = decimal(qField), vp = decimal(pField), va = decimal(.amount)
        if has(qField), has(pField), !has(.amount), !isUser(.amount), let vq, let vp {
            setAuto(.amount, vq * vp, 2)
        } else if has(qField), has(.amount), !has(pField), !isUser(pField), let vq, let va, vq > 0 {
            setAuto(pField, va / vq, 2)
        } else if has(pField), has(.amount), !has(qField), !isUser(qField), let vp, let va, vp > 0 {
            setAuto(qField, va / vp, 2)
        }
    }

    // MARK: 峰谷电价

    public var tariffPlace: Place? { place.flatMap { $0.touTariff.isEmpty ? nil : $0 } }

    /// 峰谷电价只给参考金额，不替用户填。
    public var tariffNote: String? {
        guard let p = tariffPlace, kind == .charge, let kwh = decimal(.chargeKwh), kwh > 0,
              let amt = Self.tariffAmount(place: p, kwh: kwh, start: occurredAt, minutes: number(.chargeMinutes)) else { return nil }
        let cents = NSDecimalNumber(decimal: (amt * 100).rounded(scale: 0)).intValue
        return "按「\(p.name)」的峰谷电价约 \(Fmt.money(cents))"
    }

    /// 峰谷电价金额：按 5 分钟步长把电量平均分摊到各时段，最多算 3 天，支持跨午夜的时段；没有时长时按开始时刻的电价。
    public static func tariffAmount(place: Place?, kwh: Decimal, start: LocalDateTime, minutes: Double?) -> Decimal? {
        guard let tariff = place?.touTariff, !tariff.isEmpty, kwh != 0 else { return nil }
        func minuteOfDay(_ s: String) -> Int {
            let p = s.split(separator: ":").compactMap { Int($0) }
            return (p.first ?? 0) * 60 + (p.count > 1 ? p[1] : 0)
        }
        func priceAt(_ m: Int) -> Decimal {
            for t in tariff {
                let a = minuteOfDay(t.from), b = minuteOfDay(t.to)
                let inside = a <= b ? (m >= a && m < b) : (m >= a || m < b)
                if inside { return t.price }
            }
            return tariff[0].price
        }
        let startMin = start.hour * 60 + start.minute
        guard let minutes, minutes != 0 else { return kwh * priceAt(startMin) }
        let steps = min(minutes, 3 * 24 * 60)
        var sum = Decimal(0)
        var i = 0.0
        while i < steps {
            let m = (startMin + Int(i)) % (24 * 60)
            sum += priceAt(m) * Decimal(shortest: min(5, steps - i))
            i += 5
        }
        return kwh * sum / Decimal(shortest: steps)
    }

    // MARK: 显示用的派生值

    /// 液位标签：百分比加升数，或按格数。
    public func levelLabel(_ f: FormField) -> String {
        let t = text(f)
        guard !t.isEmpty, let v = JSNumber.parse(t) else { return "" }
        if f == .fuelBefore || f == .fuelAfter, vehicle.fuelGaugeMode == "bars", let n = vehicle.fuelGaugeBars, n > 0 {
            return "\(Int((v / 100 * Double(n)).rounded(.toNearestOrAwayFromZero)))/\(n) 格"
        }
        var out = "\(Fmt.num(v, 0))%"
        if (f == .fuelBefore || f == .fuelAfter), let tank = vehicle.tankCapacityL, tank > 0 {
            out += " · \(Fmt.num(v / 100 * tank, 1))L"
        }
        return out
    }

    /// 油量输入单位：上次在表单里选的，没选过按车辆的油表显示方式。
    public var fuelUnit: String { fuelUnitPref ?? (vehicle.fuelGaugeMode == "liters" ? "liters" : "pct") }

    public mutating func setFuelUnit(_ u: String) {
        fuelUnitPref = u
        recompute()
    }

    /// 按升的油表显示的升数。
    public func litersText(_ f: FormField) -> String {
        guard let v = JSNumber.parse(text(f)), !text(f).isEmpty, let tank = vehicle.tankCapacityL, tank > 0 else { return "" }
        return JSNumber.trimmed(v / 100 * tank, 1)
    }

    /// 本次里程增量提示。时间早于最新记录说明是在补录历史，里程比最新的小是正常的，不标红。
    /// 所选时间前后最近的两次里程读数；没有时间轴数据时退回最新里程。
    var odoNeighbors: (prev: OdoPoint?, next: OdoPoint?) {
        guard !prefill.odoPoints.isEmpty else {
            return (prefill.lastOdo.map { OdoPoint(ts: prefill.lastOdoTs ?? occurredAt, odo: $0) }, nil)
        }
        let prev = prefill.odoPoints.last { $0.ts < occurredAt }
        let next = prefill.odoPoints.first { $0.ts > occurredAt }
        return (prev, next)
    }

    public var odoHint: OdoHint {
        let (prev, next) = odoNeighbors
        let last = prev?.odo
        let trip = flag(.tripMode)
        let ph = trip ? "本次行驶公里数" : (last.map { "上次 \(Fmt.km($0))" } ?? "仪表盘总里程")
        if flag(.odoUnknown) { return OdoHint(text: "里程按前后记录推算", warn: false, placeholder: ph) }
        guard let raw = number(.odometer), let prev, let last else {
            return OdoHint(text: last.map { "上次 \(Fmt.km($0))" } ?? "", warn: false, placeholder: ph)
        }
        let delta = trip ? raw : raw - last
        let total = trip ? last + raw : raw
        // 补录历史：和所选时间之前的那次读数比，超过之后的读数才标红
        if let next {
            let text = total > next.odo
                ? "比之后 \(Fmt.date(next.ts)) 的 \(Fmt.km(next.odo)) km 还大"
                : "比 \(Fmt.date(prev.ts)) \(delta >= 0 ? "+" : "")\(Fmt.km(delta)) km"
            return OdoHint(text: text, warn: delta < 0 || total > next.odo, placeholder: ph)
        }
        let text = trip ? "总里程 \(Fmt.km(total))" : "本次 \(delta >= 0 ? "+" : "")\(Fmt.km(delta)) km"
        return OdoHint(text: text, warn: delta < 0 || delta > 2000, placeholder: ph)
    }

    // MARK: 提交

    /// 生成提交体。`clientId` 只在新建时生成；编辑时带上原记录的 `version`。
    public func collect(startOnly: Bool = false, clientId: String? = nil, now: LocalDateTime = LocalDateTime(date: Date())) -> RecordPayload {
        var b = RecordPayload(vehicleId: vehicle.id, kind: kind.rawValue, occurredAt: occurredAt)
        let trip = flag(.tripMode)
        var odo: Double? = flag(.odoUnknown) ? nil : JSNumber.parse(text(.odometer))
        if let o = odo, trip, let last = odoNeighbors.prev?.odo { odo = last + o }
        func cents(_ f: FormField) -> Int? { money(f)?.cents }
        var est = estimates
        let amount = cents(.amount)
        b.status = startOnly ? "in_progress" : "done"
        b.odometerKm = odo
        b.odometerEstimated = odo == nil
        let sevenDaysAgo = now.addingDays(-7)
        b.source = editing?.source ?? (occurredAt < sevenDaysAgo ? "backfill" : "manual")
        b.note = note.trimmingCharacters(in: .whitespacesAndNewlines)
        b.missedBefore = flag(.missedBefore)
        b.amountCents = amount
        b.extraFeeCents = cents(.extraFee)
        b.socBeforePct = number(.socBefore)
        b.fuelLevelBeforePct = number(.fuelBefore)
        b.placeId = place?.id
        b.placeName = place?.name
        b.lat = coords?.lat
        b.lng = coords?.lng
        switch kind {
        case .fuel:
            b.fuelGrade = fuelGrade
            b.fuelLiters = number(.fuelLiters)
            b.fuelUnitPrice = number(.fuelUnitPrice)
            b.fuelIsFull = flag(.fuelIsFull)
            b.fuelLevelAfterPct = flag(.fuelIsFull) ? nil : number(.fuelAfter)
        case .charge:
            b.chargeType = chargeType ?? "home"
            b.chargeKwh = startOnly ? nil : number(.chargeKwh)
            b.chargeUnitPrice = startOnly ? nil : number(.chargeUnitPrice)
            b.chargeToLimit = startOnly ? false : flag(.chargeToLimit)
            b.socAfterPct = startOnly ? nil : number(.socAfter)
            b.chargeMinutes = number(.chargeMinutes).map { Int($0.rounded(.toNearestOrAwayFromZero)) }
            b.energyFeeCents = cents(.energyFee)
            b.serviceFeeCents = cents(.serviceFee)
            if startOnly { b.amountCents = nil }
        case .snapshot:
            b.snapshotTag = snapshotTag ?? "other"
        }
        if odo == nil { est.insert("odometer_km") } else { est.remove("odometer_km") }
        b.estimatedFields = est.sorted()
        // 编辑已保存的记录带 version；新建和待同步记录带 client_id，重发时复用同一个
        if let v = editing?.version { b.version = v } else { b.clientId = clientId }
        return b
    }

    /// 保存前的校验，提示文字与网页版一致；通过时返回 nil。
    public func validate(_ b: RecordPayload) -> String? {
        if b.odometerKm == nil && !flag(.odoUnknown) { return "请填写里程，或勾选「不确定里程」" }
        if b.kind == "snapshot" && b.odometerKm == nil && b.socBeforePct == nil && b.fuelLevelBeforePct == nil {
            return "快照至少要填里程、电量或油量中的一项"
        }
        if b.kind == "fuel" && b.status == "done" && b.fuelLiters == nil && b.amountCents == nil { return "请至少填写加油量或金额" }
        for v in [b.socBeforePct, b.socAfterPct, b.fuelLevelBeforePct, b.fuelLevelAfterPct] {
            if let v, v < 0 || v > 100 { return "电量和油量要在 0–100% 之间" }
        }
        return nil
    }

    // MARK: 草稿

    public func draft() -> FormDraft {
        var f: [String: String] = [:]
        for (k, v) in fields where v.isUser && !v.text.isEmpty { f[k.rawValue] = v.text }
        var fl: [String: Bool] = [:]
        for (k, v) in flags { fl[k.rawValue] = v }
        return FormDraft(fields: f, flags: fl, fuelGrade: fuelGrade, chargeType: chargeType, snapshotTag: snapshotTag,
                         place: place, savedAt: Date(), note: note)
    }

    /// 恢复草稿，不覆盖时间；恢复后用户填的字段仍是用户值。
    public mutating func restore(_ d: FormDraft) {
        for (k, v) in d.fields { if let f = FormField(rawValue: k), !(kind == .charge && f == .chargeUnitPrice) { setUser(f, v) } }
        for (k, v) in d.flags { if let f = FormFlag(rawValue: k) { flags[f] = v } }
        if flag(.odoUnknown) { fields[.odometer] = FieldState() }
        if let g = d.fuelGrade { fuelGrade = g }
        if let c = d.chargeType { chargeType = c }
        if let t = d.snapshotTag { snapshotTag = t }
        if let p = d.place { applyPlace(p, defaults: false) }
        if !d.note.isEmpty { note = d.note }
        recompute()
    }

    /// 已保存的记录里「更多」区域有内容时默认展开。
    public static func hasMoreContent(_ r: Record) -> Bool {
        r.fuelLevelBeforePct != nil || r.fuelLevelAfterPct != nil || r.missedBefore == true || (r.extraFeeCents ?? 0) != 0 ||
            (r.chargeMinutes ?? 0) != 0 || r.energyFeeCents != nil
    }
}

public extension JSNumber {
    /// 等同 String(Number)：整数不带小数点。
    static func jsString(_ x: Double) -> String {
        if x == x.rounded(), abs(x) < 1e15 { return String(Int64(x)) }
        return "\(x)"
    }
}
