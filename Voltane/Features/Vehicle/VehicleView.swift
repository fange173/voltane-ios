import SwiftUI
import VoltaneKit

/// 车辆页：概要、数据体检、成员与邀请、历史汇总、动态、归档 / 退出 / 删除。
struct VehicleView: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        Group {
            if let v = app.currentVehicle {
                VehicleLoader(vehicle: v).id(v.id)
            } else {
                ContentUnavailableView {
                    Label("还没有车辆", systemImage: "car.fill")
                } description: {
                    Text("添加你的车，或用家人发来的邀请码加入。")
                } actions: {
                    NavigationLink(value: MeRoute.newVehicle) { Label("添加我的车", systemImage: "plus") }.buttonStyle(.vGlassProminent)
                }
            }
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("车辆")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct VehiclePageData: Sendable {
    var health: VehicleHealth
    var members: [Member]
    var summaries: [PeriodSummary]
    var activity: [Activity]
    var invites: [Invite]
}

private struct VehicleLoader: View {
    @Environment(AppModel.self) private var app
    let vehicle: Vehicle
    @State private var data: VehiclePageData?
    @State private var failure: String?

    var body: some View {
        Group {
            if let data {
                VehicleContent(vehicle: vehicle, data: data)
            } else if let failure {
                ContentUnavailableView {
                    Label("加载失败", systemImage: "wifi.exclamationmark")
                } description: { Text(failure) } actions: {
                    Button("重试") { Task { await load() } }.buttonStyle(.vGlass)
                }
            } else {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task(id: app.dataVersion) { await load() }
        .refreshable { await load() }
    }

    private func load() async {
        let repo = app.repository
        let id = vehicle.id
        do {
            async let h = repo.fetch(API.vehicleHealth(vehicleId: id))
            async let m = repo.fetch(API.members(vehicleId: id))
            async let s = repo.fetch(API.summaries(vehicleId: id))
            async let a = repo.fetch(API.activity(vehicleId: id))
            var invites: [Invite] = []
            if vehicle.isOwner { invites = try await repo.fetch(API.invites(vehicleId: id)).value }
            data = VehiclePageData(health: try await h.value, members: try await m.value, summaries: try await s.value,
                                   activity: try await a.value, invites: invites)
            failure = nil
        } catch is CancellationError {
            return
        } catch {
            if data == nil { failure = error.localizedDescription }
        }
    }
}

private enum PageSheet: Identifiable {
    case params, invite, role(Member), summary(PeriodSummary?), delivery(VehicleHealth.Issue)

    var id: String {
        switch self {
        case .params: "params"
        case .invite: "invite"
        case .role(let m): "role-\(m.id)"
        case .summary(let s): "summary-\(s?.id ?? 0)"
        case .delivery: "delivery"
        }
    }
}

private struct VehicleContent: View {
    @Environment(AppModel.self) private var app
    let vehicle: Vehicle
    let data: VehiclePageData

    @State private var sheet: PageSheet?
    @State private var revoking: Invite?
    @State private var confirmLeave = false
    @State private var showDelete = false
    @State private var deleteName = ""

    private var owner: Bool { vehicle.isOwner }
    /// 车主和共同记录者、且未归档才能改数据。
    private var editable: Bool { vehicle.canEdit }
    private var otherOwners: Bool { data.members.filter { $0.role == "owner" }.count > 1 }

    var body: some View {
        ScrollViewReader { proxy in
            List {
                hero
                healthSection(proxy)
                membersSection
                if owner && !data.invites.isEmpty { invitesSection }
                summariesSection.id("summaries")
                activitySection
                moreSection
            }
            .listStyle(.insetGrouped)
        }
        .sheet(item: $sheet) { s in
            switch s {
            case .params: VehicleParamsSheet(vehicle: vehicle)
            case .invite: InviteSheet(vehicle: vehicle)
            case .role(let m): RoleSheet(vehicle: vehicle, member: m, hasInvites: !data.invites.isEmpty)
            case .summary(let existing): SummarySheet(vehicle: vehicle, existing: existing)
            case .delivery(let issue): DeliverySheet(vehicle: vehicle, issue: issue)
            }
        }
        .confirmationDialog("作废邀请码？", isPresented: Binding(get: { revoking != nil }, set: { if !$0 { revoking = nil } }),
                            titleVisibility: .visible, presenting: revoking) { inv in
            Button("作废", role: .destructive) { Task { await revoke(inv) } }
        } message: { _ in Text("作废后这个邀请码不能再使用，已经通过它加入的成员不受影响。") }
        .confirmationDialog("退出这辆车？", isPresented: $confirmLeave, titleVisibility: .visible) {
            Button("退出", role: .destructive) { Task { await leave() } }
        } message: { Text("退出后你将看不到这辆车的数据，你记过的记录会保留。") }
        .alert("删除车辆", isPresented: $showDelete) {
            TextField("车名", text: $deleteName)
            Button("删除", role: .destructive) { Task { await delete() } }
            Button("取消", role: .cancel) {}
        } message: {
            Text("删除后所有成员都看不到这辆车，记录、费用、提醒全部删除且不能恢复。请输入车名「\(vehicle.name)」确认：")
        }
    }

    // MARK: 概要

    private var hero: some View {
        Section {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 12) {
                    VehicleDot(vehicle: vehicle, size: 44)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(vehicle.name).font(.title3.bold())
                        Text(([vehicle.displayLabel] + [vehicle.plate, vehicle.model].compactMap { $0 }.filter { !$0.isEmpty }).joined(separator: " · "))
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if editable {
                        Button { sheet = .params } label: { Label("参数", systemImage: "pencil") }
                            .buttonStyle(.bordered).controlSize(.small)
                    }
                }
                LazyVGrid(columns: [GridItem(.flexible(), alignment: .leading), GridItem(.flexible(), alignment: .leading)],
                          alignment: .leading, spacing: 12) {
                    ForEach(params, id: \.0) { label, value in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(label).font(.caption).foregroundStyle(.secondary)
                            Text(value).font(.subheadline.weight(.semibold)).monospacedDigit()
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
                if vehicle.isArchived {
                    Label("这辆车已归档，只能查看", systemImage: "info.circle.fill").font(.footnote).foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 4)
        }
    }

    /// 概要里的参数格，与网页版 `.v-params` 一致。
    private var params: [(String, String)] {
        var out: [(String, String)] = []
        if let odo = data.health.latestOdo { out.append(("当前里程", "\(Fmt.km(odo)) km")) }
        if vehicle.hasFuel { out.append(("油箱", vehicle.tankCapacityL.map { "\(Fmt.num($0)) L" } ?? "未填")) }
        if vehicle.hasElec {
            out.append(("电池", vehicle.batteryUsableKwh.map { "\(Fmt.num($0)) kWh" } ?? "未填"))
            out.append(("每 1% 电量", data.health.k.map { "\(Fmt.fixed($0, 3)) kWh" } ?? Fmt.dash))
        }
        out.append(("我的角色", Labels.role[vehicle.role ?? ""] ?? Fmt.dash))
        return out
    }

    // MARK: 数据体检

    private func healthSection(_ proxy: ScrollViewProxy) -> some View {
        Section {
            ForEach([("fuel", "油耗", vehicle.hasFuel, data.health.coverage?.fuel), ("elec", "电耗", vehicle.hasElec, data.health.coverage?.elec)].filter(\.2), id: \.0) { _, label, _, c in
                VStack(alignment: .leading, spacing: 6) {
                    HStack { Text("\(label)精确覆盖").font(.subheadline); Spacer(); Text(c.map { "\(Fmt.num($0 * 100, 0))%" } ?? Fmt.dash).monospacedDigit().bold() }
                    ProgressView(value: min(max(c ?? 0, 0), 1)).tint((c ?? 0) > 0.6 ? Color.vOk : Color.vWarn)
                }
                .accessibilityElement(children: .combine)
            }
            Text("记账以来 \(Fmt.km(data.health.ledgerKm)) km 里，能算出精确能耗的里程占比").font(.caption).foregroundStyle(.secondary)
            if data.health.issues.isEmpty {
                Label("数据很完整", systemImage: "checkmark.circle.fill").font(.subheadline).foregroundStyle(Color.vOk)
            } else {
                ForEach(data.health.issues) { issue in issueRow(issue, proxy) }
            }
        } header: { Text("数据体检") } footer: { Text("缺数据只会降低精度，不影响使用") }
    }

    private func issueRow(_ i: VehicleHealth.Issue, _ proxy: ScrollViewProxy) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: i.level == "warn" ? "exclamationmark.triangle.fill" : "info.circle.fill")
                .foregroundStyle(i.level == "warn" ? Color.vWarn : Color.secondary).padding(.top, 2)
            Text(i.text).font(.subheadline).frame(maxWidth: .infinity, alignment: .leading)
            if editable, let label = Self.actionLabels[i.action ?? ""] {
                Button(label) { Task { await run(i, proxy) } }.buttonStyle(.bordered).controlSize(.small).tint(Color.vBrand)
            }
            Button { Task { await dismissIssue(i) } } label: { Image(systemName: "xmark").font(.caption.weight(.semibold)).foregroundStyle(.secondary) }
                .buttonStyle(.borderless).padding(.top, 4).accessibilityLabel("不再提示")
        }
        .swipeActions(edge: .trailing) {
            Button { Task { await dismissIssue(i) } } label: { Label("忽略", systemImage: "eye.slash") }.tint(.gray)
        }
    }

