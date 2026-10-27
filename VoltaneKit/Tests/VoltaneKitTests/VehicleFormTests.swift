import Foundation
import Testing
@testable import VoltaneKit

private func fixture<T: Decodable>(_ name: String, as type: T.Type = T.self) throws -> T {
    try JSONCoding.decoder.decode(T.self, from: try TestResources.data("Fixtures/\(name).json"))
}

private func json(_ p: some Encodable) throws -> [String: Any] {
    let data = try JSONCoding.encoder.encode(p)
    return try JSONSerialization.jsonObject(with: data) as! [String: Any]
}

private func wizard() -> VehicleWizardState {
    var w = VehicleWizardState()
    w.name = "gltest_秦"
    w.currentOdo = "12000"
    return w
}

@Suite struct InvitePayloadTests {
    @Test func longTermInviteSendsExplicitNulls() throws {
        let o = try json(InviteBody(role: "viewer", days: nil, maxUses: nil, allowSignup: false))
        #expect(o["days"] is NSNull && o["max_uses"] is NSNull)
        #expect(o["role"] as? String == "viewer" && o["allow_signup"] as? Bool == false)
        let seven = try json(InviteBody())
        #expect(seven["days"] as? Int == 7 && seven["max_uses"] as? Int == 1)
    }

    @Test func metaTextShowsLongTermAndUnlimited() throws {
        let list: [Invite] = try fixture("vehicles_vid_invites__phev")
        let long = try #require(list.first { $0.expiresAt == nil })
        #expect(long.metaText == "共同记录 · 长期有效 · 不限次数 · 已加入 0 人")
        let limited = try #require(list.first { $0.maxUses == 3 })
        #expect(limited.metaText == "只看 · \(Fmt.date(limited.expiresAt!.local())) 过期 · 已用 0/3")
    }

    @Test func shareTextMatchesWeb() {
        let t = InviteShare.text(code: "Q6RS287G", server: URL(string: "http://localhost:8136/"))
        #expect(t == "邀请你一起记录用车数据，打开 http://localhost:8136/join/Q6RS287G 或在「我的 → 加入车辆」输入邀请码 Q6RS287G")
    }
}

@Suite struct HealthDecodingTests {
    @Test func issueExtrasDecode() throws {
        let text = """
        {"coverage":{"elec":null,"fuel":0.5},"issues":[
         {"key":"delivery_odo","level":"warn","text":"x","action":"fix_delivery","odometer_km":12.0,"delivery_date":"2026-01-02"},
         {"key":"stale:7","level":"warn","text":"y","action":"finish_charge","record_id":7},
         {"key":"missed:1:2","level":"warn","text":"z","action":"fix_missed","after_id":1,"before_id":2,"kind":"fuel"}],
         "k":null,"k_source":"default","latest_odo":null,"ledger_km":0}
        """
        let h = try JSONCoding.decoder.decode(VehicleHealth.self, from: Data(text.utf8))
        #expect(h.issues[0].odometerKm == 12 && h.issues[0].deliveryDate?.dateOnly == "2026-01-02")
        #expect(h.issues[1].recordId == 7 && h.issues[2].afterId == 1 && h.issues[2].kind == "fuel")
        #expect(h.coverage?.elec == nil && Fmt.km(h.latestOdo) == "–")
    }

    @Test func summaryDiffDecodes() throws {
        let list: [PeriodSummary] = try fixture("summaries__phev")
        #expect(list[0].diff?.recordedFuelL == 0 && list[0].diff?.warnings?.isEmpty == true)
    }
}

@Suite struct VehicleParamsTests {
    @Test func editRoundTripKeepsFields() throws {
        let v: Vehicle = try fixture("vehicles_vid__phev")
        let d = VehicleParamsDraft(vehicle: v)
        #expect(d.deliveryOdo == "12" && d.deliveryDate?.dateOnly == "2025-12-31")
        #expect(d.validate() == nil && d.deliveryChange(for: v) == nil)
        let o = try json(d.payload(for: v))
        #expect(o["name"] as? String == v.name && o["tank_capacity_l"] as? Double == 48)
        #expect(o["delivery_date"] as? String == "2025-12-31" && o["initial_odometer_km"] as? Double == 12)
        #expect((o["calc_settings"] as? [String: Any])?["min_segment_km"] as? Double == 30)
    }

