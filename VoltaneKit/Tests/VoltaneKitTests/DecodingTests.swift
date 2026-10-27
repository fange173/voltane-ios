import Foundation
import Testing
@testable import VoltaneKit

struct Manifest: Decodable {
    struct Entry: Decodable, Sendable, CustomTestStringConvertible {
        let file: String
        let method: String
        let path: String
        let status: Int
        var testDescription: String { file }
    }
    let apiVersion: Int
    let files: [Entry]
}

let manifest: Manifest = {
    let data = try! TestResources.data("Fixtures/manifest.json")
    return try! JSONCoding.decoder.decode(Manifest.self, from: data)
}()

/// 每个接口样例都要有对应的强类型解码；样例没有对应类型时测试失败，提醒补模型。
func decodeFixture(_ entry: Manifest.Entry) throws {
    let data = try TestResources.data("Fixtures/\(entry.file)")
    let name = String(entry.file.split(separator: "_", omittingEmptySubsequences: false).joined(separator: "_").components(separatedBy: "__")[0])
    let dec = JSONCoding.decoder
    func ok<T: Decodable>(_ type: T.Type) throws { _ = try dec.decode(T.self, from: data) }

    if entry.file.hasSuffix(".csv") {
        #expect(!data.isEmpty)
        return
    }
    if entry.status >= 400 {
        let err = APIError.parse(status: entry.status, data: data)
        #expect(err.status == entry.status)
        #expect(!err.message.isEmpty)
        return
    }
    switch name {
    case "admin_system": try ok(AdminSystem.self)
    case "admin_users": try ok([AdminUser].self)
    case "auth_login": try ok(LoginResponse.self)
    case "auth_logout_all": try ok(OKResponse.self)
    case "auth_me": try ok(User.self)
    case "auth_refresh": try ok(TokenResponse.self)
    case "expenses_eid": try ok(Expense.self)
    case "export": try ok(JSONValue.self)
    case "health": try ok(Health.self)
    case "invites_code": try ok(InvitePreview.self)
    case "places": try ok([Place].self)
    case "records": try ok(TimelinePage.self)
    case "records_create": try ok(SaveResult.self)
    case "records_prefill": try ok(Prefill.self)
    case "records_rid": try ok(Record.self)
    case "reminders": try ok([Reminder].self)
    case "reminders_due": try ok(DueReminders.self)
    case "reminders_templates": try ok([ReminderTemplate].self)
    case "stats_calendar": try ok(StatsCalendar.self)
    case "stats_cost": try ok(StatsCost.self)
    case "stats_energy": try ok(StatsEnergy.self)
    case "stats_mileage": try ok(StatsMileage.self)
    case "stats_monthly-report": try ok(MonthlyReport.self)
    case "stats_overview": try ok(Overview.self)
    case "stats_segments": try ok([Segment].self)
    case "stats_yearly-report": try ok(YearlyReport.self)
    case "summaries": try ok([PeriodSummary].self)
    case "trash": try ok([JSONValue].self)
    case "vehicles": try ok([Vehicle].self)
    case "vehicles_vid": try ok(Vehicle.self)
    case "vehicles_vid_members": try ok([Member].self)
    case "vehicles_vid_invites": try ok([Invite].self)
    case "vehicles_vid_activity": try ok([Activity].self)
    case "vehicles_vid_calibration": try ok(Calibration.self)
    case "vehicles_vid_health": try ok(VehicleHealth.self)
    case "vehicles_vid_odometer": try ok(OdometerLatest.self)
    default: Issue.record("样例 \(entry.file) 没有对应的解码测试")
    }
}

@Suite struct DecodingTests {
    @Test func manifestVersion() { #expect(manifest.apiVersion == 1) }

    @Test(arguments: manifest.files) func decodes(entry: Manifest.Entry) throws {
        try decodeFixture(entry)
    }

    @Test func coversErrorShapes() throws {
        let statuses = Set(manifest.files.filter { $0.file.hasPrefix("error__") }.map(\.status))
        #expect(statuses.isSuperset(of: [400, 401, 403, 404, 409, 422, 429]))
        let dup = try TestResources.data("Fixtures/error__409_duplicate.json")
        let e = APIError.parse(status: 409, data: dup)
        #expect(e.code == "duplicate" && e.embeddedRecord?.kind == "fuel")
        let validation = APIError.parse(status: 422, data: try TestResources.data("Fixtures/error__422_bad_value.json"))
        if case .validation(let msgs) = validation.detail { #expect(!msgs.isEmpty) } else { Issue.record("422 应为校验数组") }
        let plain = APIError.parse(status: 401, data: try TestResources.data("Fixtures/error__401.json"))
        if case .text = plain.detail {} else { Issue.record("401 应为字符串") }
    }

    @Test func sparseVehicleHasNoNaN() throws {
        let data = try TestResources.data("Fixtures/stats_overview__sparse_month.json")
        let o = try JSONCoding.decoder.decode(Overview.self, from: data)
        #expect(o.latest.fuel?.per100 == nil && o.latest.fuel?.quality == "D")
        #expect(o.history?.mileage == 0)
        #expect(Fmt.num(o.latest.fuel?.per100) == "–")
    }

    @Test func systemAndBusinessTimesAreDifferentTypes() throws {
        let rec = try JSONCoding.decoder.decode(Record.self, from: try TestResources.data("Fixtures/records_rid__fuel.json"))
        #expect(rec.occurredAt.wire.count == 16)
        #expect(rec.createdAt != nil)
        let act = try JSONCoding.decoder.decode([Activity].self, from: try TestResources.data("Fixtures/vehicles_vid_activity__phev.json"))
        #expect(!act.isEmpty)
    }
}