    private static let actionLabels = [
        "fix_missed": "补一条", "record_fuel": "记加油", "edit_vehicle": "去填写", "finish_charge": "结束", "open_summaries": "查看",
        "filter_estimated": "查看", "fix_delivery": "修正", "open_records": "去看看",
    ]

    private func run(_ i: VehicleHealth.Issue, _ proxy: ScrollViewProxy) async {
        do {
            switch i.action {
            case "fix_missed":
                guard let a = i.afterId, let b = i.beforeId else { return }
                let r = try await app.client.send(try API.fixMissed(vehicleId: vehicle.id, afterId: a, beforeId: b, kind: i.kind ?? "charge"))
                app.toasts.show("已自动补一条（约 \(Fmt.num(r.qty))\(i.kind == "fuel" ? "L" : "kWh")）", sub: "标记为估算，可在记录里修改")
                app.bump()
            case "record_fuel": app.sheet = .record(kind: .fuel, vehicleId: vehicle.id)
            case "edit_vehicle": sheet = .params
            case "filter_estimated", "open_records": app.tab = .records
            case "open_summaries": withAnimation { proxy.scrollTo("summaries", anchor: .top) }
            case "fix_delivery": sheet = .delivery(i)
            case "finish_charge":
                guard let id = i.recordId ?? Int(i.key.split(separator: ":").last ?? "") else { return }
                let r = try await app.client.send(API.record(id: id))
                app.sheet = .editRecord(r, finish: true)
            default: break
            }
        } catch { app.toasts.error(error) }
    }

