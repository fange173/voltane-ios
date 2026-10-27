import SwiftUI
import VoltaneKit

@MainActor @Observable
final class ExpenseFormModel {
    enum Mode { case create(vehicleId: Int), edit(Expense), pending(OutboxItem) }

    let app: AppModel
    let mode: Mode
    let vehicle: Vehicle
    var category = "maintenance"
    var amountText = ""
    var amountIsUser = false
    var occurredAt = LocalDateTime(date: Date())
    var odometerText = ""
    var title = ""
    var vendor = ""
    var note = ""
    var insuranceItems: [String: String] = [:]
    var periodStart: Date?
    var periodEnd: Date?
    var error: String?
    var saving = false
    var finished = false
    private var clientId = UUID().uuidString
    private var version: Int?
    private var pendingId: UUID?
    static let insuranceNames = ["交强险", "商业险", "驾意险", "车船税"]

    init(app: AppModel, mode: Mode) {
        self.app = app; self.mode = mode
        var vid = 0
        var existing: Expense?
        var cid = UUID().uuidString
        var pid: UUID?
        switch mode {
        case .create(let v): vid = v
        case .edit(let e): existing = e; vid = e.vehicleId
        case .pending(let item):
            vid = item.vehicleId; pid = item.id
            if var obj = (try? JSONSerialization.jsonObject(with: item.body)) as? [String: Any] {
                cid = (obj["client_id"] as? String) ?? cid
                obj["id"] = 0
                if let d = try? JSONSerialization.data(withJSONObject: obj) { existing = try? JSONCoding.decoder.decode(Expense.self, from: d) }
            }
        }
        clientId = cid
        pendingId = pid
        vehicle = app.vehicles.first { $0.id == vid } ?? Vehicle(id: vid, name: "", energyType: "phev", hasFuel: true, hasElec: true)
        if let e = existing {
            category = e.category
            amountText = (Decimal(e.amountCents) / 100).plainString; amountIsUser = true
            occurredAt = e.occurredAt
            odometerText = e.odometerKm.map(JSNumber.jsString) ?? ""
            title = e.title ?? ""; vendor = e.vendor ?? ""; note = e.note ?? ""
            if case .edit = mode { version = e.version }
            for it in e.subItems ?? [] { insuranceItems[it.name] = (Decimal(it.cents) / 100).plainString }
            periodStart = e.periodStart?.date(); periodEnd = e.periodEnd?.date()
        }
    }

