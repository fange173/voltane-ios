import SwiftUI
import VoltaneKit

/// 记录或费用详情：基本信息、能耗段与算式、段标记、编辑与删除。
struct RecordDetailView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    let id: Int
    let isExpense: Bool

    var body: some View {
        Group {
            if isExpense {
                RemoteContent(endpoint: API.expense(id: id)) { ExpenseDetail(expense: $0, close: { dismiss() }) }
            } else {
                RemoteContent(endpoint: API.record(id: id)) { RecordDetail(record: $0, close: { dismiss() }) }
            }
        }
        .navigationTitle(isExpense ? "费用详情" : "记录详情")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("关闭") { dismiss() } } }
    }
}

private struct RecordDetail: View {
    @Environment(AppModel.self) private var app
    let record: Record
    let close: () -> Void
    @State private var confirmDelete = false

    private var vehicle: Vehicle? { app.vehicles.first { $0.id == record.vehicleId } }

    var body: some View {
        let d = TimelineDisplay(item: .record(record), vehicles: app.vehicles)
        List {
            Section {
                HStack(spacing: 12) {
                    IconBadge(systemName: d.systemImage, tone: d.tone, size: 44)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(d.title).font(.headline)
                        if let c = record.createdBy {
                            HStack(spacing: 4) {
                                AvatarView(user: c)
                                Text("\(c.name) 记录" + (record.updatedBy.map { $0.id != c.id ? " · \($0.name) 修改过" : "" } ?? ""))
                            }.font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    if let c = record.amountCents { Text(Fmt.money(c)).font(.title3.bold()).monospacedDigit() }
                }
            }
            ForEach(dedupe(record.segments ?? []), id: \.self) { s in
                SegmentSection(segment: s, record: record, canMark: record.canEdit == true, vehicle: vehicle)
            }
            Section {
                ForEach(rows(), id: \.0) { row in
                    LabeledContent(row.0) { Text(row.1).multilineTextAlignment(.trailing) }
                }
            }
            if record.canEdit == true || record.canDelete == true {
                Section {
                    if record.isInProgress && record.canEdit == true {
                        Button("结束充电", systemImage: "checkmark.circle.fill") { app.sheet = .editRecord(record, finish: true) }.tint(Color.vElec)
                    }
                    if record.canEdit == true { Button("编辑", systemImage: "pencil") { app.sheet = .editRecord(record, finish: false) } }
                    if record.canDelete == true { Button("删除", systemImage: "trash", role: .destructive) { confirmDelete = true } }
                }
            }
        }
        .confirmationDialog("删除这条记录？删除后会进入回收站，30 天内可以恢复。", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("删除", role: .destructive) { Task { await delete() } }
        }
    }

    private func dedupe(_ segs: [Segment]) -> [Segment] {
        let comb = segs.filter { $0.energy == "combined" }
        return segs.filter { s in !(s.energy == "fuel" && comb.contains { $0.startId == s.startId && $0.endId == s.endId }) }
    }

    private func rows() -> [(String, String)] {
        var kv: [(String, String)] = []
        func add(_ k: String, _ v: String?) { if let v, !v.isEmpty { kv.append((k, v)) } }
        let r = record
        add("时间", Fmt.date(r.occurredAt, year: true, time: true, week: true))
        add("里程", r.odometerKm.map { (r.isOdometerEstimated ? "估算 " : "") + Fmt.km($0) + " km" } ?? "未填（按前后记录推算）")
        let est = r.estimated
        switch r.kind {
        case "fuel":
            add("标号", Labels.grade(r.fuelGrade))
            add("加油量", r.fuelLiters.map { Fmt.num($0) + " L" + (est.contains("fuel_l") ? "（推算）" : "") })
            add("单价", r.fuelUnitPrice.map { Fmt.fixed($0) + " 元/L" })
            add("加满", r.fuelIsFull == true ? "是" : "否")
            add("加油前油量", Fmt.fuelLevel(r.fuelLevelBeforePct, vehicle: vehicle))
            add("加油后油量", Fmt.fuelLevel(r.fuelLevelAfterPct, vehicle: vehicle))
            add("当前电量", r.socBeforePct.map { Fmt.num($0, 0) + "%" })
        case "charge":
            add("方式", Labels.chargeLabel(r.chargeType))
            if r.socBeforePct != nil || r.socAfterPct != nil {
                add("电量", "\(r.socBeforePct.map { Fmt.num($0, 0) + "%" } ?? "?") → \(r.socAfterPct.map { Fmt.num($0, 0) + "%" } ?? (r.chargeToLimit == true ? "上限" : "?"))")
            }
            add("充电量", r.chargeKwh.map { Fmt.num($0) + " kWh" + (est.contains("charge_kwh") ? "（推算）" : "") })
            add("单价", r.chargeUnitPrice.map { Fmt.fixed($0, 3) + " 元/度" })
            add("时长", r.chargeMinutes.map { "\($0 / 60)小时\($0 % 60)分" })
            if r.energyFeeCents != nil { add("电费 / 服务费", "\(Fmt.money(r.energyFeeCents)) / \(Fmt.money(r.serviceFeeCents))") }
            add("当前油量", Fmt.fuelLevel(r.fuelLevelBeforePct, vehicle: vehicle))
        default:
            add("标签", Labels.snapshotTags[r.snapshotTag ?? ""])
            add("电量", r.socBeforePct.map { Fmt.num($0, 0) + "%" })
            add("油量", Fmt.fuelLevel(r.fuelLevelBeforePct, vehicle: vehicle))
        }
        if let e = r.extraFeeCents, e != 0 { add("附加费", Fmt.money(e)) }
        add("地点", r.placeName)
        if r.missedBefore == true { add("漏记", "上次补能没记") }
        add("备注", r.note)
        return kv
    }

    private func delete() async {
        do {
            _ = try await app.client.send(API.deleteRecord(id: record.id))
            close()
            app.bump()
            let id = record.id
            app.toasts.show("已删除", actions: [ToastAction(label: "撤销") {
                do { _ = try await app.client.send(API.restoreRecord(id: id)); app.bump() } catch { app.toasts.error(error) }
            }])
        } catch { app.toasts.error(error) }
    }
}

private struct SegmentSection: View {
    @Environment(AppModel.self) private var app
    let segment: Segment
    let record: Record
    let canMark: Bool
    let vehicle: Vehicle?
    @State private var tag: String
    @State private var excluded: Bool

