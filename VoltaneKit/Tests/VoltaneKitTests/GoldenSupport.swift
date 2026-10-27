import Foundation
@testable import VoltaneKit

/// 网页版实际算出的表单样例（见 Golden/README.md），用来逐项比对 Swift 实现。
struct WebGolden: Decodable {
    struct Case: Decodable {
        let name: String
        let veh: String
        let kind: String
        let act: [[JSONValue]]
        let prefill: JSONValue?
        let record: JSONValue?
        let expected: Expected
    }

    struct Expected: Decodable {
        let f: [String: [String]]
        let lv: [String: String]?
        let chips: [String: String]?
        let sel: [String: Bool]?
        let lit: String?
        let odo: Odo?
        let odoPh: String?
        let paidPh: String?
        let disc: String?
        let tariff: String?
        let place: String?
        let err: String
        let body: [String: JSONValue]?

        struct Odo: Decodable { let t: String; let w: Bool }
    }

    struct UtilGolden: Decodable {
        let amount: [JSONValue]
        let num: [[JSONValue]]
        let km: [[JSONValue]]
        let money: [[JSONValue]]
        let gauge: [[JSONValue]]
        let pct: [[JSONValue]]
    }

    let vehicles: [String: JSONValue]
    let prefill: JSONValue
    let cases: [Case]
    let util: UtilGolden

    static func load() throws -> WebGolden {
        try JSONCoding.decoder.decode(WebGolden.self, from: try TestResources.data("Golden/web-form-cases.json"))
    }
}

extension JSONValue {
    func decoded<T: Decodable>(_ type: T.Type = T.self) throws -> T {
        try JSONCoding.decoder.decode(T.self, from: JSONEncoder().encode(self))
    }

    var number: Double? {
        switch self { case .int(let v): Double(v); case .double(let v): v; default: nil }
    }

    var isNull: Bool { if case .null = self { true } else { false } }
}

extension WebGolden {
    func vehicle(_ key: String) throws -> Vehicle {
        var base: [String: JSONValue] = [
            "id": .int(1), "name": .string("T"), "plate": .string(""), "energy_type": .string("phev"), "has_fuel": .bool(true),
            "has_elec": .bool(true), "tank_capacity_l": .double(48), "battery_usable_kwh": .double(18.3),
            "charge_limit_pct": .double(100), "default_fuel_grade": .string("92"), "default_charge_type": .string("home"),
            "fuel_gauge_mode": .string("pct"), "fuel_gauge_bars": .null, "factory_fuel_l": .double(5),
            "record_style": .string("detailed"), "role": .string("owner"), "is_archived": .bool(false),
        ]
        if case .object(let o) = vehicles[key] ?? .object([:]) { base.merge(o) { _, new in new } }
        return try JSONValue.object(base).decoded(Vehicle.self)
    }

    func prefill(for c: Case) throws -> Prefill {
        var base: [String: JSONValue] = [:]
        if case .object(let o) = prefill { base = o }
        if case .object(let o)? = c.prefill { base.merge(o) { _, new in new } }
        return try JSONValue.object(base).decoded(Prefill.self)
    }
}
