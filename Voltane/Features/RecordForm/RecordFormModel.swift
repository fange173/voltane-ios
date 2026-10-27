import CoreLocation
import Foundation
import Observation
import SwiftUI
import VoltaneKit

/// 记录表单的界面模型：加载预填、持有表单状态、保存流程（重复确认、冲突、离线、撤销、标记静置、草稿）。
@MainActor @Observable
final class RecordFormModel {
    enum Mode {
        case create(kind: RecordKind, vehicleId: Int)
        case edit(Record, finish: Bool)
        case pending(OutboxItem)
    }

    let app: AppModel
    let mode: Mode
    let vehicle: Vehicle
    private(set) var state: RecordFormState
    private(set) var loaded = false
    private var loading = false
    var error: String?
    var saving = false
    var duplicateMessage: String?
    var finished = false
    var showMore = false
    var placePicker = false
    /// 同一张表单每次提交共用的 client_id，离线重发和重复确认都复用它。
    private var clientId = UUID().uuidString
    private var pendingId: UUID?
    private var draftTask: Task<Void, Never>?
    private let location = LocationFinder()

    var isEdit: Bool { if case .edit = mode { true } else { false } }
    var isFinish: Bool { if case .edit(_, let f) = mode { f } else { false } }
    var isPending: Bool { if case .pending = mode { true } else { false } }
    var kind: RecordKind { state.kind }

    var title: String {
        let name: [RecordKind: String] = [.fuel: "加油", .charge: "充电", .snapshot: "状态快照"]
        if isFinish { return "结束充电" }
        if isPending { return "待同步的" + (name[kind] ?? "") }
        return (isEdit ? "编辑" : "") + (name[kind] ?? "")
    }

    init(app: AppModel, mode: Mode) {
        self.app = app
        self.mode = mode
        var vid = 0
        var record: Record?
        var kind: RecordKind = .fuel
        var finish = false
        var cid = UUID().uuidString
        var pid: UUID?
        switch mode {
        case .create(let k, let v): kind = k; vid = v
        case .edit(let r, let f): record = r; vid = r.vehicleId; finish = f
        case .pending(let item):
            vid = item.vehicleId
            pid = item.id
            record = Self.record(from: item)
            cid = Self.clientId(of: item) ?? cid
        }
        clientId = cid
        pendingId = pid
        let v = app.vehicles.first { $0.id == vid } ?? Vehicle(id: vid, name: "", energyType: "phev", hasFuel: true, hasElec: true)
        vehicle = v
        if let record {
            state = RecordFormState(vehicle: v, record: record, prefill: Prefill(), finish: finish)
        } else {
            let allowed: [RecordKind] = [v.hasFuel ? .fuel : nil, v.hasElec ? .charge : nil, .snapshot].compactMap { $0 }
            if !allowed.contains(kind) { kind = allowed[0] }
            state = RecordFormState(vehicle: v, kind: kind, prefill: Prefill())
        }
    }

    var availableKinds: [RecordKind] { [vehicle.hasFuel ? .fuel : nil, vehicle.hasElec ? .charge : nil, .snapshot].compactMap { $0 } }

    private static func record(from item: OutboxItem) -> Record? {
        guard var obj = (try? JSONSerialization.jsonObject(with: item.body)) as? [String: Any] else { return nil }
        obj["id"] = 0
        guard let data = try? JSONSerialization.data(withJSONObject: obj) else { return nil }
        return try? JSONCoding.decoder.decode(Record.self, from: data)
    }

    private static func clientId(of item: OutboxItem) -> String? {
        ((try? JSONSerialization.jsonObject(with: item.body)) as? [String: Any])?["client_id"] as? String
    }

    private var draftKey: String { "\(app.user?.id ?? 0):\(vehicle.id):\(kind.rawValue)" }

    // MARK: 加载

