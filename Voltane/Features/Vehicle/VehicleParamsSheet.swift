import SwiftUI
import VoltaneKit

/// 车辆参数编辑，对应网页版 `editVehicle`。
struct VehicleParamsSheet: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    let vehicle: Vehicle
    @State private var draft: VehicleParamsDraft
    @State private var error: String?
    @State private var busy = false

    init(vehicle: Vehicle) {
        self.vehicle = vehicle
        _draft = State(initialValue: VehicleParamsDraft(vehicle: vehicle))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("车名", text: $draft.name)
                    TextField("车牌", text: $draft.plate)
                    TextField("品牌型号", text: $draft.model)
                }
                Section("颜色") { ColorSwatches(color: $draft.color) }
                Section {
                    if vehicle.hasFuel { FormNumberRow(title: "油箱容积", unit: "L", text: $draft.tank) }
                    if vehicle.hasElec {
                        FormNumberRow(title: "电池可用容量", unit: "kWh", text: $draft.battery)
                        FormNumberRow(title: "充电上限", unit: "%", text: $draft.chargeLimit, keyboard: .numberPad)
                        Picker("常用充电方式", selection: $draft.chargeType) {
                            ForEach(Labels.chargeOrder, id: \.self) { Text(Labels.charge[$0] ?? $0).tag($0) }
                        }
                    }
                    if vehicle.hasFuel {
                        Picker("默认标号", selection: $draft.fuelGrade) {
                            ForEach(Labels.fuelGrades, id: \.self) { Text(Labels.grade($0)).tag($0) }
                        }
                        Picker("油表显示方式", selection: $draft.gaugeMode) {
                            Text("百分比").tag("pct"); Text("格数").tag("bars"); Text("升").tag("liters")
                        }
                        FormNumberRow(title: "油表总格数", unit: "格", placeholder: "格数显示时填", text: $draft.gaugeBars, keyboard: .numberPad)
                    }
                    Picker("记录习惯", selection: $draft.recordStyle) { Text("精细").tag("detailed"); Text("简单").tag("simple") }
                } footer: {
                    Text("记录习惯：精细会把电量、油量放在表单显眼位置，能耗更准；简单收进「更多」里。")
                }
                Section {
                    DisclosureGroup("提车信息（可选）") {
                        OptionalDateRow(title: "提车日期", date: $draft.deliveryDate, upTo: LocalDateTime(date: Date()))
                        FormNumberRow(title: "提车里程", unit: "km", placeholder: "新车一般 0–50", text: $draft.deliveryOdo, keyboard: .numberPad)
                        Text("提车日期和提车里程都填了，才能算「提车至今」。中途开始记、记不清可以一直不填；以后想起来了也可以在这里补。")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                    DisclosureGroup("计算设置") {
                        FormNumberRow(title: "最小段里程", unit: "km", text: $draft.minSegmentKm)
                        FormNumberRow(title: "电能折算系数", unit: "kWh/L", text: $draft.kwhPerL)
                        if vehicle.hasFuel {
                            FormNumberRow(title: "油表读数误差", unit: "%", text: $draft.gaugeErrPct)
                            Toggle("没有两次加满时用油表读数估算", isOn: $draft.allowGaugeAnchor)
                        }
                        Text("最小段里程：短于这个里程的段合并到下一段。电能折算系数用来算等效油耗。油表读数误差：车机能精确到 1% 的可以填 2。")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }
                FormErrorSection(message: error)
            }
            .navigationTitle("车辆参数")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    if busy { ProgressView() } else { Button("保存") { Task { await save() } } }
                }
            }
        }
    }

    private func save() async {
        if let e = draft.validate() { error = e; return }
        busy = true
        defer { busy = false }
        do {
            _ = try await app.client.send(try API.updateVehicle(id: vehicle.id, draft.payload(for: vehicle)))
            if let c = draft.deliveryChange(for: vehicle) {
                _ = try await app.client.send(try API.fixDelivery(vehicleId: vehicle.id, odometerKm: c.odometerKm, deliveryDate: c.date))
            }
            await app.reloadAfterVehicleChange()
            app.toasts.show("已保存，能耗已按新参数重新计算")
            dismiss()
        } catch { self.error = error.localizedDescription }
    }
}

