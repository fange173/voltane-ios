import Foundation

/// 服务端时间字符串的拆分结果：`YYYY-MM-DD`、`YYYY-MM-DDTHH:MM[:SS[.ffffff]]`，可带 `Z` 或 `±HH:MM`。
struct Stamp {
    var year = 0, month = 0, day = 0, hour = 0, minute = 0, second = 0
    var hasTime = false
    var offsetMinutes: Int?

    init?(_ text: String) {
        let s = text.trimmingCharacters(in: .whitespaces)
        let sepIndex = s.firstIndex(where: { $0 == "T" || $0 == " " })
        let datePart = sepIndex.map { String(s[..<$0]) } ?? s
        let d = datePart.split(separator: "-", omittingEmptySubsequences: false)
        guard d.count == 3, d[0].count == 4, let y = Int(d[0]), let m = Int(d[1]), let dd = Int(d[2]),
              (1...12).contains(m), (1...31).contains(dd) else { return nil }
        year = y; month = m; day = dd
        guard let sepIndex else { return }
        var rest = String(s[s.index(after: sepIndex)...])
        if rest.hasSuffix("Z") { rest.removeLast(); offsetMinutes = 0 }
        else if let i = rest.lastIndex(where: { $0 == "+" || $0 == "-" }), rest.distance(from: rest.startIndex, to: i) >= 5 {
            let off = rest[rest.index(after: i)...].replacingOccurrences(of: ":", with: "")
            guard off.count == 4, let h = Int(off.prefix(2)), let mi = Int(off.suffix(2)) else { return nil }
            offsetMinutes = (rest[i] == "-" ? -1 : 1) * (h * 60 + mi)
            rest = String(rest[..<i])
        }
        let t = rest.split(separator: ":", omittingEmptySubsequences: false)
        guard t.count >= 2, let h = Int(t[0]), let mi = Int(t[1]), (0...23).contains(h), (0...59).contains(mi) else { return nil }
        hour = h; minute = mi
        if t.count > 2 { second = Int(t[2].split(separator: ".")[0]) ?? 0 }
        hasTime = true
    }

    func components() -> DateComponents {
        DateComponents(year: year, month: month, day: day, hour: hour, minute: minute, second: second)
    }
}
