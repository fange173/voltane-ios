import SwiftUI
import VoltaneKit

/// 概览：充电中、最近能耗、本期 KPI、待确认、提醒、提车至今、最近记录。
struct HomeView: View {
    @Environment(AppModel.self) private var app
    @State private var range = "month"

    private static let ranges = [("month", "本月"), ("30d", "近30天"), ("year", "今年"), ("all", "全部")]

    var body: some View {
        Group {
            if let v = app.currentVehicle {
                RemoteContent(endpoint: API.overview(vehicleId: v.id, range: range)) { o in
                    HomeContent(overview: o, vehicle: v, range: $range)
                }
                .id("\(v.id)-\(range)")
            } else {
                Welcome()
            }
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("概览")
        .onAppear { range = app.user?.settings["home_range"]?.stringValue ?? "month" }
    }

    private struct Welcome: View {
        @Environment(AppModel.self) private var app

        var body: some View {
            ContentUnavailableView {
                Label("欢迎使用油电簿", systemImage: "bolt.car.fill")
            } description: {
                Text("还没有车辆。添加你的车，或用家人发来的邀请码加入。")
            } actions: {
                NavigationLink { VehicleWizardView() } label: { Label("添加我的车", systemImage: "plus") }.buttonStyle(.vGlassProminent)
                NavigationLink { JoinVehicleView() } label: { Label("用邀请码加入", systemImage: "key.fill") }.buttonStyle(.vGlass)
                Button("刷新") { Task { await app.loadVehicles() } }.buttonStyle(.borderless)
            }
        }
    }
}

private struct HomeContent: View {
    @Environment(AppModel.self) private var app
    let overview: Overview
    let vehicle: Vehicle
    @Binding var range: String

    var body: some View {
        let o = overview
        ScrollView {
            LazyVStack(spacing: 16) {
                ForEach(o.inProgress) { ChargingCard(record: $0, vehicle: vehicle) }
                HeroCard(overview: o, vehicle: vehicle)
                rangePicker(o)
                kpiGrid(o)
                if vehicle.canEdit { QuickRow(vehicle: vehicle) }
                if !o.pending.isEmpty { PendingCard(items: o.pending, vehicle: vehicle) }
                if !o.reminders.isEmpty { RemindersCard(reminders: o.reminders) }
                if let h = o.history, h.days >= 30, app.user?.settings["hide_history"]?.boolValue != true { HistoryCard(history: h) }
                recent(o)
            }
            .padding(16)
            .frame(maxWidth: 720)
            .frame(maxWidth: .infinity)
        }
        .vScrollEdgeSoft()
    }

    private func rangePicker(_ o: Overview) -> some View {
        Picker("范围", selection: Binding(get: { range }, set: { k in
            range = k
            Task { await app.savePref("home_range", .string(k)) }
        })) {
            ForEach([("month", "本月"), ("30d", "近30天"), ("year", "今年"), ("all", "全部")], id: \.0) { Text($0.1).tag($0.0) }
        }
        .pickerStyle(.segmented)
    }

    private func kpiGrid(_ o: Overview) -> some View {
        let p = o.period, prev = o.prev
        let cols = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]
        return LazyVGrid(columns: cols, spacing: 12) {
            KPICard(label: "里程", systemImage: "road.lanes", value: Fmt.km(p.mileage), unit: "km",
                    change: Fmt.pctChange(p.mileage, prev?.mileage), neutral: true)
            KPICard(label: "总花费", systemImage: "creditcard.fill", value: Fmt.money(p.totalCents, digits: (p.totalCents ?? 0) >= 1_000_000 ? 0 : 2),
                    unit: "", change: Fmt.pctChange(p.totalCents.map(Double.init), prev?.totalCents.map(Double.init)),
                    note: (p.summaryCents ?? 0) > 0 ? "含汇总分摊" : nil)
            if vehicle.hasFuel {
                KPICard(label: "加油", systemImage: "fuelpump.fill", value: Fmt.num(p.fuelL, 1), unit: "L", tone: .fuel,
                        note: "\(p.fuelCount ?? 0) 次 · \(Fmt.money(p.fuelCents))")
            }
            if vehicle.hasElec {
                KPICard(label: "充电", systemImage: "bolt.fill", value: Fmt.num(p.elecKwh, 0), unit: "kWh", tone: .elec,
                        note: "\(p.elecCount ?? 0) 次" + (p.homeShare.map { " · 家充 \(Fmt.num($0 * 100, 0))%" } ?? ""))
            }
            KPICard(label: "每公里能源", systemImage: "yensign.circle", value: p.energyCostPerKm.map { "¥" + Fmt.fixed($0) } ?? Fmt.dash, unit: "",
                    change: Fmt.pctChange(p.energyCostPerKm, prev?.energyCostPerKm))
            KPICard(label: "每公里总成本", systemImage: "receipt", value: p.totalCostPerKm.map { "¥" + Fmt.fixed($0) } ?? Fmt.dash, unit: "",
                    change: Fmt.pctChange(p.totalCostPerKm, prev?.totalCostPerKm))
        }
    }