/// 数据体检里「修正提车信息」。
struct DeliverySheet: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    let vehicle: Vehicle
    @State private var date: LocalDateTime?
    @State private var odo = ""
    @State private var error: String?
    @State private var busy = false

    init(vehicle: Vehicle, issue: VehicleHealth.Issue) {
        self.vehicle = vehicle
        _date = State(initialValue: issue.deliveryDate.map { OptionalDateRow.day($0.date()) })
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    OptionalDateRow(title: "提车日期", date: $date, upTo: LocalDateTime(date: Date()))
                    FormNumberRow(title: "提车里程", unit: "km", placeholder: "新车一般 0–50", text: $odo, keyboard: .numberPad)
                } footer: {
                    Text("会同时修改「提车」快照和提车当天的加油记录。不记得提车里程的话，可以把这两条记录删掉，从记账起点开始算也完全没问题。")
                }
                FormErrorSection(message: error)
            }
            .navigationTitle("修正提车信息")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    if busy { ProgressView() } else { Button("保存") { Task { await save() } } }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func save() async {
        guard let o = JSNumber.parse(odo.trimmingCharacters(in: .whitespaces)) else { error = "请填写提车里程"; return }
        busy = true
        defer { busy = false }
        do {
            _ = try await app.client.send(try API.fixDelivery(vehicleId: vehicle.id, odometerKm: o, deliveryDate: date))
            await app.reloadAfterVehicleChange()
            app.toasts.show("已修正提车里程，能耗和里程已重新计算")
            dismiss()
        } catch { self.error = error.localizedDescription }
    }
}

/// 历史 / 周期汇总的新增与编辑。
struct SummarySheet: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    let vehicle: Vehicle
    let existing: PeriodSummary?
    @State private var draft: SummaryDraft
    @State private var error: String?
    @State private var busy = false
    @State private var confirmDelete = false

    init(vehicle: Vehicle, existing: PeriodSummary?) {
        self.vehicle = vehicle
        self.existing = existing
        _draft = State(initialValue: existing.map { SummaryDraft($0) } ?? SummaryDraft())
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    DateRow(title: "开始日期", date: $draft.startDate)
                    DateRow(title: "结束日期", date: $draft.endDate)
                    Picker("填写方式", selection: $draft.mode) {
                        Text("补充没记的部分").tag("extra"); Text("按总数（自动扣除已记录）").tag("total")
                    }
                } footer: {
                    Text("一段时间内没有逐条记录的补能，按合计填写。只用于花费统计和长期粗略能耗，不影响精确能耗段。")
                }
                if vehicle.hasFuel {
                    Section("加油") {
                        FormNumberRow(title: "加油升数", unit: "L", text: $draft.fuelLiters)
                        FormNumberRow(title: "加油金额", unit: "元", text: $draft.fuelYuan)
                        FormNumberRow(title: "平均油价", unit: "元/L", placeholder: "只填金额时用", text: $draft.fuelPrice)
                    }
                }
                if vehicle.hasElec {
                    Section("充电") {
                        FormNumberRow(title: "充电度数", unit: "kWh", text: $draft.elecKwh)
                        FormNumberRow(title: "充电金额", unit: "元", text: $draft.elecYuan)
                        FormNumberRow(title: "平均电价", unit: "元/度", placeholder: "只填金额时用", text: $draft.elecPrice)
                    }
                }
                if let d = existing?.diff {
                    Section("与逐条记录的对比") {
                        let rec = [vehicle.hasFuel ? "加油 \(Fmt.num(d.recordedFuelL))L" : nil, vehicle.hasElec ? "充电 \(Fmt.num(d.recordedElecKwh))kWh" : nil].compactMap { $0 }
                        let diff = [vehicle.hasFuel ? "\(Fmt.num(d.fuelL ?? 0))L" : nil, vehicle.hasElec ? "\(Fmt.num(d.elecKwh ?? 0))kWh" : nil].compactMap { $0 }
                        LabeledContent("同期已逐条记录", value: rec.joined(separator: " "))
                        LabeledContent("计入的补差", value: diff.joined(separator: " "))
                    }
                }
                Section { TextField("备注", text: $draft.note) }
                FormErrorSection(message: error)
                if existing != nil {
                    Section { Button("删除这条汇总", role: .destructive) { confirmDelete = true } }
                }
            }
            .navigationTitle(existing == nil ? "添加汇总" : "编辑汇总")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    if busy { ProgressView() } else { Button("保存") { Task { await save() } } }
                }
            }
            .confirmationDialog("删除这条汇总？", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("删除", role: .destructive) { Task { await delete() } }
            }
        }
    }

    private func save() async {
        if let e = draft.validate() { error = e; return }
        busy = true
        defer { busy = false }
        do {
            let body = draft.payload(vehicle: vehicle, version: existing?.version)
            if let existing { _ = try await app.client.send(try API.updateSummary(id: existing.id, body)) }
            else { _ = try await app.client.send(try API.createSummary(body)) }
            app.bump()
            app.toasts.show("已保存汇总")
            dismiss()
        } catch { self.error = error.localizedDescription }
    }

    private func delete() async {
        guard let existing else { return }
        do {
            _ = try await app.client.send(API.deleteSummary(id: existing.id))
            app.bump()
            dismiss()
        } catch { self.error = error.localizedDescription }
    }
}
