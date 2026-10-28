import Foundation

/// 数字、金额、日期的显示格式，对应网页版 `util.js` 与 `state.js`。空值统一显示「–」。
public enum Fmt {
    public static let dash = "–"

    /// ICU 风格取整：按最短十进制表示四舍五入（1.005 → 1.01）。
    static func rounded(_ x: Double, _ digits: Int) -> Decimal {
        Decimal(shortest: x).rounded(scale: digits)
    }

    private static func grouped(_ d: Decimal, fixedDigits: Int?, maxDigits: Int) -> String {
        let negative = d < 0
        let digits = fixedDigits ?? maxDigits
        let r = abs(d).rounded(scale: digits)
        var s = NSDecimalNumber(decimal: r).description(withLocale: Locale(identifier: "en_US_POSIX"))
        var frac = ""
        if let dot = s.firstIndex(of: ".") {
            frac = String(s[s.index(after: dot)...])
            s = String(s[..<dot])
        }
        if let f = fixedDigits { while frac.count < f { frac += "0" } }
        var out = ""
        for (i, ch) in s.reversed().enumerated() {
            if i > 0 && i % 3 == 0 { out.append(",") }
            out.append(ch)
        }
        out = String(out.reversed()) + (frac.isEmpty ? "" : "." + frac)
        let isZero = r == 0
        return (negative && !isZero ? "-" : "") + out
    }

    public static func num(_ x: Double?, _ digits: Int = 2) -> String {
        guard let x, x.isFinite else { return dash }
        return grouped(Decimal(shortest: x), fixedDigits: nil, maxDigits: digits)
    }

    public static func fixed(_ x: Double?, _ digits: Int = 2) -> String {
        guard let x, x.isFinite else { return dash }
        return grouped(Decimal(shortest: x), fixedDigits: digits, maxDigits: digits)
    }

    public static func km(_ x: Double?) -> String {
        guard let x, x.isFinite else { return dash }
        return grouped(Decimal(shortest: x), fixedDigits: nil, maxDigits: 0)
    }

    /// 整数分转金额文字：不经过浮点数；绝对值 ≥ 10000 元时不显示小数。
    public static func money(_ cents: Int?, sign: Bool = false, digits: Int? = nil) -> String {
        guard let cents else { return dash }
        let yuan = Decimal(cents) / 100
        let d = digits ?? (abs(cents) >= 1_000_000 ? 0 : 2)
        let body = grouped(abs(yuan), fixedDigits: d, maxDigits: d)
        return (cents < 0 ? "-" : sign ? "+" : "") + "¥" + body
    }

    /// 较上一期的变化比例；上期为空或 0 时返回 nil。
    /// 环比的最小基数：上期里程不足 100km 或金额不足 100 元时百分比没有参考意义。
    public static let minChangeKm = 100.0
    public static let minChangeCents = 10_000.0

    /// 和上一周期比的变化比例；上期基数小于 min 时返回 nil。
    public static func pctChange(_ cur: Double?, _ prev: Double?, min: Double = 0) -> Double? {
        guard let cur, let prev, prev != 0, abs(prev) >= min else { return nil }
        return (cur - prev) / abs(prev)
    }

    public static func durationText(minutes: Int?) -> String {
        guard let minutes else { return dash }
        let h = minutes / 60
        let m = minutes % 60
        return h > 0 ? "\(h)小时\(m > 0 ? "\(m)分" : "")" : "\(m)分钟"
    }

    /// 按车辆的油表显示方式把油量百分比换成「40%」「19.2 L」「3/8 格」；无值返回空串。
    public static func fuelLevel(_ pct: Double?, vehicle: Vehicle?) -> String {
        guard let pct else { return "" }
        if vehicle?.fuelGaugeMode == "liters", let tank = vehicle?.tankCapacityL, tank > 0 {
            return "\(JSNumber.trimmed(pct / 100 * tank, 1)) L"
        }
        if vehicle?.fuelGaugeMode == "bars", let bars = vehicle?.fuelGaugeBars, bars > 0 {
            return "\(Int((pct / 100 * Double(bars)).rounded(.toNearestOrAwayFromZero)))/\(bars) 格"
        }
        return "\(Int(pct.rounded(.toNearestOrAwayFromZero)))%"
    }

    // MARK: 日期

    private static let week = Array("日一二三四五六")

    /// `MM-DD`，与当前年不同时带年份；可附带星期和时间。
    public static func date(_ d: LocalDateTime?, now: LocalDateTime = LocalDateTime(date: Date()),
                            year: Bool? = nil, time: Bool = false, week showWeek: Bool = false,
                            calendar: Calendar = .current) -> String {
        guard let d else { return dash }
        let showYear = year ?? (d.year != now.year)
        var out = (showYear ? String(format: "%04d-", d.year) : "") + String(format: "%02d-%02d", d.month, d.day)
        if showWeek {
            let wd = calendar.component(.weekday, from: d.date(calendar: calendar)) - 1
            out += " 周\(week[wd])"
        }
        if time { out += " " + d.timeText }
        return out
    }

    /// 今天、昨天、前天，其余显示日期加星期。
    public static func relDay(_ d: LocalDateTime, now: LocalDateTime = LocalDateTime(date: Date()),
                              calendar: Calendar = .current) -> String {
        let a = calendar.startOfDay(for: d.date(calendar: calendar))
        let b = calendar.startOfDay(for: now.date(calendar: calendar))
        let diff = calendar.dateComponents([.day], from: a, to: b).day ?? 0
        switch diff {
        case 0: return "今天"
        case 1: return "昨天"
        case 2: return "前天"
        default: return date(d, now: now, week: true, calendar: calendar)
        }
    }
}
