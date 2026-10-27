import Foundation

/// 全部接口的类型化入口。路径和参数与服务端 `app/routers/*.py` 一一对应。
public enum API {
    public static func health() -> Endpoint<Health> { Endpoint(.get, "/api/health", authenticated: false) }

    // MARK: 认证
    public struct LoginBody: Encodable, Sendable {
        public var username: String
        public var password: String
        public var client = "ios"
        public var remember = true
        public init(username: String, password: String) { self.username = username; self.password = password }
    }

    public static func login(username: String, password: String) throws -> Endpoint<LoginResponse> {
        try Endpoint(.post, "/api/auth/login", json: LoginBody(username: username, password: password), authenticated: false)
    }

    public struct SignupBody: Encodable, Sendable {
        public var code: String
        public var username: String
        public var password: String
        public var displayName: String
        public var client = "ios"
        public init(code: String, username: String, password: String, displayName: String) {
            self.code = code; self.username = username; self.password = password; self.displayName = displayName
        }
    }

    public static func signup(_ body: SignupBody) throws -> Endpoint<LoginResponse> {
        try Endpoint(.post, "/api/auth/signup", json: body, authenticated: false)
    }

    public static func refresh() -> Endpoint<TokenResponse> { Endpoint(.post, "/api/auth/refresh") }
    public static func logoutAll() -> Endpoint<OKResponse> { Endpoint(.post, "/api/auth/logout-all") }
    public static func me() -> Endpoint<User> { Endpoint(.get, "/api/auth/me") }

    public struct SettingsBody: Encodable, Sendable {
        public var values: [String: JSONValue]
        public func encode(to encoder: Encoder) throws {
            var c = encoder.singleValueContainer()
            try c.encode(values)
        }
    }

    public static func putSettings(_ values: [String: JSONValue]) -> Endpoint<[String: JSONValue]> {
        (try? Endpoint(.put, "/api/auth/settings", json: SettingsBody(values: values))) ?? Endpoint(.put, "/api/auth/settings")
    }

    // MARK: 车辆与概览
    public static func vehicles() -> Endpoint<[Vehicle]> { Endpoint(.get, "/api/vehicles") }
    public static func members(vehicleId: Int) -> Endpoint<[Member]> { Endpoint(.get, "/api/vehicles/\(vehicleId)/members") }
    public static func activity(vehicleId: Int, limit: Int = 15) -> Endpoint<[Activity]> {
        Endpoint(.get, "/api/vehicles/\(vehicleId)/activity", query: [URLQueryItem("limit", limit)])
    }
    public static func overview(vehicleId: Int, range: String = "month") -> Endpoint<Overview> {
        Endpoint(.get, "/api/stats/overview", query: [URLQueryItem("vehicle_id", vehicleId), URLQueryItem("range", range)])
    }
    public static func dueReminders() -> Endpoint<DueReminders> { Endpoint(.get, "/api/reminders/due") }

    // MARK: 邀请
    public static func previewInvite(code: String) -> Endpoint<InvitePreview> {
        Endpoint(.get, "/api/invites/\(Self.inviteCode(code))", authenticated: false)
    }
    public static func acceptInvite(code: String) -> Endpoint<AcceptInvite> { Endpoint(.post, "/api/invites/\(Self.inviteCode(code))/accept") }

    /// 只保留字母数字并转大写，避免路径注入。
    static func inviteCode(_ raw: String) -> String { String(raw.uppercased().filter { $0.isASCII && ($0.isLetter || $0.isNumber) }.prefix(16)) }

    // MARK: 记录
    public static func records(vehicleId: Int, kind: String? = nil, query: String? = nil, mine: Bool = false, anomaly: Bool = false,
                               before: LocalDateTime? = nil, limit: Int = 60) -> Endpoint<TimelinePage> {
        var q = [URLQueryItem("vehicle_id", vehicleId), URLQueryItem("limit", limit)]
        if let kind, !kind.isEmpty { q.append(URLQueryItem("kind", kind)) }
        if mine { q.append(URLQueryItem("mine", true)) }
        if anomaly { q.append(URLQueryItem("anomaly", true)) }
        if let query, !query.isEmpty { q.append(URLQueryItem("q", query)) }
        if let before { q.append(URLQueryItem("before", before.wire)) }
        return Endpoint(.get, "/api/records", query: q)
    }

