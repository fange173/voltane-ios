import Foundation
import Testing
@testable import VoltaneKit

private let goldenNow = LocalDateTime("2026-10-27T12:00")!
private let defaultAt = LocalDateTime("2026-10-27T08:30")!

private func eq(_ a: JSONValue, _ b: JSONValue) -> Bool {
    if let x = a.number, let y = b.number { return abs(x - y) < 1e-9 }
    return a == b
}

/// 按网页版的操作脚本在 Swift 状态机上重放。
private func replay(_ c: WebGolden.Case, _ g: WebGolden) throws -> (RecordFormState, startOnly: Bool) {
    let vehicle = try g.vehicle(c.veh)
    let prefill = try g.prefill(for: c)
    let kind = RecordKind(rawValue: c.kind)!
    var st: RecordFormState
    if let rec = c.record {
        guard case .object(var o) = rec else { throw GoldenError.badRecord }
        o["vehicle_id"] = .int(1); o["version"] = .int(1); o["type"] = .string("record")
        st = RecordFormState(vehicle: vehicle, record: try JSONValue.object(o).decoded(Record.self), prefill: prefill, now: goldenNow)
    } else {
        st = RecordFormState(vehicle: vehicle, kind: kind, prefill: prefill, now: goldenNow)
        st.carryOver(odometer: nil, note: nil, placeDefaultTop: false)
        st.setOccurredAt(defaultAt)
    }
    var startOnly = false
    for a in c.act {
        let op = a[0].stringValue!
        switch op {
        case "type":
            let name = a[1].stringValue!, value = a[2].stringValue!
            if name == "occurred_at" { st.setOccurredAt(LocalDateTime(value)!) }
            else if name == "note" { st.note = value }
            else { st.input(FormField(rawValue: name)!, value) }
        case "check": st.setFlag(FormFlag(rawValue: a[1].stringValue!)!, a[2].boolValue!)
        case "chip":
            let chip: FormChip = ["grade": .grade, "ctype": .chargeType, "snap": .snapshotTag][a[1].stringValue!]!
            st.selectChip(chip, a[2].stringValue ?? String(a[2].intValue ?? 0))
        case "place": st.selectPlace(prefill.places.first { $0.id == a[1].intValue })
        case "bar": st.tapBar(FormField(rawValue: a[1].stringValue!)!, bar: a[2].intValue!)
        case "lit": st.setLiters(FormField(rawValue: a[1].stringValue!)!, a[2].stringValue!)
        case "same": st.copyLast()
        case "start": startOnly = true
        default: Issue.record("未知操作 \(op)")
        }
    }
    return (st, startOnly)
}

private enum GoldenError: Error { case badRecord }

private func flagCode(_ s: FieldState) -> String { s.isAuto ? "a" : s.isUser ? "u" : "" }

@Suite struct FormMathTests {
    static let golden = try! WebGolden.load()