    private func dismissIssue(_ i: VehicleHealth.Issue) async {
        do {
            _ = try await app.client.send(try API.dismissHint(vehicleId: vehicle.id, key: i.key))
            app.bump()
        } catch { app.toasts.error(error) }
    }

    // MARK: 成员与邀请

    private var membersSection: some View {
        Section {
            ForEach(data.members) { m in memberRow(m) }
        } header: {
            HStack {
                Text("成员（\(data.members.count)）")
                Spacer()
                if owner && !vehicle.isArchived { Button { sheet = .invite } label: { Label("邀请", systemImage: "person.badge.plus").font(.subheadline) }.textCase(nil) }
            }
        }
    }

    @ViewBuilder
    private func memberRow(_ m: Member) -> some View {
        let manageable = owner && !m.isMe
        let row = HStack(spacing: 12) {
            AvatarView(user: UserBrief(id: m.id, username: m.username, name: m.name, color: m.color), size: 34)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) { Text(m.name); if m.isMe { Pill(text: "我", tone: .brand) } }
                Text("@\(m.username) · \(m.joinedAt.map { Fmt.date($0.local()) } ?? Fmt.dash) 加入").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if manageable {
                HStack(spacing: 4) { Text(m.roleLabel); Image(systemName: "chevron.up.chevron.down").font(.caption2) }.foregroundStyle(Color.vBrand)
            } else {
                Pill(text: m.roleLabel)
            }
        }
        if manageable {
            Button { sheet = .role(m) } label: { row.contentShape(Rectangle()) }.buttonStyle(.plain)
        } else {
            row
        }
    }

    private var invitesSection: some View {
        Section("邀请码") {
            ForEach(data.invites) { inv in
                HStack(spacing: 12) {
                    IconBadge(systemName: "key.fill", size: 30)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(inv.code).font(.system(.body, design: .monospaced, weight: .bold))
                        Text(inv.metaText).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if !vehicle.isArchived {
                        ShareLink(item: inv.shareText(server: app.server?.primary)) { Image(systemName: "square.and.arrow.up") }
                            .buttonStyle(.borderless).accessibilityLabel("分享邀请")
                    }
                    Button { revoking = inv } label: { Image(systemName: "trash").foregroundStyle(Color.vDanger) }
                        .buttonStyle(.borderless).accessibilityLabel("作废")
                }
                .swipeActions(edge: .trailing) {
                    Button(role: .destructive) { revoking = inv } label: { Label("作废", systemImage: "trash") }
                }
            }
        }
    }

