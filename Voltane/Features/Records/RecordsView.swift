import SwiftUI
import VoltaneKit

/// 记录列表：按月分组，筛选、搜索、游标分页，左滑删除（带撤销），右滑编辑。
struct RecordsView: View {
    @Environment(AppModel.self) private var app
    @State private var filter = ""
    @State private var query = ""
    @State private var items: [TimelineItem] = []
    @State private var next: LocalDateTime?
    @State private var loading = false
    @State private var loaded = false
    @State private var failure: String?
    @State private var offline: Date?
    /// 月份里程用统计接口的口径（按里程表插值分摊），和概览一致。
    @State private var monthKm: [String: Double] = [:]

    private static let filters: [(String, String)] = [
        ("", "全部"), ("fuel", "加油"), ("charge", "充电"), ("snapshot", "快照"), ("expense", "费用"),
        ("mine", "我记的"), ("anomaly", "有异常"), ("estimated", "补录/估算"),
    ]

    var body: some View {
        Group {
            if let v = app.currentVehicle { list(v) } else {
                ContentUnavailableView("还没有车辆", systemImage: "car.fill", description: Text("添加车辆后就可以在这里查看记录。"))
            }
        }
        .navigationTitle("记录")
        .background(Color(.systemGroupedBackground))
    }

    private func list(_ v: Vehicle) -> some View {
        let groups = Dictionary(grouping: items, by: { $0.occurredAt.monthKey }).sorted { $0.key > $1.key }
        return List {
            if app.outboxCount > 0 {
                Button { app.sheet = .outbox(vehicleId: v.id) } label: {
                    Label("\(app.outboxCount) 条待同步", systemImage: "arrow.triangle.2.circlepath").foregroundStyle(Color.vWarn)
                }
            }
            if loaded && items.isEmpty {
                ContentUnavailableView {
                    Label(filter.isEmpty && query.isEmpty ? "还没有记录" : "没有符合条件的记录", systemImage: "list.bullet")
                } description: {
                    Text(filter.isEmpty && query.isEmpty ? "建议从一次「加满」或「状态快照」开始记录。" : "换个筛选条件试试。")
                } actions: {
                    if v.canEdit && filter.isEmpty && query.isEmpty {
                        Button("记第一笔") { app.sheet = .record(kind: v.hasFuel ? .fuel : .charge, vehicleId: v.id) }.buttonStyle(.vGlass)
                    }
                }
                .listRowBackground(Color.clear)
            }
            ForEach(groups, id: \.key) { month, arr in
                Section {
                    ForEach(arr) { item in
                        Button { open(item) } label: { RecordRow(item: item) }
                            .buttonStyle(.plain)
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                if canDelete(item, v) { Button(role: .destructive) { Task { await delete(item) } } label: { Label("删除", systemImage: "trash") } }
                            }
                            .swipeActions(edge: .leading) {
                                if canEdit(item, v) { Button { edit(item) } label: { Label("编辑", systemImage: "pencil") }.tint(Color.vBrand) }
                            }
                            .onAppear { if item.id == items.last?.id, next != nil { Task { await loadMore(v) } } }
                    }
                } header: {
                    HStack { Text(monthTitle(month)).font(.subheadline.weight(.semibold)); Spacer(); Text(summary(arr, km: monthKm[month])).font(.caption).foregroundStyle(.secondary) }
                        .textCase(nil)
                }
            }
            if let failure, items.isEmpty {
                ContentUnavailableView { Label("加载失败", systemImage: "wifi.exclamationmark") } description: { Text(failure) } actions: {
                    Button("重试") { Task { await reload(v) } }.buttonStyle(.vGlass)
                }
            }
            if loading && !items.isEmpty { ProgressView().frame(maxWidth: .infinity).listRowBackground(Color.clear) }
            else if loaded && next == nil && !items.isEmpty { Text("— 共 \(items.count) 条 —").font(.caption).foregroundStyle(.tertiary).frame(maxWidth: .infinity).listRowBackground(Color.clear) }
        }
        .listStyle(.insetGrouped)
        .searchable(text: $query, prompt: "搜索地点、备注")
        .safeAreaInset(edge: .top, spacing: 0) { if let offline { OfflineBanner(updatedAt: offline) } }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Picker("筛选", selection: $filter) {
                        ForEach(Self.filters.filter { f in f.0 == "fuel" ? v.hasFuel : f.0 == "charge" ? v.hasElec : true }, id: \.0) { Text($0.1).tag($0.0) }
                    }
                } label: { Image(systemName: filter.isEmpty ? "line.3.horizontal.decrease.circle" : "line.3.horizontal.decrease.circle.fill") }
                    .accessibilityLabel("筛选")
            }
        }
        .task(id: "\(v.id)|\(filter)|\(query)|\(app.dataVersion)") {
            if !query.isEmpty { try? await Task.sleep(for: .milliseconds(300)) }
            guard !Task.isCancelled else { return }
            await reload(v)
        }
        .task(id: "\(v.id)|\(app.dataVersion)") {
            if let r = try? await app.client.send(API.statsMileage(vehicleId: v.id)) {
                monthKm = Dictionary(r.months.compactMap { m in m.km.map { (m.month, $0) } }, uniquingKeysWith: { a, _ in a })
            }
        }
        .refreshable { await reload(v); await app.flushOutbox() }
    }

    private func endpoint(_ v: Vehicle, before: LocalDateTime?) -> Endpoint<TimelinePage> {
        let kind = ["fuel", "charge", "snapshot", "expense", "estimated"].contains(filter) ? filter : nil
        return API.records(vehicleId: v.id, kind: kind, query: query.isEmpty ? nil : query, mine: filter == "mine",
                           anomaly: filter == "anomaly", before: before)
    }

    private func reload(_ v: Vehicle) async {
        let ep = endpoint(v, before: nil)
        if !loaded, let c = await app.repository.cached(ep) { items = c.value.items; next = c.value.next; loaded = true }
        loading = true
        defer { loading = false }
        do {
            let r = try await app.repository.fetch(ep)
            items = r.value.items; next = r.value.next; failure = nil; offline = nil
        } catch is CancellationError {
            return
        } catch let e as APIError {
            if items.isEmpty { failure = e.message } else if e.isNetwork { offline = Date() }
        } catch {}
        loaded = true
    }

    private func loadMore(_ v: Vehicle) async {
        guard let cursor = next, !loading else { return }
        loading = true
        defer { loading = false }
        if let r = try? await app.client.send(endpoint(v, before: cursor)) {
            let seen = Set(items.map(\.id))
            items += r.items.filter { !seen.contains($0.id) }
            next = r.next
        }
    }

    private func open(_ item: TimelineItem) {
        switch item {
        case .record(let r): app.sheet = .recordDetail(id: r.id, isExpense: false)
        case .expense(let e): app.sheet = .recordDetail(id: e.id, isExpense: true)
        }
    }

    private func edit(_ item: TimelineItem) {
        switch item {
        case .record(let r): app.sheet = .editRecord(r, finish: false)
        case .expense(let e): app.sheet = .editExpense(e)
        }
    }

    private func canEdit(_ item: TimelineItem, _ v: Vehicle) -> Bool { v.canEdit }

    private func canDelete(_ item: TimelineItem, _ v: Vehicle) -> Bool {
        guard v.canEdit else { return false }
        if v.isOwner { return true }
        let creator: Int? = { switch item { case .record(let r): r.createdBy?.id; case .expense(let e): e.createdBy?.id } }()
        return creator == app.user?.id
    }

    private func delete(_ item: TimelineItem) async {
        do {
            switch item {
            case .record(let r): _ = try await app.client.send(API.deleteRecord(id: r.id))
            case .expense(let e): _ = try await app.client.send(API.deleteExpense(id: e.id))
            }
            items.removeAll { $0.id == item.id }
            app.bump()
            app.toasts.show("已删除", actions: [ToastAction(label: "撤销") {
                do {
                    switch item {
                    case .record(let r): _ = try await app.client.send(API.restoreRecord(id: r.id))
                    case .expense(let e): _ = try await app.client.send(API.restoreExpense(id: e.id))
                    }
                    app.bump()
                } catch { app.toasts.error(error) }
            }])
        } catch { app.toasts.error(error) }
    }

    private func monthTitle(_ key: String) -> String {
        let p = key.split(separator: "-")
        return p.count == 2 ? "\(p[0]) 年 \(Int(p[1]) ?? 0) 月" : key
    }

    private func summary(_ arr: [TimelineItem], km: Double?) -> String {
        var cents = 0, fuel = 0.0, kwh = 0.0
        var odos: [Double] = []
        for it in arr {
            switch it {
            case .expense(let e): cents += e.amountCents
            case .record(let r):
                cents += r.amountCents ?? 0
                if r.kind == "fuel" { fuel += r.fuelLiters ?? 0 }
                if r.kind == "charge" { kwh += r.chargeKwh ?? 0 }
                if let o = r.odometerKm, !r.isOdometerEstimated { odos.append(o) }
            }
        }
        var parts = [Fmt.money(cents)]
        if fuel > 0 { parts.append(Fmt.num(fuel, 1) + "L") }
        if kwh > 0 { parts.append(Fmt.num(kwh, 0) + "kWh") }
        if let km {
            if km > 0 { parts.append(Fmt.km(km) + "km") }
        } else if odos.count > 1, let hi = odos.max(), let lo = odos.min() { parts.append(Fmt.km(hi - lo) + "km") }
        return parts.joined(separator: " · ")
    }
}