    func load() async {
        // .task 可能重复触发，等待网络期间要挡住第二次加载，否则草稿提示会弹两次
        guard !loaded, !loading else { return }
        loading = true
        defer { loading = false }
        let ep = API.prefill(vehicleId: vehicle.id, kind: kind.rawValue)
        var prefill = Prefill()
        if let c = await app.repository.cached(ep) { prefill = c.value }
        if let r = try? await app.repository.fetch(ep) { prefill = r.value }
        rebuild(prefill: prefill)
        loaded = true
        if case .create = mode { await autoPickPlace() }
    }

    private func rebuild(prefill: Prefill, keep: (odometer: String?, note: String?, time: LocalDateTime?)? = nil) {
        defer { if let u = app.user?.settings["fuel_unit"]?.stringValue { state.setFuelUnit(u) } }
        switch mode {
        case .edit(let r, let finish):
            state = RecordFormState(vehicle: vehicle, record: r, prefill: prefill, finish: finish)
        case .pending(let item):
            if let r = Self.record(from: item) { state = RecordFormState(vehicle: vehicle, record: r, prefill: prefill) }
        case .create:
            state = RecordFormState(vehicle: vehicle, kind: state.kind, prefill: prefill)
            let top = app.user?.settings["place_default"]?.stringValue == "top"
            state.carryOver(odometer: keep?.odometer, note: keep?.note, placeDefaultTop: top)
            if let t = keep?.time { state.setOccurredAt(t) }
            if keep == nil, let d = app.settings.draft(key: draftKey) {
                state.restore(d)
                app.toasts.show("已恢复上次没保存的内容", actions: [ToastAction(label: "清空") { [weak self] in self?.discardDraft() }])
            }
        }
    }

    /// 切换加油 / 充电 / 快照：保留已填的时间、里程和备注。
    func switchKind(_ k: RecordKind) async {
        guard k != state.kind, case .create = mode else { return }
        let keep = (odometer: state.text(.odometer).isEmpty ? nil : state.text(.odometer), note: state.note.isEmpty ? nil : state.note, time: Optional(state.occurredAt))
        state = RecordFormState(vehicle: vehicle, kind: k, prefill: Prefill())
        loaded = false
        let ep = API.prefill(vehicleId: vehicle.id, kind: k.rawValue)
        var prefill = Prefill()
        if let c = await app.repository.cached(ep) { prefill = c.value }
        if let r = try? await app.repository.fetch(ep) { prefill = r.value }
        state = RecordFormState(vehicle: vehicle, kind: k, prefill: prefill)
        rebuild(prefill: prefill, keep: keep)
        loaded = true
        await autoPickPlace()
    }

    private func discardDraft() {
        app.settings.saveDraft(nil, key: draftKey)
        rebuild(prefill: state.prefill, keep: (nil, nil, nil))
    }

    // MARK: 用户操作（每次都存草稿）

    func input(_ f: FormField, _ text: String) { state.input(f, text); touch() }
    func setFlag(_ f: FormFlag, _ on: Bool) { state.setFlag(f, on); touch() }
    func chip(_ c: FormChip, _ value: String) { state.selectChip(c, value); touch() }
    func setTime(_ t: LocalDateTime) { state.setOccurredAt(t); touch() }
    func setNote(_ n: String) { state.note = n; touch() }
    func setLevel(_ f: FormField, _ v: Double) { state.setLevel(f, v); touch() }
    func clearLevel(_ f: FormField) { state.clearLevel(f); touch() }
    func tapBar(_ f: FormField, _ k: Int) { state.tapBar(f, bar: k); touch() }
    func setLiters(_ f: FormField, _ t: String) { state.setLiters(f, t); touch() }
    func setFuelUnit(_ u: String) {
        state.setFuelUnit(u)
        Task { await app.savePref("fuel_unit", .string(u)) }
    }
    func selectPlace(_ p: Place?) { state.selectPlace(p); touch() }
    func copyLast() { state.copyLast(); touch(); app.toasts.show("已复制上次的地点、方式和单价") }