    func setCategory(_ c: String) {
        category = c
        if c == "insurance", periodStart == nil {
            let cal = Calendar.current
            let d = occurredAt.date()
            let s = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: d)) ?? d
            periodStart = s
            periodEnd = cal.date(byAdding: .day, value: -1, to: cal.date(byAdding: .year, value: 1, to: s) ?? s)
        }
    }

    /// 险种金额填了就自动合计，除非用户已经手填了总金额。
    func setInsurance(_ name: String, _ text: String) {
        insuranceItems[name] = text
        let sum = insuranceItems.values.reduce(Decimal(0)) { $0 + (Decimal(plain: $1) ?? 0) }
        if sum > 0 && !amountIsUser { amountText = sum.plainString }
    }

    func setAmount(_ t: String) { amountText = t; amountIsUser = !t.isEmpty }

    func save() async {
        guard let amt = AmountExpression.cents(amountText), amt >= 0 else { error = "请填写金额"; return }
        var p = ExpensePayload(vehicleId: vehicle.id, category: category, occurredAt: occurredAt, amountCents: amt)
        p.title = title.trimmingCharacters(in: .whitespaces)
        p.odometerKm = JSNumber.parse(odometerText)
        p.vendor = vendor.trimmingCharacters(in: .whitespaces)
        p.note = note.trimmingCharacters(in: .whitespacesAndNewlines)
        if category == "insurance" {
            p.periodStart = periodStart.map { LocalDateTime(date: $0) }
            p.periodEnd = periodEnd.map { LocalDateTime(date: $0) }
            p.subItems = Self.insuranceNames.compactMap { n in
                guard let c = insuranceItems[n].flatMap({ Decimal(plain: $0) })?.cents, c != 0 else { return nil }
                return ExpensePayload.SubItem(name: n, cents: c)
            }
        }
        if let v = version { p.version = v } else { p.clientId = clientId }
        error = nil
        saving = true
        defer { saving = false }
        do {
            let editing: Int? = { if case .edit(let e) = mode { e.id } else { nil } }()
            let res = editing != nil ? try await app.client.send(try API.updateExpense(id: editing!, p)) : try await app.client.send(try API.createExpense(p))
            if let pid = pendingId { await app.outbox.remove(pid); await app.refreshOutboxCount() }
            app.bump()
            finished = true
            if let r = res.insuranceReminder {
                app.toasts.show("已更新「保险到期」提醒：\(r.dueDate?.dateOnly ?? "")")
            } else {
                app.toasts.show(editing != nil ? "已保存" : "已记录 \(Labels.expense[category] ?? "") \(Fmt.money(amt))")
            }
            for s in res.suggestComplete ?? [] { app.pendingReminderCompletions.append(.init(reminder: s, doneAt: occurredAt, odometer: p.odometerKm)) }
        } catch let e as APIError {
            if e.isNetwork && version == nil {
                guard let body = try? JSONCoding.encoder.encode(p) else { return }
                if let pid = pendingId { await app.outbox.replace(pid, label: "费用", body: body) }
                else { await app.outbox.enqueue(kind: .expense, vehicleId: vehicle.id, label: "费用", body: body) }
                await app.refreshOutboxCount()
                app.toasts.show("网络不通，已离线保存", sub: "联网后会自动同步")
                finished = true
            } else {
                error = e.message
            }
        } catch {
            self.error = error.localizedDescription
        }
    }
}

