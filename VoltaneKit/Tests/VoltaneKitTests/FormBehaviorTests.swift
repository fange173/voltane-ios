import Foundation
import Testing
@testable import VoltaneKit

private let now = LocalDateTime("2026-10-27T12:00")!

private func phev(tank: Double? = 48) -> Vehicle {
    Vehicle(id: 1, name: "秦", energyType: "phev", hasFuel: true, hasElec: true, tankCapacityL: tank, batteryUsableKwh: 18.3)
}

private func prefill() -> Prefill { Prefill(k: 0.2, lastOdo: 10000, lastOdoTs: LocalDateTime("2026-10-20T08:00")) }

@Suite struct AmountExpressionTests {
    @Test func basicArithmetic() {
        #expect(AmountExpression.evaluate("200+15") == 215)
        #expect(AmountExpression.evaluate("(1+2)*3") == 9)
        #expect(AmountExpression.evaluate("10/4") == Decimal(string: "2.5"))
        #expect(AmountExpression.evaluate("1,000.5") == Decimal(string: "1000.5"))
        #expect(AmountExpression.evaluate("¥12") == 12)
    }

    @Test func unicodeOperators() {
        #expect(AmountExpression.evaluate("12×3") == 36)
        #expect(AmountExpression.evaluate("100÷8") == Decimal(string: "12.5"))
        #expect(AmountExpression.evaluate("2×(3+4)÷7") == 2)
    }

    @Test func invalidReturnsNil() {
        for s in ["", "abc", "1++2", "3*(2+", "1/0", "5.", "+5", "1e3", "１２", "((", ")"] {
            #expect(AmountExpression.evaluate(s) == nil, "\(s)")
        }
    }

    @Test func decimalExactNotFloat() {
        #expect(AmountExpression.evaluate("0.1+0.2") == Decimal(string: "0.3"))
        #expect(AmountExpression.cents("0.1+0.2") == 30)
        #expect(AmountExpression.cents("19.99*3") == 5997)
        #expect(AmountExpression.cents("2.675") == 268)
    }
}

@Suite struct FmtTests {
    @Test func nullsAreDashes() {
        #expect(Fmt.num(nil) == "–" && Fmt.fixed(nil) == "–" && Fmt.km(nil) == "–" && Fmt.money(nil) == "–")
        #expect(Fmt.num(.nan) == "–" && Fmt.num(.infinity) == "–" && Fmt.km(-.infinity) == "–")
        #expect(Fmt.durationText(minutes: nil) == "–" && Fmt.fuelLevel(nil, vehicle: nil) == "")
    }

    @Test func zeroIsNeverTrimmed() {
        #expect(Fmt.num(30) == "30" && Fmt.num(100, 0) == "100" && Fmt.num(0) == "0" && Fmt.km(30) == "30")
        #expect(JSNumber.trimmed(30, 0) == "30" && JSNumber.trimmed(50, 1) == "50" && JSNumber.trimmed(100, 2) == "100")
        #expect(Fmt.money(3000) == "¥30.00" && Fmt.money(1_000_000) == "¥10,000")
    }

    @Test func toFixedMatchesJavaScript() {
        #expect(JSNumber.toFixed(1.005, 2) == "1.00")
        #expect(JSNumber.toFixed(0.125, 2) == "0.13")
        #expect(JSNumber.toFixed(2.5, 0) == "3")
        #expect(JSNumber.toFixed(-1.5, 0) == "-2")
        #expect(JSNumber.toFixed(99.995, 2) == "100.00" || JSNumber.toFixed(99.995, 2) == "99.99")
        #expect(JSNumber.toFixed(37.5, 1) == "37.5" && JSNumber.toFixed(25, 1) == "25.0")
        #expect(JSNumber.trimmed(-0.0001, 2) == "0")
    }

    @Test func moneyNeverUsesDouble() {
        #expect(Fmt.money(1) == "¥0.01" && Fmt.money(-550) == "-¥5.50" && Fmt.money(5, sign: true) == "+¥0.05")
        #expect(Fmt.money(999_999_999_999) == "¥10,000,000,000")
    }
}