    @Test func atLeast25Cases() { #expect(Self.golden.cases.count >= 25) }

    @Test(arguments: golden.cases.map(\.name))
    func matchesWebForm(name: String) throws {
        let g = Self.golden
        let c = try #require(g.cases.first { $0.name == name })
        let (st, startOnly) = try replay(c, g)
        let e = c.expected

        for f in FormField.allCases {
            let actual = st.state(f)
            if let exp = e.f[f.rawValue] {
                #expect(actual.text == exp[0], "\(name): \(f.rawValue) 文本")
                #expect(flagCode(actual) == exp[1], "\(name): \(f.rawValue) 状态")
            } else {
                #expect(actual.text.isEmpty, "\(name): \(f.rawValue) 应为空，实际 \(actual.text)")
            }
        }
        for (k, v) in e.chips ?? [:] {
            let actual: String? = ["fuel_grade": st.fuelGrade, "charge_type": st.chargeType, "snapshot_tag": st.snapshotTag][k] ?? nil
            #expect(actual == v, "\(name): 胶囊 \(k)")
        }
        for (k, v) in e.sel ?? [:] { #expect(st.flag(FormFlag(rawValue: k)!) == v, "\(name): 开关 \(k)") }
        if let odo = e.odo {
            let h = st.odoHint
            #expect(h.text == odo.t, "\(name): 里程提示")
            #expect(h.warn == odo.w, "\(name): 里程提示标红")
        }
        if let ph = e.odoPh { #expect(st.odoHint.placeholder == ph) }
        #expect(st.tariffNote == e.tariff, "\(name): 峰谷电价参考")
        for (k, v) in e.lv ?? [:] { #expect(st.levelLabel(FormField(rawValue: k)!) == v, "\(name): 液位标签 \(k)") }
        if let lit = e.lit { #expect(st.litersText(.fuelBefore) == lit, "\(name): 升数") }

        let payload = st.collect(startOnly: startOnly, clientId: nil, now: goldenNow)
        let err = st.validate(payload) ?? ""
        #expect(err == e.err, "\(name): 校验提示")
        guard let body = e.body, err.isEmpty else { return }
        let data = try JSONCoding.encoder.encode(payload)
        guard case .object(var actual) = try JSONDecoder().decode(JSONValue.self, from: data) else { return }
        actual = actual.filter { !$0.value.isNull && !["client_id", "version", "force"].contains($0.key) }
        for (k, v) in body {
            if k == "estimated_fields" {
                let exp = Set(v.arrayStrings), act = Set(actual[k]?.arrayStrings ?? [])
                #expect(exp == act, "\(name): estimated_fields \(act) ≠ \(exp)")
            } else {
                let same: Bool = actual[k].map { eq($0, v) } ?? false
                #expect(same, "\(name): 提交体 \(k) 实际 \(String(describing: actual[k])) 期望 \(v)")
            }
        }
        for k in actual.keys where body[k] == nil && k != "estimated_fields" {
            if actual[k] == .bool(false) { continue }
            if k == "estimated_fields" { continue }
            #expect(Bool(false), "\(name): 提交体多出 \(k) = \(String(describing: actual[k]))")
        }
        if body["estimated_fields"] == nil {
            let extra: [String] = actual["estimated_fields"]?.arrayStrings ?? []
            #expect(extra.isEmpty)
        }
    }

    @Test func utilAmountExpressionsMatchWeb() {
        for pair in Self.golden.util.amount {
            guard case .array(let a) = pair, let input = a[0].stringValue else { continue }
            let got = AmountExpression.evaluate(input)
            if let exp = a[1].number {
                #expect(got.map { abs($0.doubleValue - exp) < 1e-9 } ?? false, "算式 \(input)")
            } else {
                #expect(got == nil, "算式 \(input) 应为非法")
            }
        }
    }

    @Test func utilNumberFormattingMatchesWeb() {
        for row in Self.golden.util.num {
            let x = row[0].number, digits = row[1].intValue!
            #expect(Fmt.num(x, digits) == row[2].stringValue, "num(\(String(describing: x)), \(digits))")
            #expect(Fmt.fixed(x, digits) == row[3].stringValue, "fixed(\(String(describing: x)), \(digits))")
        }
        for row in Self.golden.util.km { #expect(Fmt.km(row[0].number) == row[1].stringValue, "km(\(row[0]))") }
        for row in Self.golden.util.money {
            if case .double = row[0] { continue }
            let cents = row[0].intValue
            #expect(Fmt.money(cents, sign: row[1].boolValue == true) == row[2].stringValue, "money(\(String(describing: cents)))")
        }
        for row in Self.golden.util.gauge {
            let v = Vehicle(id: 1, name: "t", energyType: "phev", hasFuel: true, hasElec: true, tankCapacityL: row[2].number,
                            fuelGaugeMode: row[1].stringValue, fuelGaugeBars: row[3].intValue)
            #expect(Fmt.fuelLevel(row[0].number, vehicle: v) == row[4].stringValue, "fuelLevel(\(row[0]), \(row[1]))")
        }
        for row in Self.golden.util.pct {
            let got = Fmt.pctChange(row[0].number, row[1].number)
            if let exp = row[2].number { #expect(got.map { abs($0 - exp) < 1e-9 } ?? false) } else { #expect(got == nil) }
        }
    }
}

extension JSONValue {
    var arrayStrings: [String] {
        if case .array(let a) = self { return a.compactMap(\.stringValue) }
        return []
    }
}