    init(segment: Segment, record: Record, canMark: Bool, vehicle: Vehicle?) {
        self.segment = segment; self.record = record; self.canMark = canMark; self.vehicle = vehicle
        _tag = State(initialValue: segment.tag ?? "normal")
        _excluded = State(initialValue: segment.excluded == true)
    }

    var body: some View {
        let s = segment
        let isComb = s.energy == "combined"
        let unit = s.energy == "fuel" || isComb ? "L" : "kWh"
        Section {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(isComb ? "本段综合能耗" : s.energy == "fuel" ? "本段油耗" : s.kind == "idle" ? "本段静置耗电" : "本段电耗").font(.headline)
                    Spacer()
                    Text("\(Fmt.date(s.startTs)) → \(Fmt.date(s.endTs)) · \(Fmt.km(s.distance)) km").font(.caption).foregroundStyle(.secondary)
                }
                if s.status != "ok" {
                    Pill(text: Labels.segmentIssue[s.status ?? ""] ?? "无法计算", tone: .fuel)
                } else if s.kind == "idle" {
                    HStack(alignment: .firstTextBaseline) {
                        Text("\(Fmt.num(s.amount)) kWh").font(.title2.bold()).monospacedDigit()
                        Text("\(Fmt.num(s.days, 1)) 天 · \(Fmt.num(s.perDay)) kWh/天").font(.caption).foregroundStyle(.secondary)
                    }
                } else if isComb {
                    HStack(alignment: .firstTextBaseline, spacing: 14) {
                        Text("\(Fmt.num(s.per100)) L").font(.title2.bold()).foregroundStyle(Color.vFuelStrong)
                        Text("\(Fmt.num(s.elecPer100)) kWh").font(.title2.bold()).foregroundStyle(Color.vElecStrong)
                        Text("/100km").font(.caption).foregroundStyle(.secondary)
                    }.monospacedDigit()
                } else {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text("\(Fmt.num(s.per100)) \(unit)/100km").font(.title2.bold()).monospacedDigit()
                            .foregroundStyle(s.energy == "fuel" ? Color.vFuelStrong : Color.vElecStrong)
                        QualityBadge(quality: s.quality, err: s.err100)
                    }
                }
                if let a = s.anomaly { Pill(text: Labels.anomaly[a] ?? a, tone: .fuel) }
                if isComb && s.status == "ok" {
                    Text([s.costPerKm.map { "每公里 ¥\(Fmt.fixed($0))" }, s.equivPer100.map { "等效油耗 \(Fmt.num($0)) L" },
                          s.elecShare.map { "电能占比 \(Fmt.num($0 * 100, 0))%" }].compactMap { $0 }.joined(separator: "  ·  "))
                        .font(.caption).foregroundStyle(.secondary)
                }
                if let parts = s.explain?.parts, !parts.isEmpty { formula(parts, distance: s.distance) }
            }
            if canMark, let endId = s.endId {
                Picker("段标签", selection: $tag) { ForEach(Labels.segmentTagOrder, id: \.self) { Text(Labels.segmentTags[$0] ?? $0).tag($0) } }
                    .onChange(of: tag) { _, new in Task { await mark(endId, new, excluded) } }
                Toggle("不计入行驶能耗（仍计入综合能耗和花费）", isOn: $excluded)
                    .onChange(of: excluded) { _, new in Task { await mark(endId, tag, new) } }
            }
        }
    }

    private func formula(_ parts: [Segment.Part], distance: Double?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(Array(parts.enumerated()), id: \.offset) { _, p in
                if let t = p.text { Text(t) } else {
                    let u = p.unit == "L" ? "L" : "kWh"
                    Text("\(p.energy == "fuel" ? "油" : "电")：起点 \(p.start ?? "–")（\(Fmt.num(p.startValue))\(u)）− 终点 \(p.end ?? "–")（\(Fmt.num(p.endValue))\(u)）+ 期间补能 \(Fmt.num(p.added))\(u) = \(Fmt.num(p.amount))\(u)"
                         + (p.k.map { "（每 1% 电量 ≈ \(Fmt.fixed($0, 3)) kWh）" } ?? ""))
                }
            }
            Text("÷ \(Fmt.km(distance)) km × 100")
        }
        .font(.system(.caption, design: .monospaced))
        .padding(10).frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func mark(_ endId: Int, _ tag: String, _ excluded: Bool) async {
        do {
            _ = try await app.client.send(try API.markSegment(.init(vehicleId: record.vehicleId, endRecordId: endId, energy: segment.energy, tag: tag, excluded: excluded)))
            app.bump()
            app.toasts.show("已更新这段的标签")
        } catch { app.toasts.error(error) }
    }
}

