import Foundation

/// 与网页版 JavaScript 数值行为对齐的取整与转换。
public enum JSNumber {
    /// 等同 Number.prototype.toFixed：按二进制精确值取位，恰好在中间时进位。
    public static func toFixed(_ x: Double, _ digits: Int) -> String {
        guard x.isFinite else { return "NaN" }
        let negative = x < 0
        let exact = String(format: "%.\(digits + 40)f", abs(x))
        let parts = exact.split(separator: ".", omittingEmptySubsequences: false)
        var integer = Array(parts[0])
        let fraction = Array(parts.count > 1 ? parts[1] : "")
        var kept = Array(fraction.prefix(digits))
        if fraction.count > digits, let next = fraction[digits].wholeNumberValue, next >= 5 {
            var carry = true
            var i = kept.count - 1
            while carry && i >= 0 {
                if kept[i] == "9" { kept[i] = "0"; i -= 1 } else { kept[i] = Character(String(kept[i].wholeNumberValue! + 1)); carry = false }
            }
            var j = integer.count - 1
            while carry && j >= 0 {
                if integer[j] == "9" { integer[j] = "0"; j -= 1 } else { integer[j] = Character(String(integer[j].wholeNumberValue! + 1)); carry = false }
            }
            if carry { integer.insert("1", at: 0) }
        }
        let body = String(integer) + (digits > 0 ? "." + String(kept) : "")
        return negative ? "-" + body : body
    }

    /// 等同 String(+x.toFixed(digits))：去掉多余的 0，-0 显示为 0。
    public static func trimmed(_ x: Double, _ digits: Int) -> String {
        trim(toFixed(x, digits))
    }

    static func trim(_ s: String) -> String {
        var out = s
        if out.contains(".") {
            while out.hasSuffix("0") { out.removeLast() }
            if out.hasSuffix(".") { out.removeLast() }
        }
        return out == "-0" || out == "" ? "0" : out
    }

    /// 等同 toNum：去掉逗号和空白后解析，非有限数返回 nil。
    public static func parse(_ text: String) -> Double? {
        if text.isEmpty { return nil }
        let cleaned = text.filter { !"，, \t\n".contains($0) }
        if cleaned.isEmpty { return 0 }
        guard cleaned.allSatisfy({ "0123456789.eE+-".contains($0) }), let v = Double(cleaned), v.isFinite else { return nil }
        return v
    }
}

public extension Decimal {
    init?(plain text: String) {
        guard let v = Decimal(string: text, locale: Locale(identifier: "en_US_POSIX")) else { return nil }
        self = v
    }

    /// 由 Double 的最短十进制表示得到 Decimal，避免二进制误差。
    init(shortest x: Double) {
        self = Decimal(string: "\(x)", locale: Locale(identifier: "en_US_POSIX")) ?? Decimal(x)
    }

    func rounded(scale: Int) -> Decimal {
        var src = self
        var dst = Decimal()
        NSDecimalRound(&dst, &src, scale, .plain)
        return dst
    }

    var doubleValue: Double { NSDecimalNumber(decimal: self).doubleValue }

    /// 去掉多余的 0 的十进制字符串。
    var plainString: String {
        JSNumber.trim(NSDecimalNumber(decimal: self).description(withLocale: Locale(identifier: "en_US_POSIX")))
    }

    /// 金额（元）转整数分，四舍五入。
    var cents: Int {
        (self * 100).rounded(scale: 0).intValue
    }

    var intValue: Int { NSDecimalNumber(decimal: self).intValue }
}