struct ExpenseFormView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    let mode: ExpenseFormModel.Mode
    @State private var model: ExpenseFormModel?

    var body: some View {
        NavigationStack {
            Group { if let model { FormContent(model: model) } else { ProgressView() } }
                .navigationTitle(isEdit ? "编辑费用" : "记一笔费用").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } } }
        }
        .task {
            if model == nil { model = ExpenseFormModel(app: app, mode: mode) }
        }
    }

    private var isEdit: Bool { if case .edit = mode { true } else { false } }

    private struct FormContent: View {
        @Environment(\.dismiss) private var dismiss
        @Bindable var model: ExpenseFormModel
        @FocusState private var focus: Bool
        @State private var keyboardVisible = false

        var body: some View {
            ScrollView {
                VStack(spacing: 14) {
                    Card { categoryGrid }
                    Card {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("金额").font(.caption).foregroundStyle(.secondary)
                            HStack {
                                TextField("0.00，可输入 200+15", text: Binding(get: { model.amountText }, set: { model.setAmount($0) }))
                                    .keyboardType(.numbersAndPunctuation).font(.title3.weight(.semibold)).monospacedDigit().focused($focus)
                                Text("元").foregroundStyle(.secondary)
                            }
                            .padding(10).background(Color(.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                    }
                    if model.category == "insurance" { Card { insurance } }
                    Card {
                        VStack(alignment: .leading, spacing: 12) {
                            DatePicker("日期", selection: Binding(get: { model.occurredAt.date() }, set: { model.occurredAt = LocalDateTime(date: $0) }),
                                       in: ...Date().addingTimeInterval(86400), displayedComponents: [.date, .hourAndMinute])
                            field("里程（可选）", "km", $model.odometerText, keyboard: .numberPad)
                            field("名称（可选）", "", $model.title, placeholder: "如：小保养")
                            field("商家（可选）", "", $model.vendor, placeholder: "如：4S 店")
                        }
                    }
                    Card {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("备注").font(.caption).foregroundStyle(.secondary)
                            TextField("可不填", text: $model.note, axis: .vertical).lineLimit(2...5).padding(10)
                                .background(Color(.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                    }
                    if let e = model.error { Text(e).font(.footnote).foregroundStyle(Color.vDanger) }
                }
                .padding(16).frame(maxWidth: 640).frame(maxWidth: .infinity)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Color(.systemGroupedBackground))
            .trackKeyboard($keyboardVisible)
            .safeAreaInset(edge: .bottom) {
                if !keyboardVisible { Button { Task { await model.save() } } label: {
                    HStack { if model.saving { ProgressView() }; Text("保存").frame(maxWidth: .infinity) }
                }
                .buttonStyle(.borderedProminent).tint(Color.vBrand).controlSize(.large).buttonBorderShape(.capsule).disabled(model.saving)
                .padding(.horizontal, 16).padding(.top, 10).padding(.bottom, 8)
                .background(.bar).overlay(alignment: .top) { Divider() } }
            }
            .toolbar { ToolbarItem(placement: .confirmationAction) {
                if keyboardVisible { Button("保存") { focus = false; Task { await model.save() } }.fontWeight(.semibold).disabled(model.saving) }
            } }
            .toolbar { ToolbarItemGroup(placement: .keyboard) {
                Button("+") { model.setAmount(model.amountText + "+") }
                Button("×") { model.setAmount(model.amountText + "×") }
                Spacer()
                Button("完成") { focus = false }
            } }
            .onChange(of: model.finished) { _, done in if done { dismiss() } }
            .sensoryFeedback(.success, trigger: model.finished)
        }

        private var categoryGrid: some View {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 8) {
                ForEach(Labels.expenseOrder, id: \.self) { k in
                    let on = model.category == k
                    Button { model.setCategory(k) } label: {
                        VStack(spacing: 4) {
                            Image(systemName: icon(k)).font(.title3)
                            Text(Labels.expense[k] ?? k).font(.caption2).lineLimit(1)
                        }
                        .frame(maxWidth: .infinity).padding(.vertical, 8)
                        .foregroundStyle(on ? Color.white : Color.primary)
                        .background(on ? Color.vExpense : Color(.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .buttonStyle(.plain).accessibilityAddTraits(on ? .isSelected : [])
                }
            }
        }

        private func icon(_ k: String) -> String {
            switch k {
            case "insurance": "shield.fill"; case "maintenance": "wrench.and.screwdriver.fill"; case "repair": "hammer.fill"
            case "inspection": "checklist"; case "tires": "circle.circle"; case "wash": "drop.fill"; case "parking": "parkingsign.circle.fill"
            case "toll": "road.lanes"; case "fine": "exclamationmark.triangle.fill"; case "accessory": "puzzlepiece.fill"
            case "loan": "banknote.fill"; default: "yensign.circle.fill"
            }
        }

        private var insurance: some View {
            VStack(alignment: .leading, spacing: 10) {
                Text("险种（填了各项金额会自动合计）").font(.caption).foregroundStyle(.secondary)
                ForEach(ExpenseFormModel.insuranceNames, id: \.self) { n in
                    HStack {
                        Text(n).frame(width: 64, alignment: .leading)
                        TextField("–", text: Binding(get: { model.insuranceItems[n] ?? "" }, set: { model.setInsurance(n, $0) })).keyboardType(.decimalPad)
                            .padding(8).background(Color(.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        Text("元").foregroundStyle(.secondary)
                    }
                }
                DatePicker("保险起期", selection: Binding(get: { model.periodStart ?? Date() }, set: { model.periodStart = $0 }), displayedComponents: .date)
                DatePicker("保险止期", selection: Binding(get: { model.periodEnd ?? Date() }, set: { model.periodEnd = $0 }), displayedComponents: .date)
                Text("保存后会自动更新「保险到期」提醒").font(.caption2).foregroundStyle(.secondary)
            }
        }

        private func field(_ title: String, _ unit: String, _ text: Binding<String>, keyboard: UIKeyboardType = .default, placeholder: String = "") -> some View {
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.caption).foregroundStyle(.secondary)
                HStack {
                    TextField(placeholder.isEmpty ? "–" : placeholder, text: text).keyboardType(keyboard)
                    if !unit.isEmpty { Text(unit).foregroundStyle(.secondary) }
                }
                .padding(10).background(Color(.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        }
    }
}