    @ViewBuilder private func recent(_ o: Overview) -> some View {
        SectionTitle(title: "最近记录", trailing: "全部") { app.tab = .records }
        if o.recent.isEmpty {
            Card {
                ContentUnavailableView {
                    Label("还没有记录", systemImage: "list.bullet")
                } description: {
                    Text(Labels.hint["need_start"] ?? "")
                } actions: {
                    if vehicle.canEdit { Button("记第一笔") { app.sheet = .record(kind: vehicle.hasFuel ? .fuel : .charge, vehicleId: vehicle.id) }.buttonStyle(.vGlass) }
                }
            }
        } else {
            Card(padding: 0) {
                VStack(spacing: 0) {
                    ForEach(Array(o.recent.enumerated()), id: \.element.id) { i, item in
                        Button {
                            switch item {
                            case .record(let r): app.sheet = .recordDetail(id: r.id, isExpense: false)
                            case .expense(let e): app.sheet = .recordDetail(id: e.id, isExpense: true)
                            }
                        } label: { RecordRow(item: item).padding(.horizontal, 14).padding(.vertical, 10) }
                            .buttonStyle(.plain)
                        if i < o.recent.count - 1 { Divider().padding(.leading, 66) }
                    }
                }
            }
        }
    }
}

/// 快捷记录，对应网页版 home.js 的 quickRow。
private struct QuickRow: View {
    @Environment(AppModel.self) private var app
    let vehicle: Vehicle

    var body: some View {
        var items: [(String, String, Tone, ActiveSheet)] = []
        if vehicle.hasFuel { items.append(("加油", "fuelpump.fill", .fuel, .record(kind: .fuel, vehicleId: vehicle.id))) }
        if vehicle.hasElec { items.append(("充电", "bolt.fill", .elec, .record(kind: .charge, vehicleId: vehicle.id))) }
        items.append(("记一笔", "yensign.circle.fill", .expense, .expense(vehicleId: vehicle.id)))
        items.append(("快照", "gauge.with.dots.needle.33percent", .snapshot, .record(kind: .snapshot, vehicleId: vehicle.id)))
        return HStack(spacing: 10) {
            ForEach(items, id: \.0) { it in
                Button { app.sheet = it.3 } label: {
                    VStack(spacing: 6) {
                        IconBadge(systemName: it.1, tone: it.2, size: 36)
                        Text(it.0).font(.footnote.weight(.medium))
                    }
                    .frame(maxWidth: .infinity).padding(.vertical, 12)
                    .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
    }
}

private struct KPICard: View {
    let label: String
    let systemImage: String
    let value: String
    let unit: String
    var tone: Tone = .brand
    var change: Double?
    var neutral = false
    var note: String?

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 6) {
                Label(label, systemImage: systemImage).font(.caption).foregroundStyle(.secondary)
                MetricView(value: value, unit: unit, tone: tone)
                HStack(spacing: 6) {
                    if let change { ChangeTag(change: change, neutral: neutral) }
                    if let note { Text(note).font(.caption2).foregroundStyle(.secondary) }
                }
            }
        }
    }
}

struct ChangeTag: View {
    let change: Double
    var neutral = false
    var lowerIsBetter = true

    var body: some View {
        if abs(change) < 0.005 {
            Text("持平").font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
        } else {
            let good = lowerIsBetter ? change < 0 : change > 0
            Text("\(change > 0 ? "↑" : "↓")\(Fmt.num(abs(change) * 100, 0))%")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(neutral ? Color.secondary : good ? Color.vOk : Color.vDanger)
        }
    }
}