    public static func record(id: Int) -> Endpoint<Record> { Endpoint(.get, "/api/records/\(id)") }
    public static func expense(id: Int) -> Endpoint<Expense> { Endpoint(.get, "/api/expenses/\(id)") }

    public static func prefill(vehicleId: Int, kind: String) -> Endpoint<Prefill> {
        Endpoint(.get, "/api/records/prefill", query: [URLQueryItem("vehicle_id", vehicleId), URLQueryItem("kind", kind)])
    }

    public static func createRecord(_ body: RecordPayload) throws -> Endpoint<SaveResult> {
        try Endpoint(.post, "/api/records", json: body)
    }

    public static func updateRecord(id: Int, _ body: RecordPayload) throws -> Endpoint<SaveResult> {
        try Endpoint(.put, "/api/records/\(id)", json: body)
    }

    public static func deleteRecord(id: Int) -> Endpoint<OKResponse> { Endpoint(.delete, "/api/records/\(id)") }
    public static func restoreRecord(id: Int) -> Endpoint<OKResponse> { Endpoint(.post, "/api/records/\(id)/restore") }

    public static func createExpense(_ body: ExpensePayload) throws -> Endpoint<ExpenseSaveResult> {
        try Endpoint(.post, "/api/expenses", json: body)
    }

    public static func updateExpense(id: Int, _ body: ExpensePayload) throws -> Endpoint<ExpenseSaveResult> {
        try Endpoint(.put, "/api/expenses/\(id)", json: body)
    }

    public static func deleteExpense(id: Int) -> Endpoint<OKResponse> { Endpoint(.delete, "/api/expenses/\(id)") }
    public static func restoreExpense(id: Int) -> Endpoint<OKResponse> { Endpoint(.post, "/api/expenses/\(id)/restore") }

    public struct SegmentMarkBody: Encodable, Sendable {
        public var vehicleId: Int
        public var endRecordId: Int
        public var energy: String
        public var tag: String
        public var excluded: Bool
        public init(vehicleId: Int, endRecordId: Int, energy: String, tag: String, excluded: Bool) {
            self.vehicleId = vehicleId; self.endRecordId = endRecordId; self.energy = energy; self.tag = tag; self.excluded = excluded
        }
    }

    public static func markSegment(_ body: SegmentMarkBody) throws -> Endpoint<OKResponse> {
        try Endpoint(.patch, "/api/segments", json: body)
    }

    public struct PlaceBody: Encodable, Sendable {
        public var vehicleId: Int
        public var shared = true
        public var name: String
        public var kind: String
        public var defaultChargeType: String?
        public var defaultFuelGrade: String?
        public var lastUnitPrice: Double?
        public init(vehicleId: Int, name: String, kind: String, defaultChargeType: String? = nil, defaultFuelGrade: String? = nil, lastUnitPrice: Double? = nil) {
            self.vehicleId = vehicleId; self.name = name; self.kind = kind; self.defaultChargeType = defaultChargeType
            self.defaultFuelGrade = defaultFuelGrade; self.lastUnitPrice = lastUnitPrice
        }
    }

    public static func createPlace(_ body: PlaceBody) throws -> Endpoint<Place> { try Endpoint(.post, "/api/places", json: body) }
    public static func places(vehicleId: Int) -> Endpoint<[Place]> {
        Endpoint(.get, "/api/places", query: [URLQueryItem("vehicle_id", vehicleId)])
    }

    public struct FixMissedBody: Encodable, Sendable {
        public var afterId: Int
        public var beforeId: Int
        public var kind: String
    }

    public struct FixMissedResult: Decodable, Sendable {
        public let recordId: Int?
        public let qty: Double?
        public let cents: Int?
    }

    public static func fixMissed(vehicleId: Int, afterId: Int, beforeId: Int, kind: String) throws -> Endpoint<FixMissedResult> {
        try Endpoint(.post, "/api/vehicles/\(vehicleId)/fix/missed", json: FixMissedBody(afterId: afterId, beforeId: beforeId, kind: kind))
    }

    public struct DismissBody: Encodable, Sendable { public var key: String }
    public static func dismissHint(vehicleId: Int, key: String) throws -> Endpoint<OKResponse> {
        try Endpoint(.post, "/api/vehicles/\(vehicleId)/hints/dismiss", json: DismissBody(key: key))
    }
}
