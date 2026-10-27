import SwiftUI
import VoltaneKit

/// 新车向导：基本信息 → 能源参数 → 怎么开始记 → 提醒，对应网页版 `wizardPage`。
struct VehicleWizardView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var st = VehicleWizardState()
    @State private var error: String?
    @State private var busy = false
    @State private var confirmLeave = false

    var body: some View {
        VStack(spacing: 0) {
            StepBar(titles: VehicleWizardState.stepTitles, current: st.step)
            Form {
                switch st.step {
                case 1: BasicStep(st: $st)
                case 2: EnergyStep(st: $st)
                case 3: StartStep(st: $st)
                default: ReminderStep(st: $st)
                }
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("添加车辆")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("取消") { if st.isPristine { dismiss() } else { confirmLeave = true } }
            }
        }
        .confirmationDialog("放弃添加这辆车？", isPresented: $confirmLeave, titleVisibility: .visible) {
            Button("放弃", role: .destructive) { dismiss() }
            Button("继续填写", role: .cancel) {}
        } message: { Text("已填的内容不会保存。") }
        .safeAreaInset(edge: .bottom, spacing: 0) { footer }
    }

    private var footer: some View {
        VStack(spacing: 8) {
            if let error { Label(error, systemImage: "exclamationmark.triangle.fill").font(.footnote).foregroundStyle(Color.vDanger).frame(maxWidth: .infinity, alignment: .leading) }
            HStack {
                if st.step > 1 { Button { error = nil; st.step -= 1 } label: { Label("上一步", systemImage: "chevron.left") }.buttonStyle(.bordered) }
                Spacer()
                if st.step > 1 && st.step < 4 { Button("跳过") { error = nil; st.step += 1 }.buttonStyle(.borderless) }
                Button { Task { await next() } } label: {
                    if busy { ProgressView().frame(minWidth: 56) } else { Text(st.step < 4 ? "下一步" : "完成").frame(minWidth: 56) }
                }
                .buttonStyle(.borderedProminent).disabled(busy)
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
        .background(.bar)
    }

    private func next() async {
        if let e = st.validate(step: st.step) { error = e; return }
        error = nil
        if st.step < 4 { st.step += 1; return }
        busy = true
        defer { busy = false }
        do {
            let v = try await app.client.send(try API.createVehicle(st.payload()))
            await app.loadVehicles()
            app.selectVehicle(v.id)
            app.bump()
            app.toasts.show("已添加「\(v.name)」", sub: "以后加油尽量加满、充电时填一下电量，能耗就会越来越准")
            app.finishPushed(.newVehicle, dismiss: dismiss)
        } catch { self.error = error.localizedDescription }
    }
}

private struct StepBar: View {
    let titles: [String]
    let current: Int

    var body: some View {
        HStack(spacing: 6) {
            ForEach(Array(titles.enumerated()), id: \.offset) { i, t in
                let n = i + 1
                VStack(spacing: 4) {
                    Capsule().fill(n <= current ? Color.vBrand : Color(.tertiarySystemFill)).frame(height: 4)
                    Text("\(n) \(t)").font(.caption2.weight(n == current ? .bold : .regular))
                        .foregroundStyle(n == current ? Color.primary : Color.secondary).lineLimit(1).minimumScaleFactor(0.8)
                }
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("第 \(current) 步，共 \(titles.count) 步：\(titles[current - 1])")
    }
}

// MARK: 第 1 步

private struct BasicStep: View {
    @Binding var st: VehicleWizardState

    var body: some View {
        Section {
            TextField("车名，如：秦PLUS、家里的车", text: $st.name)
            TextField("车牌（可选）", text: $st.plate)
            TextField("品牌型号（可选）", text: $st.model)
        }
        Section("车型") {
            ForEach(VehicleWizardState.energyTypes, id: \.self) { t in
                RadioRow(title: Labels.energy[t] ?? t, detail: VehicleWizardState.energyDesc[t],
                         systemImage: t == "bev" ? "bolt.fill" : (t == "ice" || t == "hev") ? "fuelpump.fill" : "car.fill",
                         selected: st.energyType == t) { st.energyType = t }
            }
        }
        Section("颜色") { ColorSwatches(color: $st.color) }
    }
}

// MARK: 第 2 步

private struct EnergyStep: View {
    @Binding var st: VehicleWizardState

    var body: some View {
        if st.hasFuel {
            Section {
                FormNumberRow(title: "油箱容积", unit: "L", placeholder: "如 48", text: $st.tank)
            } footer: { Text("用于「加满自动算油量」和油表读数换算，可查官方参数") }
        }
        if st.hasElec {
            Section {
                FormNumberRow(title: "电池可用容量", unit: "kWh", placeholder: "如 18.3", text: $st.battery)
                FormNumberRow(title: "平时充电上限", unit: "%", text: $st.chargeLimit, keyboard: .numberPad)
                Picker("常用充电方式", selection: $st.chargeType) {
                    ForEach(Labels.chargeOrder, id: \.self) { Text(Labels.charge[$0] ?? $0).tag($0) }
                }
            } footer: { Text("电池容量常见：18.3 / 26.6 / 46 / 60 / 75 kWh。不确定可以不填，充几次电后会自动校准") }
        }
        if st.hasFuel {
            Section {
                Picker("默认标号", selection: $st.fuelGrade) {
                    ForEach(Labels.fuelGrades, id: \.self) { Text(Labels.grade($0)).tag($0) }
                }
                Picker("油表显示方式", selection: Binding(get: { st.gaugeMode }, set: { st.setGaugeMode($0) })) {
                    Text("百分比").tag("pct"); Text("格数").tag("bars"); Text("升").tag("liters")
                }
                if st.gaugeMode == "bars" { FormNumberRow(title: "油表总格数", unit: "格", text: $st.gaugeBars, keyboard: .numberPad) }
            } footer: { Text("按「升」或「格数」输入需要填油箱容积，否则会退回按百分比") }
        }
        Section {
            Picker("记录习惯", selection: $st.recordStyle) { Text("精细").tag("detailed"); Text("简单").tag("simple") }
                .pickerStyle(.segmented)
        } header: { Text("记录习惯") } footer: { Text("精细：电量、油量放在表单显眼位置，能耗更准；简单：收进「更多」里") }
    }
}

// MARK: 第 3 步

private struct StartStep: View {
    @Binding var st: VehicleWizardState
    @State private var showDelivery = false
    @State private var showSummary = false
    private static let modes: [(VehicleWizardState.StartMode, String, String)] = [
        (.existing, "已经开了一段时间", "从现在开始记，以前的记录记得多少补多少，不补也能用"),
        (.new, "新车，刚提车", "从提车这一刻开始记"),
        (.skip, "以后再说", "第一条记录会自动作为起点"),
    ]

    var body: some View {
        Section {
            ForEach(Self.modes, id: \.0) { m, title, detail in
                RadioRow(title: title, detail: detail, selected: st.mode == m) { st.mode = m }
            }
        }
        if st.mode != .skip {
            Section {
                FormNumberRow(title: "当前里程 *", unit: "km", text: $st.currentOdo, keyboard: .numberPad)
                if st.hasFuel {
                    let u = st.gaugeUnit
                    FormNumberRow(title: "当前油量", unit: u.label, placeholder: u.placeholder, text: $st.currentFuel)
                }
                if st.hasElec { FormNumberRow(title: "当前电量", unit: "%", text: $st.currentSoc) }
            } header: { Text(st.mode == .new ? "提车时的状态" : "现在的状态") } footer: {
                Text("油量、电量不确定可以不填；填了的话，下次加油或充电时就能算出第一段能耗。")
            }
        }
        if st.mode == .existing {
            Section {
                DisclosureGroup("提车信息（记得就填，可跳过）", isExpanded: $showDelivery) {
                    Text("提车日期和提车里程都填了，才能算「提车至今」的里程和粗略能耗；二手车或记不清就跳过，不影响以后的记录。")
                        .font(.footnote).foregroundStyle(.secondary)
                    OptionalDateRow(title: "提车日期", date: $st.deliveryDate, upTo: LocalDateTime(date: Date()))
                    FormNumberRow(title: "提车里程", unit: "km", placeholder: "新车一般 0–50", text: $st.deliveryOdo, keyboard: .numberPad)
                    if st.hasFuel {
                        FormNumberRow(title: "出厂自带油", unit: "L", text: $st.factoryFuel)
                        FormNumberRow(title: "提车时加了", unit: "L", placeholder: "没加不填", text: $st.deliveryFillL)
                        FormNumberRow(title: "花了", unit: "元", text: $st.deliveryFillYuan)
                    }
                }
                DisclosureGroup("历史汇总（可选）", isExpanded: $showSummary) {
                    Text("之前没逐条记的加油、充电，知道大概总数就填，只用于花费统计和长期粗略能耗。来源：家充桩 App 累计度数、电费账单、支付宝/微信账单里搜「加油」「充电」。")
                        .font(.footnote).foregroundStyle(.secondary)
                    OptionalDateRow(title: "从哪天开始算", date: $st.summaryStart, upTo: LocalDateTime(date: Date()))
                    Text("不填就从提车日期第二天开始；没填提车日期时必须填").font(.caption).foregroundStyle(.secondary)
                    if st.hasFuel {
                        FormNumberRow(title: "加油合计", unit: "元", text: $st.summaryFuelYuan)
                        FormNumberRow(title: "或升数", unit: "L", text: $st.summaryFuelL)
                        FormNumberRow(title: "平均油价", unit: "元/L", placeholder: "7.5", text: $st.summaryFuelPrice)
                    }
                    if st.hasElec {
                        FormNumberRow(title: "充电合计", unit: "kWh", text: $st.summaryElecKwh)
                        FormNumberRow(title: "花了", unit: "元", text: $st.summaryElecYuan)
                        FormNumberRow(title: "平均电价", unit: "元/度", placeholder: "0.6", text: $st.summaryElecPrice)
                    }
                }
            }
        }
    }
}

// MARK: 第 4 步

private struct ReminderStep: View {
    @Binding var st: VehicleWizardState

    var body: some View {
        Section {
            Text("勾选需要的提醒，填上下次到期的日期或里程（填一个就行，都填时哪个先到算哪个）。周期是常见值，请按你的保养手册改，留空就是一次性提醒。以后在「提醒」页随时可以改。")
                .font(.footnote).foregroundStyle(.secondary)
        }
        ForEach(WizardReminderTemplate.all) { t in
            let draft = Binding(get: { st.reminders[t.key] ?? seed(t) }, set: { st.reminders[t.key] = $0 })
            Section {
                Toggle(t.title, isOn: draft.on.animation())
                if draft.wrappedValue.on {
                    if let hint = t.hint { Text(hint).font(.caption).foregroundStyle(.secondary) }
                    OptionalDateRow(title: "下次到期日期", date: draft.dueDate)
                    if t.useKm {
                        FormNumberRow(title: "下次到期里程", unit: "km", placeholder: JSNumber.parse(st.currentOdo).map { "当前 \(Fmt.km($0))" } ?? "–",
                                      text: draft.dueOdo, keyboard: .numberPad)
                    }
                    if t.hasInterval {
                        FormNumberRow(title: "周期（月）", unit: "月", placeholder: "一次性", text: draft.months, keyboard: .numberPad)
                        if t.useKm { FormNumberRow(title: "周期（里程）", unit: "km", placeholder: "不按里程", text: draft.km, keyboard: .numberPad) }
                        Text("周期以保养手册为准，完成后会按实际完成的日期和里程顺延。").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private func seed(_ t: WizardReminderTemplate) -> WizardReminderDraft {
        var copy = st
        return copy.reminder(t)
    }
}