    private func touch() {
        guard case .create = mode else { return }
        draftTask?.cancel()
        draftTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled, let self else { return }
            self.app.settings.saveDraft(self.state.draft(), key: self.draftKey)
        }
    }

    /// 把当前临时地点直接存为常用地点并选中。
    func saveCurrentPlace() async {
        guard let cur = state.place, cur.id == nil else { return }
        let kind = state.kind == .fuel ? "gas_station" : (state.chargeType == "home" ? "home_charger" : "charge_station")
        let price = JSNumber.parse(state.text(state.kind == .fuel ? .fuelUnitPrice : .chargeUnitPrice))
        let body = API.PlaceBody(vehicleId: vehicle.id, name: cur.name, kind: kind,
                                 defaultChargeType: state.kind == .charge ? state.chargeType : nil,
                                 defaultFuelGrade: state.kind == .fuel ? state.fuelGrade : nil, lastUnitPrice: price)
        do {
            let saved = try await app.client.send(try API.createPlace(body))
            state.prefill.places.insert(saved, at: 0)
            state.selectPlace(saved)
            touch()
            app.toasts.show("已存为常用地点")
        } catch { app.toasts.error(error) }
    }

    // MARK: 定位

    private func autoPickPlace() async {
        guard kind != .snapshot, state.place == nil else { return }
        guard let loc = await location.locate(askPermission: false) else { return }
        apply(loc, announce: false)
    }

    func locateNow() async {
        guard let loc = await location.locate(askPermission: true) else {
            app.toasts.show("定位失败，请在系统设置里允许「使用期间」定位", isError: true)
            return
        }
        apply(loc, announce: true)
    }

    private func apply(_ loc: CLLocation, announce: Bool) {
        state.coords = (loc.coordinate.latitude, loc.coordinate.longitude)
        if let hit = Geo.nearest(lat: loc.coordinate.latitude, lng: loc.coordinate.longitude, in: state.prefill.places) {
            state.selectPlace(hit.place)
            if announce { app.toasts.show("已定位到「\(hit.place.name)」") }
        } else if announce {
            app.toasts.show("附近 300 米内没有常用地点，已记下坐标")
        }
    }

    // MARK: 保存

    func save(again: Bool = false, startOnly: Bool = false, force: Bool = false) async {
        var payload = state.collect(startOnly: startOnly, clientId: clientId)
        if let err = state.validate(payload) { error = err; return }
        error = nil
        payload.force = force
        saving = true
        defer { saving = false }
        let editing: Int? = { if case .edit(let r, _) = mode { r.id } else { nil } }()
        do {
            let res: SaveResult
            if let id = editing { res = try await app.client.send(try API.updateRecord(id: id, payload)) }
            else { res = try await app.client.send(try API.createRecord(payload)) }
            if let pid = pendingId { await app.outbox.remove(pid); await app.refreshOutboxCount() }
            app.settings.saveDraft(nil, key: draftKey)
            suggestPlace(for: payload)
            afterSave(res, editing: editing != nil, startOnly: startOnly, finishedCharge: isFinish)
            app.bump()
            finished = true
            if again { await reopen() }
        } catch let e as APIError {
            if e.status == 409 && e.code == "duplicate" && editing == nil {
                duplicateMessage = e.message
            } else if e.status == 409 && e.code == "conflict" {
                app.toasts.show(e.message, isError: true)
                app.bump()
                finished = true
            } else if e.isNetwork && editing == nil {
                await queueOffline(payload)
            } else {
                error = e.message
            }
        } catch {
            self.error = error.localizedDescription
        }
    }

    func confirmDuplicate() async { duplicateMessage = nil; await save(force: true) }

    private func queueOffline(_ payload: RecordPayload) async {
        guard let body = try? JSONCoding.encoder.encode(payload) else { return }
        let label = ["fuel": "加油", "charge": "充电", "snapshot": "状态快照"][payload.kind] ?? "记录"
        if let pid = pendingId { await app.outbox.replace(pid, label: label, body: body) }
        else { await app.outbox.enqueue(kind: .record, vehicleId: vehicle.id, label: label, body: body) }
        await app.refreshOutboxCount()
        app.settings.saveDraft(nil, key: draftKey)
        app.toasts.show("网络不通，已离线保存", sub: "联网后会自动同步")
        finished = true
    }

    private func reopen() async {
        let k = state.kind
        finished = false
        state = RecordFormState(vehicle: vehicle, kind: k, prefill: Prefill())
        clientId = UUID().uuidString
        loaded = false
        await load()
    }

    private func suggestPlace(for p: RecordPayload) {
        guard p.placeId == nil, let name = p.placeName, !name.isEmpty else { return }
        let key = "\(vehicle.id):\(name)"
        let count = app.settings.bumpPlaceName(key)
        guard count == 2, !app.settings.placeSuggestionSkipped(key) else { return }
        let vid = vehicle.id
        let kind = p.kind == "fuel" ? "gas_station" : p.kind == "charge" ? (p.chargeType == "home" ? "home_charger" : "charge_station") : "other"
        let body = API.PlaceBody(vehicleId: vid, name: name, kind: kind, defaultChargeType: p.chargeType, defaultFuelGrade: p.fuelGrade,
                                 lastUnitPrice: p.fuelUnitPrice ?? p.chargeUnitPrice)
        let app = self.app
        Task {
            try? await Task.sleep(for: .seconds(3.5))
            app.toasts.show("要把「\(name)」存成常用地点吗？", actions: [
                ToastAction(label: "不再提示") { app.settings.skipPlaceSuggestion(key) },
                ToastAction(label: "保存") {
                    do { _ = try await app.client.send(try API.createPlace(body)); app.toasts.show("已存为常用地点") } catch { app.toasts.error(error) }
                },
            ])
        }
    }

    private func afterSave(_ res: SaveResult, editing: Bool, startOnly: Bool, finishedCharge: Bool) {
        let r = res.record
        for w in res.warnings ?? [] { app.toasts.show(w, isError: true) }
        if startOnly {
            app.toasts.show("已记下开始充电", sub: "拔枪后在首页「充电中」卡片里补结束")
            return
        }
        let segs = res.segments ?? []
        let seg = segs.first { $0.energy == "combined" } ?? segs.first { $0.energy == "fuel" } ?? segs.first { $0.energy == "elec" }
        var actions: [ToastAction] = []
        let app = self.app
        if !editing {
            actions.append(ToastAction(label: "撤销") {
                do { _ = try await app.client.send(API.deleteRecord(id: r.id)); app.bump(); app.toasts.show("已撤销") } catch { app.toasts.error(error) }
            })
        }
        if let elec = segs.first(where: { $0.energy == "elec" }), (elec.distance ?? 99) < 5 || elec.anomaly == "parked", let endId = r.id as Int? {
            actions.append(ToastAction(label: "标记静置") {
                do {
                    _ = try await app.client.send(try API.markSegment(.init(vehicleId: r.vehicleId, endRecordId: endId, energy: "elec", tag: "idle", excluded: false)))
                    app.bump(); app.toasts.show("已把这段标记为静置，不计入行驶能耗")
                } catch { app.toasts.error(error) }
            })
        }
        guard let seg else {
            let text = finishedCharge ? "充电已结束" : editing ? "已保存" : "已记录"
            let sub = finishedCharge && r.chargeKwh != nil ? "本次 \(Fmt.num(r.chargeKwh)) kWh · \(Fmt.money(r.amountCents))" : ""
            app.toasts.show(text, sub: sub, actions: actions)
            return
        }
        let text: String
        switch seg.energy {
        case "combined": text = "本段 \(Fmt.num(seg.per100)) L + \(Fmt.num(seg.elecPer100)) kWh / 100km"
        case "fuel": text = "本段油耗 \(Fmt.num(seg.per100)) L/100km"
        default: text = "本段电耗 \(Fmt.num(seg.per100)) kWh/100km"
        }
        var sub = "\(Fmt.km(seg.distance)) km"
        if let prev = seg.prevPer100, prev != 0, let cur = seg.per100 {
            let ch = (cur - prev) / prev
            sub += " · 比上段" + (abs(ch) < 0.005 ? "持平" : (ch > 0 ? " ↑" : " ↓") + JSNumber.toFixed(abs(ch * 100), 0) + "%")
        }
        if seg.quality != "A" { sub += " · 估算" }
        app.toasts.show(text, sub: sub, actions: actions)
    }
}