    private func revoke(_ inv: Invite) async {
        do {
            _ = try await app.client.send(API.revokeInvite(id: inv.id))
            app.bump()
        } catch { app.toasts.error(error) }
    }

    // MARK: 汇总与动态

    private var summariesSection: some View {
        Section {
            if data.summaries.isEmpty {
                Text("一条条记不清时，可以按一段时间填合计（如家充桩 App 的月度度数），系统会自动扣掉已经逐条记过的部分。")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            ForEach(data.summaries) { s in summaryRow(s) }
        } header: {
            HStack {
                Text("历史 / 周期汇总")
                Spacer()
                if editable { Button { sheet = .summary(nil) } label: { Label("添加", systemImage: "plus").font(.subheadline) }.textCase(nil) }
            }
        }
    }

    @ViewBuilder
    private func summaryRow(_ s: PeriodSummary) -> some View {
        let row = HStack {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text("\(s.startDate?.dateOnly ?? Fmt.dash) 至 \(s.endDate?.dateOnly ?? Fmt.dash)").font(.subheadline)
                    Pill(text: s.mode == "total" ? "按总数" : "补充没记的")
                }
                let parts = detail(s)
                if !parts.isEmpty { Text(parts).font(.caption).foregroundStyle(.secondary) }
                if s.diff?.warnings?.isEmpty == false { Text("总量小于已记录量").font(.caption).foregroundStyle(Color.vWarn) }
            }
            Spacer()
            if editable { Image(systemName: "chevron.right").font(.footnote).foregroundStyle(.tertiary) }
        }
        if editable { Button { sheet = .summary(s) } label: { row.contentShape(Rectangle()) }.buttonStyle(.plain) } else { row }
    }

    private func detail(_ s: PeriodSummary) -> String {
        [s.fuelLiters.map { "\(Fmt.num($0))L" }, s.fuelCents.map { "加油 \(Fmt.money($0))" },
         s.elecKwh.map { "\(Fmt.num($0))kWh" }, s.elecCents.map { "充电 \(Fmt.money($0))" }].compactMap { $0 }.joined(separator: " · ")
    }

    private var activitySection: some View {
        Section("最近动态") {
            if data.activity.isEmpty { Text("暂无").foregroundStyle(.secondary) }
            ForEach(data.activity) { a in
                HStack(alignment: .top, spacing: 10) {
                    AvatarView(user: a.user, size: 26)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(a.summary).font(.subheadline)
                        Text([a.user?.name, a.createdAt.ago()].compactMap { $0 }.joined(separator: " · ")).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    // MARK: 更多

    private var moreSection: some View {
        Section("更多") {
            NavigationLink(value: MeRoute.newVehicle) { Label("添加另一辆车", systemImage: "plus") }
            if owner {
                Button { Task { await archive() } } label: {
                    Label(vehicle.isArchived ? "取消归档" : "归档（卖掉的车）", systemImage: "archivebox")
                }
            }
            if !owner || otherOwners {
                Button { confirmLeave = true } label: { Label("退出这辆车", systemImage: "rectangle.portrait.and.arrow.right") }.tint(Color.vWarn)
            }
            if owner {
                Button(role: .destructive) { deleteName = ""; showDelete = true } label: { Label("删除车辆和全部数据", systemImage: "trash") }
            }
        }
    }

    private func archive() async {
        do {
            _ = try await app.client.send(try API.archiveVehicle(id: vehicle.id, archived: !vehicle.isArchived))
            await app.reloadAfterVehicleChange()
        } catch { app.toasts.error(error) }
    }

    private func leave() async {
        do {
            _ = try await app.client.send(API.leaveVehicle(id: vehicle.id))
            await leavePage()
        } catch { app.toasts.error(error) }
    }

    private func delete() async {
        do {
            _ = try await app.client.send(try API.deleteVehicle(id: vehicle.id, confirmName: deleteName))
            app.toasts.show("已删除")
            await leavePage()
        } catch { app.toasts.error(error) }
    }

    /// 车已不可见：先退回概览再刷新车辆列表，避免页面闪到另一辆车。
    private func leavePage() async {
        app.mePath = []
        app.tab = .home
        await app.reloadAfterVehicleChange()
    }
}