private struct ChargingCard: View {
    @Environment(AppModel.self) private var app
    let record: Record
    let vehicle: Vehicle

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "bolt.fill").foregroundStyle(Color.vElec).symbolEffect(.pulse)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text("充电中 · 已").font(.subheadline.weight(.semibold))
                    Text(record.occurredAt.date(), style: .timer).font(.subheadline.weight(.semibold)).monospacedDigit()
                }
                Text("\(Fmt.date(record.occurredAt, time: true)) 开始" + (record.socBeforePct.map { " · 开始电量 \(Fmt.num($0, 0))%" } ?? "")
                     + (record.placeName.map { " · \($0)" } ?? ""))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if vehicle.canEdit {
                Button("结束充电") { app.sheet = .editRecord(record, finish: true) }.buttonStyle(.vGlass).tint(Color.vElec)
            }
        }
        .padding(14)
        .background(Color.vElecSoft, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

private struct HeroCard: View {
    @Environment(AppModel.self) private var app
    let overview: Overview
    let vehicle: Vehicle

    private func scopeText(_ x: LatestEnergy?) -> String {
        guard let x else { return "" }
        switch x.quality {
        case "A": return (x.segments ?? 1) > 1 ? "最近 \(x.segments!) 段 · \(Fmt.km(x.distance))km" : "最近一段 · \(Fmt.km(x.distance))km"
        case "B": return "估算 · \(Fmt.km(x.distance))km"
        case "C": return "粗略 · \(x.scope == "delivery" ? "提车至今" : "记账以来") \(Fmt.km(x.distance))km"
        default: return ""
        }
    }

    private func rangeText(_ x: LatestEnergy?) -> String {
        if x?.quality == "C", let lo = x?.low100, let hi = x?.high100 { return "约 \(Fmt.num(lo))–\(Fmt.num(hi))" }
        return ""
    }

    var body: some View {
        let L = overview.latest
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("最近能耗").font(.headline)
                Spacer()
                if let odo = overview.latestOdo {
                    Label("\(Fmt.km(odo)) km", systemImage: "gauge.with.dots.needle.33percent")
                        .font(.footnote.weight(.medium)).monospacedDigit().foregroundStyle(.secondary)
                        .accessibilityLabel("里程表 \(Fmt.km(odo)) 公里")
                }
            }
            if vehicle.hasFuel && vehicle.hasElec {
                if let c = L.combined, c.quality == "A" {
                    pair(Big(value: c.per100, unit: "L", tone: .fuel, quality: "A"),
                         Big(value: c.elecPer100, unit: "kWh", tone: .elec, quality: c.elecQuality == "A" ? "A" : "B"))
                    Divider()
                    HStack(alignment: .top, spacing: 0) {
                        statCell("每公里", c.costPerKm.map { "¥" + Fmt.fixed($0) })
                        statCell("等效油耗", c.equivPer100.map { Fmt.num($0) + " L" })
                        statCell("电能占比", c.elecShare.map { Fmt.num($0 * 100, 0) + "%" })
                    }
                    Text("满到满 \(Fmt.km(c.distance)) km · \(Fmt.date(c.endTs))" + ((overview.sinceLastFull?.km ?? 0) > 0 ? " · 距上次加满已行驶 \(Fmt.km(overview.sinceLastFull?.km)) km" : ""))
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    let f = L.fuel, e = L.elec
                    pair(Big(value: f?.per100, unit: "L", tone: .fuel, quality: f?.quality, err: f?.err100),
                         Big(value: e?.per100, unit: "kWh", tone: .elec, quality: e?.quality, err: e?.err100))
                    footLine([f?.per100 != nil ? "油：\(scopeText(f)) \(rangeText(f))" : nil, e?.per100 != nil ? "电：\(scopeText(e))" : nil])
                    hintView(f, e)
                }
            } else if vehicle.hasElec {
                let e = L.elec, t = L.elecTotals
                HStack(alignment: .top) {
                    Big(value: e?.per100, unit: "kWh", tone: .elec, quality: e?.quality, err: e?.err100)
                    Spacer()
                    if let o = t?.overall {
                        VStack(alignment: .trailing, spacing: 4) {
                            small("本期行驶", t?.drive.flatMap(\.per100).map { Fmt.num($0) } ?? Fmt.dash)
                            small("含静置", Fmt.num(o.per100))
                            if let idle = t?.idle { small("静置", "\(Fmt.num(idle.amount, 1)) kWh") }
                        }
                    }
                }
                footLine([scopeText(e).isEmpty ? nil : scopeText(e), e?.costPerKm.map { "¥\(Fmt.fixed($0))/km" }])
                if e?.quality == "D", let h = e?.hint { hintLine(Labels.hint[h], kind: .charge) }
            } else {
                let f = L.fuel
                Big(value: f?.per100, unit: "L", tone: .fuel, quality: f?.quality, err: f?.err100)
                footLine([scopeText(f).isEmpty ? nil : "\(scopeText(f)) \(rangeText(f))", f?.costPerKm.map { "¥\(Fmt.fixed($0))/km" }])
                if f?.quality == "D" || f?.quality == "C", let h = f?.hint { hintLine(Labels.hint[h], kind: .fuel) }
            }
            if !(vehicle.hasFuel && vehicle.hasElec && overview.latest.combined?.quality == "A"), let km = overview.sinceLastFull?.km, km > 0 {
                Text("距上次加满已行驶 \(Fmt.km(km)) km").font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private struct Big: View {
        let value: Double?
        let unit: String
        let tone: Tone
        var quality: String?
        var err: Double?

        var body: some View {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Image(systemName: tone == .fuel ? "fuelpump.fill" : "bolt.fill").font(.caption).foregroundStyle(tone.color)
                    Text(tone == .fuel ? "油耗" : "电耗").font(.caption).foregroundStyle(.secondary)
                    QualityBadge(quality: quality, err: err)
                }
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(Fmt.num(value)).font(.system(size: 38, weight: .bold, design: .rounded)).monospacedDigit()
                        .contentTransition(.numericText()).foregroundStyle(tone.text)
                        .lineLimit(1).minimumScaleFactor(0.6)
                    Text("\(unit)/100km").font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
        }
    }

    private func pair(_ a: Big, _ b: Big) -> some View {
        HStack(alignment: .top, spacing: 16) {
            a
            Divider().frame(height: 64)
            b
        }
    }

    private func statCell(_ label: String, _ value: String?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            Text(value ?? Fmt.dash).font(.headline).monospacedDigit().lineLimit(1).minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func small(_ label: String, _ value: String) -> some View {
        HStack(spacing: 6) { Text(label).font(.caption).foregroundStyle(.secondary); Text(value).font(.subheadline.weight(.semibold)).monospacedDigit() }
    }

    @ViewBuilder private func footLine(_ parts: [String?]) -> some View {
        let t = parts.compactMap { $0 }
        if !t.isEmpty {
            // 与网页 .hero-foot 一致：一行放得下就横排，否则逐条换行。
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 16) {
                    ForEach(t, id: \.self) { Text($0).lineLimit(1) }
                }
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(t, id: \.self) { Text($0).lineLimit(2).fixedSize(horizontal: false, vertical: true) }
                }
            }
            .font(.caption).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder private func hintView(_ f: LatestEnergy?, _ e: LatestEnergy?) -> some View {
        if let f, f.hint != nil, f.quality == "C" || f.quality == "D" { hintLine(Labels.hint[f.hint!], kind: .fuel) }
        else if let e, e.hint != nil, e.quality == "D" { hintLine(Labels.hint[e.hint!], kind: .charge) }
    }

    @ViewBuilder private func hintLine(_ text: String?, kind: RecordKind) -> some View {
        if let text {
            HStack(spacing: 8) {
                Image(systemName: "sparkles").foregroundStyle(kind == .fuel ? Color.vFuel : Color.vElec)
                Text(text).font(.footnote).fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 4)
                if vehicle.canEdit {
                    Button(kind == .fuel ? "记加油" : "记充电") { app.sheet = .record(kind: kind, vehicleId: vehicle.id) }
                        .buttonStyle(.vGlass).tint(kind == .fuel ? Color.vFuel : Color.vElec).controlSize(.small)
                }
            }
            .padding(10)
            .background((kind == .fuel ? Color.vFuelSoft : Color.vElecSoft), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
    }
}

private struct PendingCard: View {
    @Environment(AppModel.self) private var app
    let items: [PendingItem]
    let vehicle: Vehicle
    @State private var hidden: Set<String> = []

    var body: some View {
        let visible = items.filter { !hidden.contains($0.key) }
        if !visible.isEmpty {
            Card {
                VStack(alignment: .leading, spacing: 10) {
                    HStack { Label("待确认", systemImage: "exclamationmark.triangle.fill").font(.headline).foregroundStyle(Color.vWarn); Spacer(); Pill(text: "\(visible.count)", tone: .fuel) }
                    ForEach(visible) { it in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(it.text).font(.subheadline)
                            HStack {
                                if it.type == "anomaly", let end = it.endId {
                                    Button("查看") { app.sheet = .recordDetail(id: end, isExpense: false) }.buttonStyle(.bordered)
                                } else if vehicle.canEdit {
                                    Button("补一条") { Task { await fix(it) } }.buttonStyle(.bordered)
                                }
                                Button("忽略") { Task { await dismiss(it) } }.buttonStyle(.borderless)
                            }
                            .controlSize(.small)
                        }
                    }
                }
            }
        }
    }

    private func dismiss(_ it: PendingItem) async {
        do {
            _ = try await app.client.send(try API.dismissHint(vehicleId: vehicle.id, key: it.key))
            hidden.insert(it.key)
        } catch { app.toasts.error(error) }
    }

    private func fix(_ it: PendingItem) async {
        guard let after = it.afterId, let before = it.beforeId else { return }
        let kind = it.type == "missed_fuel" ? "fuel" : "charge"
        do {
            let r = try await app.client.send(try API.fixMissed(vehicleId: vehicle.id, afterId: after, beforeId: before, kind: kind))
            app.toasts.show("已自动补一条\(kind == "fuel" ? "加油" : "充电")（约 \(Fmt.num(r.qty))\(kind == "fuel" ? "L" : "kWh")）", sub: "标记为估算，可在记录里修改")
            app.bump()
        } catch { app.toasts.error(error) }
    }
}

private struct RemindersCard: View {
    @Environment(AppModel.self) private var app
    let reminders: [Reminder]

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                Label("用车提醒", systemImage: "bell.fill").font(.headline)
                ForEach(Array(reminders.enumerated()), id: \.element.id) { i, r in
                    if i > 0 { Divider() }
                    HStack(spacing: 10) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(r.title).font(.subheadline.weight(.medium))
                            Text(ReminderText.due(r)).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        let s = ReminderText.status(r.status)
                        Pill(text: s.0, tone: s.1)
                    }
                }
            }
        }
    }
}