    @Test func deliveryNeedsBothOrNeither() throws {
        let v: Vehicle = try fixture("vehicles_vid__sparse")
        var d = VehicleParamsDraft(vehicle: v)
        d.deliveryDate = nil; d.deliveryOdo = "30"
        #expect(d.validate() == "提车日期和提车里程要一起填，不填就都留空")
        d.deliveryDate = LocalDateTime("2026-01-05"); d.deliveryOdo = ""
        #expect(d.validate() != nil)
        d.deliveryOdo = "30"
        #expect(d.validate() == nil && d.deliveryChange(for: v)?.odometerKm == 30)
    }
}

@Suite struct VehicleWizardTests {
    @Test func onlyNameAndCurrentOdoRequired() {
        var w = VehicleWizardState()
        #expect(w.validate(step: 1) == "请填写车名")
        w.name = "x"
        #expect(w.validate(step: 1) == nil && w.validate(step: 2) == nil)
        #expect(w.validate(step: 3) == "请填写当前里程")
        w.currentOdo = "100"
        #expect(w.validate(step: 3) == nil && w.validate(step: 4) == nil)
        w.mode = .skip; w.currentOdo = ""
        #expect(w.validate(step: 3) == nil)
    }

    @Test func deliveryRecordOnlyWhenBothFilled() throws {
        var w = wizard()
        w.deliveryOdo = "20"
        var o = try json(w.payload())
        #expect((o["start"] as! [String: Any])["delivery_odo"] is NSNull)
        #expect(o["delivery_date"] is NSNull)
        w.deliveryDate = LocalDateTime("2026-01-02")
        o = try json(w.payload())
        let start = o["start"] as! [String: Any]
        #expect(start["delivery_odo"] as? Double == 20 && start["current_odo"] as? Double == 12000 && start["mode"] as? String == "existing")
        #expect(o["delivery_date"] as? String == "2026-01-02")
    }

    @Test func fillWithoutDeliveryIsRejected() {
        var w = wizard()
        w.deliveryFillL = "30"
        #expect(w.validate(step: 3) == "填「提车时加了多少油」需要同时填提车日期和提车里程")
        w.deliveryDate = LocalDateTime("2026-01-02"); w.deliveryOdo = "10"
        #expect(w.validate(step: 3) == nil)
        w.deliveryOdo = "99999"
        #expect(w.validate(step: 3) == "提车里程不能大于当前里程")
    }

    @Test func newModeIgnoresStaleDeliveryDate() throws {
        var w = wizard()
        w.deliveryDate = LocalDateTime("2026-01-02"); w.deliveryOdo = "10"
        w.mode = .new
        let o = try json(w.payload())
        #expect(o["delivery_date"] is NSNull && (o["start"] as! [String: Any])["delivery_odo"] is NSNull)
        w.mode = .skip
        #expect(try json(w.payload())["start"] is NSNull)
    }

    @Test func summaryNeedsStartDate() throws {
        var w = wizard()
        w.summaryElecKwh = "300"
        #expect(w.validate(step: 3) == "历史汇总需要填「从哪天开始算」")
        w.summaryStart = LocalDateTime("2026-01-01"); w.summaryElecYuan = "180.5"
        #expect(w.validate(step: 3) == nil)
        let s = try #require(try json(w.payload())["summary"] as? [String: Any])
        #expect(s["elec_kwh"] as? Double == 300 && s["elec_cents"] as? Int == 18050 && s["start_date"] as? String == "2026-01-01")
        #expect(s["fuel_cents"] is NSNull)
    }

    @Test func bevDropsFuelParams() throws {
        var w = wizard()
        w.energyType = "bev"; w.tank = "50"; w.battery = "60"; w.currentFuel = "40"
        let o = try json(w.payload())
        #expect(o["tank_capacity_l"] is NSNull && o["battery_usable_kwh"] as? Double == 60)
        #expect((o["start"] as! [String: Any])["current_fuel_pct"] is NSNull)
    }