private struct ExpenseDetail: View {
    @Environment(AppModel.self) private var app
    let expense: Expense
    let close: () -> Void
    @State private var confirmDelete = false

    var body: some View {
        List {
            Section {
                HStack(spacing: 12) {
                    IconBadge(systemName: TimelineDisplay(item: .expense(expense), vehicles: app.vehicles).systemImage, tone: .expense, size: 44)
                    Text(TimelineDisplay(item: .expense(expense), vehicles: app.vehicles).title).font(.headline)
                    Spacer()
                    Text(Fmt.money(expense.amountCents)).font(.title3.bold()).monospacedDigit()
                }
            }
            Section {
                LabeledContent("时间", value: Fmt.date(expense.occurredAt, year: true, time: true, week: true))
                LabeledContent("里程", value: expense.odometerKm.map { Fmt.km($0) + " km" } ?? "未填（按前后记录推算）")
                LabeledContent("分类", value: Labels.expense[expense.category] ?? expense.category)
                if let t = expense.title, !t.isEmpty { LabeledContent("名称", value: t) }
                if let v = expense.vendor, !v.isEmpty { LabeledContent("商家", value: v) }
                ForEach(expense.subItems ?? [], id: \.name) { LabeledContent($0.name, value: Fmt.money($0.cents)) }
                if let s = expense.periodStart { LabeledContent("保险期间", value: "\(s.dateOnly) 至 \(expense.periodEnd?.dateOnly ?? "–")") }
                if let n = expense.note, !n.isEmpty { LabeledContent("备注", value: n) }
            }
            if expense.canEdit == true || expense.canDelete == true {
                Section {
                    if expense.canEdit == true { Button("编辑", systemImage: "pencil") { app.sheet = .editExpense(expense) } }
                    if expense.canDelete == true { Button("删除", systemImage: "trash", role: .destructive) { confirmDelete = true } }
                }
            }
        }
        .confirmationDialog("删除这笔费用？删除后会进入回收站，30 天内可以恢复。", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("删除", role: .destructive) {
                Task {
                    do {
                        _ = try await app.client.send(API.deleteExpense(id: expense.id))
                        close(); app.bump()
                        let id = expense.id
                        app.toasts.show("已删除", actions: [ToastAction(label: "撤销") {
                            do { _ = try await app.client.send(API.restoreExpense(id: id)); app.bump() } catch { app.toasts.error(error) }
                        }])
                    } catch { app.toasts.error(error) }
                }
            }
        }
    }
}
