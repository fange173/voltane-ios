import SwiftUI
import VoltaneKit

/// 加油、充电、快照表单，字段推算逻辑在 VoltaneKit 的 RecordFormState，这里只负责界面。
struct RecordFormView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    let mode: RecordFormModel.Mode
    @State private var model: RecordFormModel?

    var body: some View {
        NavigationStack {
            Group {
                if let model { FormBody(model: model) } else { ProgressView() }
            }
            .navigationTitle(model?.title ?? "")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } } }
        }
        .task {
            if model == nil { model = RecordFormModel(app: app, mode: mode) }
            await model?.load()
        }
    }
}

struct PendingEditView: View {
    let item: OutboxItem

    var body: some View {
        if item.kind == .record { RecordFormView(mode: .pending(item)) } else { ExpenseFormView(mode: .pending(item)) }
    }
}

private struct FormBody: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @Bindable var model: RecordFormModel
    @FocusState private var focus: FormField?
    @State private var keyboardVisible = false

    private var st: RecordFormState { model.state }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                if case .create = model.mode, model.availableKinds.count > 1 { kindPicker }
                if !model.loaded { ProgressView().padding(40) } else { fields }
            }
            .padding(16)
            .frame(maxWidth: 640).frame(maxWidth: .infinity)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Color(.systemGroupedBackground))
        .trackKeyboard($keyboardVisible)
        .safeAreaInset(edge: .bottom) { if !keyboardVisible { saveBar } }
        .toolbar { keyboardBar
            ToolbarItem(placement: .confirmationAction) {
                if keyboardVisible { Button(model.isFinish ? "结束充电" : "保存") { focus = nil; Task { await model.save() } }.fontWeight(.semibold).disabled(model.saving || !model.loaded) }
            } }
        .confirmationDialog("可能重复", isPresented: Binding(get: { model.duplicateMessage != nil }, set: { if !$0 { model.duplicateMessage = nil } }), titleVisibility: .visible) {
            Button("仍然保存") { Task { await model.confirmDuplicate() } }
            Button("取消", role: .cancel) {}
        } message: { Text("\(model.duplicateMessage ?? "")\n仍然保存吗？") }
        .sheet(isPresented: $model.placePicker) { PlacePickerSheet(places: st.prefill.places) { model.selectPlace($0) }.presentationDetents([.medium, .large]) }
        .onChange(of: model.finished) { _, done in if done { dismiss() } }
        .sensoryFeedback(.success, trigger: model.finished)
        .sensoryFeedback(.selection, trigger: st.flag(.fuelIsFull))
    }

    // MARK: 区块

    private var kindPicker: some View {
        Picker("类型", selection: Binding(get: { st.kind }, set: { k in Task { await model.switchKind(k) } })) {
            ForEach(model.availableKinds, id: \.self) { k in
                Text(k == .fuel ? "加油" : k == .charge ? "充电" : "快照").tag(k)
            }
        }
        .pickerStyle(.segmented)
    }

    @ViewBuilder private var fields: some View {
        if st.kind == .charge, case .create = model.mode { startChargeCallout }
        if case .create = model.mode, let last = st.prefill.last { lastRow(last) }
        if st.kind == .snapshot { Label("出发前、长时间停车前后记一下，可以把哨兵等静置耗电单独统计出来。电量和油量记得哪个填哪个，不确定的留空。", systemImage: "info.circle").font(.footnote).foregroundStyle(.secondary) }
        timeCard
        odometerCard
        switch st.kind {
        case .fuel: fuelCard
        case .charge: chargeCard
        case .snapshot: snapshotCard
        }
        if st.kind != .snapshot { placeCard }
        moreCard
        noteCard
        if let e = model.error { Text(e).font(.footnote).foregroundStyle(Color.vDanger).frame(maxWidth: .infinity, alignment: .leading).accessibilityLabel("错误：\(e)") }
    }

    private var startChargeCallout: some View {
        HStack(spacing: 10) {
            Image(systemName: "powerplug.fill").foregroundStyle(Color.vElec)
            Text("正在充电？先记开始，拔枪时再补结束").font(.subheadline)
            Spacer(minLength: 4)
            Button("开始充电") { Task { await model.save(startOnly: true) } }.buttonStyle(.vGlass).tint(Color.vElec).controlSize(.small)
        }
        .padding(12).background(Color.vElecSoft, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func lastRow(_ last: Record) -> some View {
        HStack {
            Text("上次：\(Fmt.date(last.occurredAt)) \(last.placeName ?? "")").font(.caption).foregroundStyle(.secondary)
            Spacer()
            Button { model.copyLast() } label: { Label("同上次", systemImage: "doc.on.doc") }.font(.caption)
        }
    }

    private var timeCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                DatePicker("时间", selection: Binding(get: { st.occurredAt.date() }, set: { model.setTime(LocalDateTime(date: $0)) }),
                           in: ...Date().addingTimeInterval(86400), displayedComponents: [.date, .hourAndMinute])
                    .datePickerStyle(.compact)
                ChipPicker(options: [("now", "现在"), ("h1", "1 小时前"), ("morning", "今天早上"), ("yesterday", "昨天")], selection: nil as String?) { k in
                    var d = Date()
                    let cal = Calendar.current
                    if k == "h1" { d = d.addingTimeInterval(-3600) }
                    if k == "morning" { d = cal.date(bySettingHour: 8, minute: 0, second: 0, of: d) ?? d }
                    if k == "yesterday" { d = cal.date(byAdding: .day, value: -1, to: d) ?? d }
                    model.setTime(LocalDateTime(date: d))
                }
            }
        }
    }

    private var odometerCard: some View {
        let hint = st.odoHint
        return Card {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("里程").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Text(hint.text).font(.caption).monospacedDigit().foregroundStyle(hint.warn ? Color.vDanger : Color.secondary)
                }
                HStack {
                    StableTextField(prompt: hint.placeholder, text: Binding(get: { st.text(.odometer) }, set: { model.input(.odometer, $0) }))
                        .keyboardType(.numberPad).font(.title3.weight(.semibold)).monospacedDigit()
                        .focused($focus, equals: .odometer).disabled(st.flag(.odoUnknown))
                    Text("km").foregroundStyle(.secondary)
                }
                .padding(10).background(Color(.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                HStack {
                    Toggle("按本次行驶输入", isOn: Binding(get: { st.flag(.tripMode) }, set: { model.setFlag(.tripMode, $0) }))
                    Toggle("不确定里程", isOn: Binding(get: { st.flag(.odoUnknown) }, set: { model.setFlag(.odoUnknown, $0) }))
                }
                .font(.footnote).toggleStyle(.switch).controlSize(.mini)
            }
        }
    }

    private func numberField(_ title: String, _ unit: String, _ f: FormField, hint: String? = nil, placeholder: String = "") -> some View {
        NumberField(title: title, unit: unit, placeholder: placeholder, text: Binding(get: { st.text(f) }, set: { model.input(f, $0) }),
                    state: st.state(f), keyboard: f.isMoney ? .numbersAndPunctuation : .decimalPad, hint: hint)
            .focused($focus, equals: f)
    }

    private var tripleFields: some View {
        VStack(spacing: 10) {
            let fuel = st.kind == .fuel
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 10) { triple(fuel) }
                VStack(spacing: 10) { triple(fuel) }
            }
        }
    }

    @ViewBuilder private func triple(_ fuel: Bool) -> some View {
        numberField(fuel ? "加油量" : "充电量", fuel ? "L" : "kWh", fuel ? .fuelLiters : .chargeKwh)
        numberField("花费金额", "元", .amount)
        if fuel { numberField("单价", "元/L", .fuelUnitPrice) } else { DerivedField(title: "单价", unit: "元/度", text: st.text(.chargeUnitPrice)) }
    }

    private var fuelCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("标号").font(.caption).foregroundStyle(.secondary)
                    ChipPicker(options: Labels.fuelGrades.map { ($0, Labels.grade($0)) }, selection: st.fuelGrade, tone: .fuel) { model.chip(.grade, $0) }
                }
                tripleFields
                Toggle(isOn: Binding(get: { st.flag(.fuelIsFull) }, set: { model.setFlag(.fuelIsFull, $0) })) {
                    VStack(alignment: .leading) { Label("加满", systemImage: "fuelpump.fill").font(.body.weight(.semibold)); Text("加满之间的油耗最准").font(.caption).foregroundStyle(.secondary) }
                }
                .tint(Color.vFuel)
                if vehicleHasElecInMain {
                    LevelField(title: "当前电量 SOC", state: st.state(.socBefore), label: st.levelLabel(.socBefore), startValue: st.prefill.lastSoc ?? 50,
                               onSet: { model.setLevel(.socBefore, $0) }, onClear: { model.clearLevel(.socBefore) })
                    Text("填写后混动能耗更准").font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
    }

    private var vehicleHasElecInMain: Bool { model.vehicle.hasElec }

    private var chargeCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("方式").font(.caption).foregroundStyle(.secondary)
                    ChipPicker(options: Labels.chargeOrder.map { ($0, Labels.charge[$0] ?? $0) }, selection: Labels.chargeKey(st.chargeType), tone: .elec) { model.chip(.chargeType, $0) }
                }
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: 12) { socPair }
                    VStack(spacing: 12) { socPair }
                }
                Toggle(isOn: Binding(get: { st.flag(.chargeToLimit) }, set: { model.setFlag(.chargeToLimit, $0) })) {
                    VStack(alignment: .leading) { Text("充到上限（\(Fmt.num(model.vehicle.chargeLimitPct ?? 100, 0))%）").font(.body); Text("勾选后结束 SOC 按上限算").font(.caption).foregroundStyle(.secondary) }
                }
                .tint(Color.vElec)
                tripleFields
                if let note = st.tariffNote { Text(note).font(.caption).foregroundStyle(.secondary) }
            }
        }
    }

    @ViewBuilder private var socPair: some View {
        LevelField(title: "开始 SOC", state: st.state(.socBefore), label: st.levelLabel(.socBefore), startValue: st.prefill.lastSoc ?? 50,
                   onSet: { model.setLevel(.socBefore, $0) }, onClear: { model.clearLevel(.socBefore) })
        LevelField(title: "结束 SOC", state: st.state(.socAfter), label: st.levelLabel(.socAfter), startValue: 100, locked: st.socAfterLocked,
                   onSet: { model.setLevel(.socAfter, $0) }, onClear: { model.clearLevel(.socAfter) })
    }

    private var snapshotCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 14) {
                if model.vehicle.hasElec {
                    LevelField(title: "电量 SOC", state: st.state(.socBefore), label: st.levelLabel(.socBefore), startValue: st.prefill.lastSoc ?? 50,
                               onSet: { model.setLevel(.socBefore, $0) }, onClear: { model.clearLevel(.socBefore) })
                }
                if model.vehicle.hasFuel { FuelGaugeField(title: "油量", field: .fuelBefore, model: model) }
                VStack(alignment: .leading, spacing: 6) {
                    Text("标签").font(.caption).foregroundStyle(.secondary)
                    ChipPicker(options: snapshotTagOptions, selection: st.snapshotTag, tone: .brand) { model.chip(.snapshotTag, $0) }
                }
            }
        }
    }

    /// 提车、记账起点这类特殊标签只在编辑已有记录时保留，不作为新建时的选项。
    private var snapshotTagOptions: [(String, String)] {
        var tags = Labels.snapshotChoices
        if let t = st.snapshotTag, !tags.contains(t) { tags.append(t) }
        return tags.map { ($0, Labels.snapshotTags[$0] ?? $0) }
    }

    /// 「不选」、前 6 个常用地点、当前已选但不在其中的地点、「其他」。
    private var placeOptions: [(String, String)] {
        let top = Array(st.prefill.places.prefix(6))
        var options: [(String, String)] = [("", "不选")] + top.map { ("\($0.id ?? -1)", $0.name) }
        if let p = st.place, p.id == nil || !top.contains(where: { $0.id == p.id }) { options.append((p.id.map(String.init) ?? "tmp", p.name)) }
        return options + [("__more", "＋ 其他…")]
    }

    private var placeCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("地点").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button { Task { await model.locateNow() } } label: { Label("定位", systemImage: "location") }.font(.caption)
                }
                ChipPicker(options: placeOptions, selection: st.place.map { $0.id.map(String.init) ?? "tmp" } ?? "") { id in
                    if id == "__more" { model.placePicker = true }
                    else if id.isEmpty { model.selectPlace(nil) }
                    else if let p = st.prefill.places.first(where: { String($0.id ?? -1) == id }) { model.selectPlace(p) }
                }
                if let p = st.place, p.id == nil {
                    Button { Task { await model.saveCurrentPlace() } } label: { Label("存为常用地点「\(p.name)」", systemImage: "mappin.and.ellipse") }
                        .font(.footnote).buttonStyle(.bordered).buttonBorderShape(.capsule).tint(Color.vBrand)
                }
            }
        }
    }

    private var moreCard: some View {
        Card {
            DisclosureGroup("更多", isExpanded: $model.showMore) {
                VStack(alignment: .leading, spacing: 14) {
                    if st.kind == .fuel {
                        FuelGaugeField(title: "加油前油量", field: .fuelBefore, model: model)
                        if !st.flag(.fuelIsFull) { FuelGaugeField(title: "加油后油量", field: .fuelAfter, model: model) }
                        numberField("其他费用（洗车等）", "元", .extraFee, hint: "计入花费，不计入油价")
                    }
                    if st.kind == .charge {
                        if model.vehicle.hasFuel { FuelGaugeField(title: "当前油量", field: .fuelBefore, model: model) }
                        HStack(alignment: .top, spacing: 10) {
                            numberField("时长", "分钟", .chargeMinutes)
                            numberField("电费", "元", .energyFee)
                            numberField("服务费", "元", .serviceFee)
                        }
                        numberField("占位/停车费", "元", .extraFee, hint: "计入花费，不计入电价")
                    }
                    if st.kind != .snapshot {
                        Toggle(isOn: Binding(get: { st.flag(.missedBefore) }, set: { model.setFlag(.missedBefore, $0) })) {
                            VStack(alignment: .leading) { Text("上次\(st.kind == .fuel ? "加油" : "充电")没记"); Text("勾选后跨过这里的能耗不计算，避免算错").font(.caption).foregroundStyle(.secondary) }
                        }
                    }
                }
                .padding(.top, 10)
            }
        }
        .onAppear { if let r = recordForMore, RecordFormState.hasMoreContent(r) { model.showMore = true } }
    }

    private var recordForMore: Record? {
        switch model.mode { case .edit(let r, _): r; default: nil }
    }

    private var noteCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 8) {
                Text("备注").font(.caption).foregroundStyle(.secondary)
                if !st.prefill.recentNotes.isEmpty {
                    ChipPicker(options: st.prefill.recentNotes.map { ($0, $0) }, selection: nil as String?) { n in
                        model.setNote(st.note.isEmpty ? n : (st.note.contains(n) ? st.note : st.note + " " + n))
                    }
                }
                TextField("可不填", text: Binding(get: { st.note }, set: { model.setNote($0) }), axis: .vertical)
                    .lineLimit(2...5).padding(10)
                    .background(Color(.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        }
    }

    // MARK: 底部与键盘

    private var saveBar: some View {
        HStack(spacing: 12) {
            if case .create = model.mode {
                Button { Task { await model.save(again: true) } } label: { Text("保存并再记").frame(maxWidth: .infinity) }
                    .buttonStyle(.bordered).tint(Color.vBrand).disabled(model.saving)
                    .frame(maxWidth: 150)
            }
            Button { Task { await model.save() } } label: {
                HStack { if model.saving { ProgressView() }; Text(model.isFinish ? "结束充电" : "保存").fontWeight(.semibold) }.frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent).tint(Color.vBrand).disabled(model.saving || !model.loaded)
        }
        .controlSize(.large)
        .buttonBorderShape(.capsule)
        .padding(.horizontal, 16).padding(.top, 10).padding(.bottom, 8)
        .background(.bar)
        .overlay(alignment: .top) { Divider() }
    }

    @ToolbarContentBuilder private var keyboardBar: some ToolbarContent {
        ToolbarItemGroup(placement: .keyboard) {
            if focus == .amount || focus == .energyFee || focus == .serviceFee || focus == .extraFee, let f = focus {
                Button("+") { model.input(f, st.text(f) + "+") }
                Button("×") { model.input(f, st.text(f) + "×") }
                if f == .amount, let c = st.prefill.last?.amountCents {
                    Button("同上次") { model.input(.amount, (Decimal(c) / 100).plainString) }
                }
            }
            Spacer()
            Button("完成") { focus = nil }
        }
    }
}

/// 选择地点：搜索常用地点，或直接输入只记在这条记录里的新地点名。
struct PlacePickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    let places: [Place]
    let onPick: (Place) -> Void
    @State private var query = ""

    var body: some View {
        NavigationStack {
            List {
                let t = query.trimmingCharacters(in: .whitespaces)
                if !t.isEmpty && !places.contains(where: { $0.name == t }) {
                    Button { onPick(Place(id: nil, name: t)); dismiss() } label: {
                        VStack(alignment: .leading) { Text("使用「\(t)」"); Text("只记在这条记录里").font(.caption).foregroundStyle(.secondary) }
                    }
                }
                ForEach(places.filter { t.isEmpty || $0.name.contains(t) }) { p in
                    Button { onPick(p); dismiss() } label: {
                        VStack(alignment: .leading) { Text(p.name); if let c = p.useCount, c > 0 { Text("用过 \(c) 次").font(.caption).foregroundStyle(.secondary) } }
                    }
                }
                if places.isEmpty && t.isEmpty { Text("还没有常用地点，直接输入名称即可").foregroundStyle(.secondary) }
            }
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "搜索或输入新地点名称")
            .navigationTitle("选择地点").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } } }
        }
    }
}