    @Test func fuelGaugeConvertsToPercent() throws {
        var w = wizard()
        w.tank = "50"; w.setGaugeMode("liters"); w.currentFuel = "20"
        #expect((try json(w.payload())["start"] as! [String: Any])["current_fuel_pct"] as? Double == 40)
        w.setGaugeMode("pct")
        #expect(w.currentFuel == "40")
        w.gaugeBars = "8"; w.setGaugeMode("bars")
        #expect(w.currentFuel == "3")
        #expect((try json(w.payload())["fuel_gauge_bars"] as? Int) == 8)
        w.currentFuel = "99"
        #expect((try json(w.payload())["start"] as! [String: Any])["current_fuel_pct"] as? Double == 100)
    }

    @Test func remindersUseTemplateAsSuggestionOnly() throws {
        var w = wizard()
        let tpl = WizardReminderTemplate.all
        let m = tpl.first { $0.key == "maintenance" }!
        var r = w.reminder(m)
        #expect(r.months == "12" && r.km == "10000" && !r.on && r.dueDate == nil && r.dueOdo.isEmpty)
        w.energyType = "ice"; w.reminders = [:]
        #expect(w.reminder(m).km == "7500")
        r = w.reminder(m); r.on = true; w.reminders[m.key] = r
        #expect(w.validate(step: 4) == "「保养」请填下次到期的日期或里程，不需要就取消勾选")
        r.dueOdo = "20000"; w.reminders[m.key] = r
        #expect(w.validate(step: 4) == nil)
        let ins = tpl.first { $0.key == "insurance" }!
        var ri = w.reminder(ins); ri.on = true; ri.dueDate = LocalDateTime("2027-03-01"); ri.months = ""; w.reminders[ins.key] = ri
        let list = try #require(try json(w.payload())["reminders"] as? [[String: Any]])
        #expect(list.count == 2)
        let a = try #require(list.first { $0["template_key"] as? String == "maintenance" })
        #expect(a["due_odometer_km"] as? Double == 20000 && a["due_date"] is NSNull && a["interval_km"] as? Double == 7500)
        let b = try #require(list.first { $0["template_key"] as? String == "insurance" })
        #expect(b["due_date"] as? String == "2027-03-01" && b["interval_months"] is NSNull && b["due_odometer_km"] is NSNull)
    }

    @Test func oversizedIntegersAreDropped() throws {
        var w = wizard()
        w.gaugeMode = "bars"; w.gaugeBars = "1e30"
        #expect(try json(w.payload())["fuel_gauge_bars"] is NSNull)
        #expect(w.gaugeUnit.label == "%")
    }

    @Test func pristineIgnoresStep() {
        var w = VehicleWizardState()
        w.step = 3
        #expect(w.isPristine)
        w.plate = "京A"
        #expect(!w.isPristine)
    }

    @Test func untouchedRemindersAreNotSent() throws {
        var w = wizard()
        for t in WizardReminderTemplate.all { _ = w.reminder(t) }
        #expect((try json(w.payload())["reminders"] as? [Any])?.isEmpty == true)
    }
}

@Suite struct SummaryDraftTests {
    @Test func roundTripAndMoneyAsCents() throws {
        let s = try #require((try fixture("summaries__phev", as: [PeriodSummary].self)).first)
        let d = SummaryDraft(s)
        #expect(d.fuelYuan == "300" && d.elecKwh == "1250" && d.mode == "extra")
        let v: Vehicle = try fixture("vehicles_vid__phev")
        let o = try json(d.payload(vehicle: v, version: s.version))
        #expect(o["fuel_cents"] as? Int == 30000 && o["elec_cents"] as? Int == 45500 && o["start_date"] as? String == "2026-01-01")
        var bad = d; bad.endDate = LocalDateTime("2025-01-01")!
        #expect(bad.validate() == "结束日期早于开始日期")
    }
}

@Suite struct AgoTests {
    @Test func buckets() {
        let now = Date()
        #expect(UTCDateTime(date: now.addingTimeInterval(-10)).ago(now: now) == "刚刚")
        #expect(UTCDateTime(date: now.addingTimeInterval(-300)).ago(now: now) == "5 分钟前")
        #expect(UTCDateTime(date: now.addingTimeInterval(-7200)).ago(now: now) == "2 小时前")
        #expect(UTCDateTime(date: now.addingTimeInterval(-86400 * 3)).ago(now: now) == "3 天前")
    }
}
