import Foundation
import Network
import Observation
import SwiftUI
import VoltaneKit

enum AppPhase: Equatable { case launching, needsLogin, ready }

/// 底部弹出的页面：记录表单、费用表单、详情。
enum ActiveSheet: Identifiable {
    case record(kind: RecordKind, vehicleId: Int)
    case editRecord(Record, finish: Bool)
    case expense(vehicleId: Int)
    case editExpense(Expense)
    case recordDetail(id: Int, isExpense: Bool)
    case outbox(vehicleId: Int)
    case pendingEdit(OutboxItem)
    case addMenu

    var isMenu: Bool { if case .addMenu = self { true } else { false } }

    var id: String {
        switch self {
        case .record(let k, let v): "record-\(k.rawValue)-\(v)"
        case .editRecord(let r, let f): "edit-\(r.id)-\(f)"
        case .expense(let v): "expense-\(v)"
        case .editExpense(let e): "edit-expense-\(e.id)"
        case .recordDetail(let id, let e): "detail-\(id)-\(e)"
        case .outbox(let v): "outbox-\(v)"
        case .pendingEdit(let i): "pending-\(i.id)"
        case .addMenu: "add-menu"
        }
    }
}

struct ReminderCompletion: Identifiable {
    let id = UUID()
    let reminder: ExpenseSaveResult.SuggestedReminder
    let doneAt: LocalDateTime
    let odometer: Double?
}

enum AppTab: Hashable { case home, records, add, stats, me }

@MainActor @Observable
final class AppModel {
    let settings = AppSettings()
    let tokens: TokenStore
    let client: APIClient
    let repository: Repository
    let cache: ResponseCache
    let outbox: Outbox
    let toasts = ToastCenter()

    private(set) var phase: AppPhase = .launching
    private(set) var server: ServerConfig?
    private(set) var user: User?
    private(set) var vehicles: [Vehicle] = []
    private(set) var currentVehicleId: Int?
    private(set) var dueCount = 0
    private(set) var outboxCount = 0
    private(set) var isOnline = true
    /// 记录、费用增删改后加 1，各页面用 `.task(id:)` 重新加载。
    private(set) var dataVersion = 0
    var tab: AppTab = .home
    /// 保存保险以外的费用后，服务端建议顺手完成的提醒，等用户确认。
    var pendingReminderCompletions: [ReminderCompletion] = []
    var sheet: ActiveSheet?
    var themeName: String { didSet { settings.theme = themeName } }

    private let monitor = NWPathMonitor()
    private var flushing = false

    init(tokens: TokenStore = KeychainTokenStore(), transport: Transport = URLSessionTransport(), baseDirectory: URL? = nil) {
        let base = baseDirectory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Voltane", isDirectory: true)
        self.tokens = tokens
        let saved = settings.server
        server = saved
        let placeholder = saved ?? ServerConfig(primary: URL(string: "http://localhost")!)
        client = APIClient(server: placeholder, tokens: tokens, transport: transport)
        cache = ResponseCache(directory: base.appendingPathComponent("ApiCache", isDirectory: true))
        outbox = Outbox(directory: base.appendingPathComponent("Outbox", isDirectory: true))
        repository = Repository(client: client, cache: cache)
        themeName = settings.theme
        startMonitoring()
    }

    var colorScheme: ColorScheme? {
        switch themeName { case "light": .light; case "dark": .dark; default: nil }
    }

    var currentVehicle: Vehicle? { vehicles.first { $0.id == currentVehicleId } }
    var canRecord: Bool { currentVehicle?.canEdit == true }

    // MARK: 启动与登录

    func bootstrap() async {
        guard phase == .launching else { return }
        await client.setHandlers(onUnauthorized: { [weak self] in Task { @MainActor in self?.sessionExpired() } },
                                 onServerChange: { [weak self] cfg in Task { @MainActor in self?.serverChanged(cfg) } })
        #if DEBUG
        // 开发调试：启动参数 -voltane.autologin "用户名:密码@服务器地址" 直接登录，只在 Debug 构建里存在
        if tokens.load() == nil, let spec = UserDefaults.standard.string(forKey: "voltane.autologin"), let at = spec.lastIndex(of: "@"),
           let url = ServerConfig.normalize(String(spec[spec.index(after: at)...])) {
            let cred = spec[..<at].split(separator: ":", maxSplits: 1).map(String.init)
            if cred.count == 2 {
                do { try await login(config: ServerConfig(primary: url), username: cred[0], password: cred[1]); return } catch {}
            }
        }
        #endif
        guard let server, tokens.load() != nil else { phase = .needsLogin; return }
        await client.setServer(server)
        if let uid = settings.lastUserId { await cache.setScope(server: server.primary, userId: uid) }
        await client.refreshIfNeeded()
        do {
            await enter(try await repository.fetch(API.me()).value)
        } catch let e as APIError where e.isNetwork {
            // 离线启动：用缓存里的用户资料先进入，网络恢复后自然刷新
            if let cached = await repository.cached(API.me()) { await enter(cached.value, offline: true) } else { phase = .needsLogin }
        } catch {
            phase = .needsLogin
        }
    }

    private func enter(_ me: User, offline: Bool = false) async {
        user = me
        settings.lastUserId = me.id
        if let server { await cache.setScope(server: server.primary, userId: me.id); await outbox.setScope(server: server.primary, userId: me.id) }
        if let cached = await repository.cached(API.vehicles()) { vehicles = cached.value }
        if !offline { await loadVehicles() }
        pickVehicle()
        phase = .ready
        await refreshOutboxCount()
        if !offline { await refreshDueCount(); await flushOutbox() }
    }