/// 提醒文案，对应网页版 reminders.js 的 dueText / STATUS。
enum ReminderText {
    static func due(_ r: Reminder) -> String {
        var parts: [String] = []
        if let d = r.daysLeft { parts.append(d < 0 ? "已过 \(-d) 天" : d == 0 ? "今天到期" : "还剩 \(d) 天") }
        if let k = r.kmLeft { parts.append(k < 0 ? "超出 \(Fmt.km(-k)) km" : "还剩 \(Fmt.km(k)) km") }
        if let k = r.kmLeft, k > 0, let eta = r.etaDate, r.daysLeft == nil { parts.append("约 \(Fmt.date(eta))") }
        return parts.isEmpty ? "未设置到期" : parts.joined(separator: " · ")
    }

    static func status(_ s: String?) -> (String, Tone) {
        switch s {
        case "overdue": ("已过期", .fuel)
        case "soon": ("临近", .fuel)
        case "ok": ("正常", .elec)
        default: ("已停用", .snapshot)
        }
    }
}

private struct HistoryCard: View {
    @Environment(AppModel.self) private var app
    let history: HistoryStat

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Label(history.scope == "delivery" ? "提车至今" : "记账以来", systemImage: "clock.arrow.circlepath").font(.headline)
                    Spacer()
                    if history.hasSummary == true { Pill(text: "含历史汇总") }
                    Button { Task { await app.savePref("hide_history", .bool(true)); app.toasts.show("已隐藏，可在「我的」里重新打开") } } label: {
                        Image(systemName: "xmark").font(.caption)
                    }.buttonStyle(.borderless).accessibilityLabel("隐藏")
                }
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 16, alignment: .topLeading), GridItem(.flexible(), alignment: .topLeading)], alignment: .leading, spacing: 14) {
                    cell("\(history.days) 天", "\(Fmt.km(history.mileage)) km")
                    cell("总花费", Fmt.money(history.totalCents, digits: 0))
                    if let f = history.fuel {
                        cell("油耗", "\(Fmt.num(f.per100)) L", note: f.low100 != nil ? "约 \(Fmt.num(f.low100))–\(Fmt.num(f.high100))" : nil)
                    }
                    if let e = history.elec { cell("电耗", "\(Fmt.num(e.per100)) kWh") }
                    cell("每公里总成本", history.totalCostPerKm.map { "¥" + Fmt.fixed($0) } ?? Fmt.dash)
                }
                if let s = history.summaryBeforeCents, s > 0 {
                    Text("另有记账前的历史汇总 \(Fmt.money(s, digits: 0))，那段里程未知，没有计入每公里成本").font(.caption2).foregroundStyle(.secondary)
                }
                if history.fuel != nil || history.elec != nil { Text("粗略口径：按长期补能总量估算，仅供参考").font(.caption2).foregroundStyle(.secondary) }
            }
        }
    }

    private func cell(_ label: String, _ value: String, note: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.headline).monospacedDigit().lineLimit(1).minimumScaleFactor(0.8)
            if let note { Text(note).font(.caption2).foregroundStyle(.secondary) }
        }
    }
}