@Suite struct FormBehaviorTests {
    /// 红线：编辑提车快照保存时不能报「数据不全」，估算标记和原来源保留。
    @Test func editingDeliverySnapshotSavesWithoutIncompleteError() throws {
        let json = #"""
        {"id":5,"vehicle_id":1,"kind":"snapshot","occurred_at":"2025-12-31T09:00","odometer_km":12,"odometer_estimated":false,
         "snapshot_tag":"delivery","fuel_level_before_pct":10.42,"soc_before_pct":null,"estimated_fields":["fuel_before_pct"],
         "source":"manual","note":"提车","version":3}
        """#
        let rec = try JSONCoding.decoder.decode(Record.self, from: Data(json.utf8))
        var st = RecordFormState(vehicle: phev(), record: rec, prefill: prefill(), now: now)
        var payload = st.collect(now: now)
        #expect(st.validate(payload) == nil)
        #expect(payload.snapshotTag == "delivery" && payload.odometerKm == 12 && payload.version == 3)
        #expect(payload.estimatedFields == ["fuel_before_pct"] && payload.source == "manual")
        st.input(.odometer, "15")
        payload = st.collect(now: now)
        #expect(st.validate(payload) == nil && payload.odometerKm == 15 && payload.estimatedFields == ["fuel_before_pct"])
        st.input(.fuelBefore, "20")
        payload = st.collect(now: now)
        #expect(st.validate(payload) == nil && payload.estimatedFields.isEmpty)
    }

    @Test func editingKeepsStoredValuesAndShowsEstimateStyle() throws {
        let json = #"""
        {"id":9,"vehicle_id":1,"kind":"charge","occurred_at":"2026-10-26T20:00","odometer_km":10100,"charge_type":"home",
         "charge_kwh":16,"soc_before_pct":10,"soc_after_pct":90,"amount_cents":480,"paid_cents":480,"charge_unit_price":0.3,
         "estimated_fields":["charge_kwh","paid_cents"],"source":"import","version":2}
        """#
        let rec = try JSONCoding.decoder.decode(Record.self, from: Data(json.utf8))
        var st = RecordFormState(vehicle: phev(), record: rec, prefill: prefill(), now: now)
        #expect(st.text(.chargeKwh) == "16" && st.state(.chargeKwh).showsEstimate && !st.state(.chargeKwh).isAuto)
        #expect(st.collect(now: now).source == "import")
        st.input(.chargeKwh, "15")
        #expect(!st.collect(now: now).estimatedFields.contains("charge_kwh"))
    }

    /// 编辑已保存的记录：地点的默认方式、标号、单价不能覆盖记录原值；用户主动换地点时才带出默认值。
    @Test func editingKeepsChargeTypeGradeAndPriceDespitePlaceDefaults() throws {
        let home = Place(id: 11, name: "家里车位", defaultChargeType: "home")
        let gas = Place(id: 12, name: "中石化", defaultFuelGrade: "95", lastUnitPrice: 7.62)
        let pf = Prefill(k: 0.2, lastOdo: 10000, places: [home, gas])
        let charge = #"{"id":1,"vehicle_id":1,"kind":"charge","occurred_at":"2026-10-26T20:00","odometer_km":10100,"charge_type":"public_ac","charge_kwh":16,"charge_unit_price":1.2,"amount_cents":1920,"place_id":11,"place_name":"家里车位","estimated_fields":[],"version":1}"#
        var st = RecordFormState(vehicle: phev(), record: try JSONCoding.decoder.decode(Record.self, from: Data(charge.utf8)), prefill: pf, now: now)
        #expect(st.collect(now: now).chargeType == "public_ac")
        st.selectPlace(home)
        #expect(st.collect(now: now).chargeType == "home")
        let fuel = #"{"id":2,"vehicle_id":1,"kind":"fuel","occurred_at":"2026-10-26T20:00","odometer_km":10100,"fuel_grade":"92","fuel_liters":20,"amount_cents":15000,"place_id":12,"place_name":"中石化","estimated_fields":[],"version":1}"#
        let st2 = RecordFormState(vehicle: phev(), record: try JSONCoding.decoder.decode(Record.self, from: Data(fuel.utf8)), prefill: pf, now: now)
        let p2 = st2.collect(now: now)
        #expect(p2.fuelGrade == "92" && p2.fuelUnitPrice == 7.5 && p2.amountCents == 15000)
    }

    @Test func backfillComparesWithReadingBeforeChosenTime() {
        let pts = [("2026-10-01T08:00", 9000.0), ("2026-10-10T08:00", 9500.0), ("2026-10-20T08:00", 10000.0)]
            .map { OdoPoint(ts: LocalDateTime($0.0)!, odo: $0.1) }
        var st = RecordFormState(vehicle: phev(), kind: .fuel, prefill: Prefill(lastOdo: 10000, odoPoints: pts), now: now)
        st.setOccurredAt(LocalDateTime("2026-10-05T08:00")!)
        st.input(.odometer, "9200")
        #expect(st.odoHint.text.contains("+200") && !st.odoHint.warn && st.odoHint.placeholder == "上次 9,000")
        st.input(.odometer, "9600")
        #expect(st.odoHint.warn)
        st.setOccurredAt(LocalDateTime("2026-10-26T08:00")!)
        st.setFlag(.tripMode, true); st.input(.odometer, "50")
        #expect(st.collect().odometerKm == 10050)
    }

    @Test func userValuesAreNeverOverwrittenAndClearingAllowsAuto() {
        var st = RecordFormState(vehicle: phev(), kind: .fuel, prefill: prefill(), now: now)
        st.setFlag(.fuelIsFull, false)
        st.input(.fuelLiters, "20"); st.input(.fuelUnitPrice, "7.5")
        #expect(st.text(.amount) == "150" && st.state(.amount).isAuto)
        st.input(.amount, "140")
        #expect(st.text(.amount) == "140" && !st.state(.amount).isAuto)
        st.input(.fuelUnitPrice, "8")
        #expect(st.text(.amount) == "140")
        st.input(.amount, "")
        #expect(st.text(.amount) == "160" && st.state(.amount).isAuto)
    }

    /// 充电单价只由金额和电量算出：不预填、不能手改，也不反推电量。
    @Test func chargeUnitPriceIsDerivedOnly() {
        let pub = Place(id: 13, name: "云快充", lastUnitPrice: 1.5)
        var st = RecordFormState(vehicle: phev(), kind: .charge, prefill: Prefill(k: 0.2, lastOdo: 10000, places: [pub]), now: now)
        st.selectPlace(pub)
        st.input(.socBefore, "20"); st.input(.socAfter, "80")
        #expect(st.text(.chargeUnitPrice).isEmpty && st.text(.chargeKwh).isEmpty)
        st.input(.amount, "30")
        #expect(st.text(.chargeKwh).isEmpty && st.text(.chargeUnitPrice).isEmpty)
        st.input(.chargeKwh, "40")
        #expect(st.text(.chargeUnitPrice) == "0.75")
        st.input(.chargeKwh, "50")
        st.input(.chargeUnitPrice, "9")
        #expect(st.text(.chargeUnitPrice) == "0.6" && st.collect(now: now).chargeUnitPrice == 0.6)
    }

    @Test func moneyIsDecimalNotFloat() {
        var st = RecordFormState(vehicle: phev(), kind: .fuel, prefill: prefill(), now: now)
        st.setFlag(.fuelIsFull, false)
        st.input(.fuelLiters, "2.675"); st.input(.fuelUnitPrice, "1")
        #expect(st.text(.amount) == "2.68")
        st.input(.amount, "0.1+0.2")
        #expect(st.collect(now: now).amountCents == 30)
    }

    @Test func finishChargeFillsDuration() {
        var rec = Record.sample(kind: "charge", at: "2026-10-27T10:00")
        rec.status = "in_progress"
        let st = RecordFormState(vehicle: phev(), record: rec, prefill: prefill(), finish: true, now: now)
        #expect(st.text(.chargeMinutes) == "120")
    }

    @Test func startOnlyChargeSendsMinimalFields() {
        var st = RecordFormState(vehicle: phev(), kind: .charge, prefill: prefill(), now: now)
        st.input(.odometer, "10100"); st.input(.socBefore, "20"); st.input(.chargeKwh, "10"); st.input(.chargeUnitPrice, "1")
        let p = st.collect(startOnly: true, clientId: "c1", now: now)
        #expect(p.status == "in_progress" && p.chargeKwh == nil && p.amountCents == nil && p.socAfterPct == nil)
        #expect(p.socBeforePct == 20 && p.clientId == "c1")
    }

    @Test func clientIdOnlyOnCreate() {
        let st = RecordFormState(vehicle: phev(), kind: .fuel, prefill: prefill(), now: now)
        #expect(st.collect(clientId: "abc", now: now).clientId == "abc" && st.collect(clientId: "abc", now: now).version == nil)
        let st2 = RecordFormState(vehicle: phev(), record: Record.sample(kind: "fuel", at: "2026-10-25T08:00"), prefill: prefill(), now: now)
        let p2 = st2.collect(clientId: "ignored", now: now)
        #expect(p2.clientId == nil && p2.version == 4)
    }

    @Test func draftRoundTrip() throws {
        var st = RecordFormState(vehicle: phev(), kind: .fuel, prefill: prefill(), now: now)
        st.input(.fuelLiters, "20"); st.input(.odometer, "10350"); st.selectChip(.grade, "95"); st.note = "备注"
        let d = st.draft()
        #expect(d.isFresh && d.hasContent)
        let data = try JSONEncoder().encode(d)
        var fresh = RecordFormState(vehicle: phev(), kind: .fuel, prefill: prefill(), now: now)
        fresh.restore(try JSONDecoder().decode(FormDraft.self, from: data))
        #expect(fresh.text(.fuelLiters) == "20" && fresh.text(.odometer) == "10350" && fresh.fuelGrade == "95" && fresh.note == "备注")
        #expect(fresh.state(.fuelLiters).isUser)
    }

    @Test func payloadWritesExplicitNulls() throws {
        let st = RecordFormState(vehicle: phev(), kind: .snapshot, prefill: prefill(), now: now)
        let data = try JSONCoding.encoder.encode(st.collect(now: now))
        let o = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(o["odometer_km"] is NSNull && o["place_id"] is NSNull && o["snapshot_tag"] as? String == "other")
        #expect(o["occurred_at"] as? String == "2026-10-27T12:00")
    }

    @Test func tariffAcrossMidnightAndMultiDay() {
        let place = Place(id: 1, name: "家", touTariff: [TariffItem(from: "22:00", to: "08:00", price: Decimal(string: "0.3")!),
                                                          TariffItem(from: "08:00", to: "22:00", price: Decimal(string: "0.62")!)])
        let start = LocalDateTime("2026-10-27T21:00")!
        // 21:00–22:00 按 0.62，22:00–23:00 按 0.3，各 60 分钟
        let amt = RecordFormState.tariffAmount(place: place, kwh: 10, start: start, minutes: 120)
        #expect(amt?.rounded(scale: 4) == Decimal(string: "4.6"))
        // 超过 3 天只算 3 天
        let long = RecordFormState.tariffAmount(place: place, kwh: 10, start: start, minutes: 10_000)
        let capped = RecordFormState.tariffAmount(place: place, kwh: 10, start: start, minutes: 3 * 24 * 60)
        #expect(long == capped)
        #expect(RecordFormState.tariffAmount(place: Place(id: 2, name: "无"), kwh: 10, start: start, minutes: 60) == nil)
    }

    @Test func nearestPlaceWithinThreeHundredMeters() {
        let a = Place(id: 1, name: "近", lat: 39.9042, lng: 116.4074)
        let b = Place(id: 2, name: "远", lat: 39.95, lng: 116.5)
        #expect(Geo.nearest(lat: 39.9043, lng: 116.4075, in: [b, a])?.place.id == 1)
        #expect(Geo.nearest(lat: 40.5, lng: 117, in: [a, b]) == nil)
        #expect(Geo.nearest(lat: 39.9, lng: 116.4, in: [Place(id: 3, name: "无坐标")]) == nil)
    }

}

extension Record {
    static func sample(kind: String, at: String) -> Record {
        let json = #"{"id":1,"vehicle_id":1,"kind":"\#(kind)","occurred_at":"\#(at)","version":4,"source":"manual","charge_type":"home","estimated_fields":[]}"#
        return try! JSONCoding.decoder.decode(Record.self, from: Data(json.utf8))
    }
}

@Suite struct ChargeLimitTests {
    @Test func chargeToLimitLocksEndSocAtLimit() {
        var st = RecordFormState(vehicle: phevForLimit(), kind: .charge, prefill: Prefill(k: 0.2, lastOdo: 10000), now: LocalDateTime("2026-10-27T12:00")!)
        st.input(.socBefore, "20"); st.input(.socAfter, "60")
        st.setFlag(.chargeToLimit, true)
        #expect(st.text(.socAfter) == "100" && st.socAfterLocked && st.state(.socAfter).isAuto)
        st.input(.socAfter, "50"); st.setLevel(.socAfter, 30)
        #expect(st.text(.socAfter) == "100")
        #expect(st.collect(now: LocalDateTime("2026-10-27T12:00")!).socAfterPct == 100)
        st.setFlag(.chargeToLimit, false)
        #expect(st.text(.socAfter).isEmpty && !st.socAfterLocked)
    }

    @Test func costIsAmountOnly() throws {
        var st = RecordFormState(vehicle: phevForLimit(), kind: .fuel, prefill: Prefill(lastOdo: 100), now: LocalDateTime("2026-10-27T12:00")!)
        st.input(.odometer, "150"); st.input(.fuelLiters, "20"); st.input(.fuelUnitPrice, "7.5")
        let data = try JSONCoding.encoder.encode(st.collect(now: LocalDateTime("2026-10-27T12:00")!))
        let o = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(o["amount_cents"] as? Int == 15000 && o["paid_cents"] == nil && o["payer_user_id"] == nil)
    }
}

private func phevForLimit() -> Vehicle {
    Vehicle(id: 1, name: "t", energyType: "phev", hasFuel: true, hasElec: true, tankCapacityL: 48, batteryUsableKwh: 18.3)
}