    func checkServer(_ text: String) async throws -> (URL, Health) {
        guard let url = ServerConfig.normalize(text) else { throw APIError.network("服务器地址不正确") }
        let probe = APIClient(server: ServerConfig(primary: url), tokens: MemoryTokenStore())
        let health = try await probe.send(API.health())
        return (url, health)
    }

    func login(config: ServerConfig, username: String, password: String) async throws {
        await client.setServer(config)
        let resp = try await client.send(try API.login(username: username, password: password))
        guard let token = resp.token, let exp = resp.expiresAt else { throw APIError(status: -1, detail: .text("服务端没有返回令牌，请确认服务端已升级")) }
        try tokens.save(StoredToken(token: token, expiresAt: exp.date))
        server = config
        settings.server = config
        settings.lastUsername = username
        await enter(resp.user)
    }

    func signup(config: ServerConfig, code: String, username: String, password: String, displayName: String) async throws {
        await client.setServer(config)
        let resp = try await client.send(try API.signup(.init(code: code, username: username, password: password, displayName: displayName)))
        guard let token = resp.token, let exp = resp.expiresAt else { throw APIError(status: -1, detail: .text("服务端没有返回令牌，请确认服务端已升级")) }
        try tokens.save(StoredToken(token: token, expiresAt: exp.date))
        server = config
        settings.server = config
        await enter(resp.user)
    }

    /// 退出所有设备：服务端确认后才退出本机；失败时提示，本机保持登录以便重试。
    func logoutAllDevices() async {
        do {
            _ = try await client.send(API.logoutAll())
        } catch {
            toasts.show("没能退出其他设备，本机仍保持登录", sub: (error as? APIError)?.message ?? error.localizedDescription, isError: true)
            return
        }
        await logout()
    }

    /// 退出登录：清掉令牌、接口缓存和当前车辆，保留服务器地址、发件箱和草稿。
    func logout() async {
        tokens.clear()
        await cache.clear()
        user = nil; vehicles = []; currentVehicleId = nil; dueCount = 0
        sheet = nil; tab = .home
        phase = .needsLogin
    }

    private func sessionExpired() {
        guard phase == .ready else { return }
        user = nil; vehicles = []; currentVehicleId = nil
        Task { await cache.clear() }
        phase = .needsLogin
    }

    private func serverChanged(_ cfg: ServerConfig) {
        server = cfg
        settings.server = cfg
    }

    func updateServer(_ cfg: ServerConfig) async {
        server = cfg
        settings.server = cfg
        await client.setServer(cfg)
    }

    // MARK: 数据

    func loadVehicles() async {
        if let r = try? await repository.fetch(API.vehicles()) { vehicles = r.value; pickVehicle() }
    }

    private func pickVehicle() {
        let scope = "\(user?.id ?? 0)"
        let saved = settings.vehicleId(scope: scope) ?? user?.settings["default_vehicle_id"]?.intValue
        if vehicles.contains(where: { $0.id == currentVehicleId }) { return }
        let active = vehicles.filter { !$0.isArchived }
        currentVehicleId = vehicles.contains(where: { $0.id == saved }) ? saved : (active.first?.id ?? vehicles.first?.id)
    }

    func selectVehicle(_ id: Int) {
        guard currentVehicleId != id else { return }
        currentVehicleId = id
        settings.setVehicleId(id, scope: "\(user?.id ?? 0)")
        Task { await savePref("default_vehicle_id", .int(id)) }
        bump()
    }

    func bump() { dataVersion += 1 }

    func savePref(_ key: String, _ value: JSONValue) async {
        guard var u = user else { return }
        u.settings[key] = value
        user = u
        _ = try? await client.send(API.putSettings([key: value]))
    }

    func refreshDueCount() async {
        if let r = try? await repository.fetch(API.dueReminders()) { dueCount = r.value.count }
    }

    // MARK: 发件箱

    func refreshOutboxCount() async { outboxCount = await outbox.count }

    func flushOutbox() async {
        guard phase == .ready, !flushing else { return }
        flushing = true
        defer { flushing = false }
        let client = self.client
        let report = await outbox.flush { item in
            switch item.kind {
            case .record: _ = try await client.sendRaw(Endpoint<SaveResult>(.post, item.path, body: item.body))
            case .expense: _ = try await client.sendRaw(Endpoint<ExpenseSaveResult>(.post, item.path, body: item.body))
            }
        }
        outboxCount = report.remaining
        for msg in report.dropped { toasts.show(msg, isError: true) }
        if report.sent > 0 {
            toasts.show("已同步 \(report.sent) 条离线记录")
            bump()
        }
    }

    private func startMonitoring() {
        monitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor in
                guard let self else { return }
                let was = self.isOnline
                self.isOnline = path.status == .satisfied
                if !was && self.isOnline { await self.flushOutbox() }
            }
        }
        monitor.start(queue: DispatchQueue(label: "voltane.path"))
    }

    func sceneBecameActive() async {
        guard phase == .ready else { return }
        await client.refreshIfNeeded()
        await flushOutbox()
        await refreshDueCount()
    }
}

extension AppSettings {
    var lastUserId: Int? {
        get { UserDefaults.standard.object(forKey: "last-user-id") as? Int }
        nonmutating set { UserDefaults.standard.set(newValue, forKey: "last-user-id") }
    }
}
