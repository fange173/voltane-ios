import SwiftUI
import VoltaneKit

/// 输入框先写本地状态再同步给模型，快速连续输入时不会被模型回写的旧值冲掉字符；模型自己改值（自动推算）时才覆盖本地。
struct StableTextField: View {
    let prompt: String
    @Binding var text: String
    @State private var local = ""
    @State private var lastPushed: String?
    @State private var ready = false

    var body: some View {
        TextField(prompt, text: $local)
            .onAppear { local = text; ready = true }
            .onChange(of: local) { _, new in
                guard ready else { return }
                lastPushed = new
                if text != new { text = new }
            }
            .onChange(of: text) { _, new in
                if new != lastPushed && new != local { local = new }
                if new == local { lastPushed = nil }
            }
    }
}

/// 估算值的标记：次要色加「估」小标签。
struct EstimateTag: View {
    var body: some View {
        Text("估").font(.caption2.weight(.bold)).padding(.horizontal, 5).padding(.vertical, 1)
            .foregroundStyle(Color.vWarn).background(Color.vWarnSoft, in: Capsule())
            .accessibilityLabel("估算值")
    }
}

/// 带标题、单位的数字输入框；自动推算的值用次要色并带「估」标签。
struct NumberField: View {
    let title: String
    let unit: String
    var placeholder = ""
    @Binding var text: String
    var state: FieldState
    var keyboard: UIKeyboardType = .decimalPad
    var hint: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            HStack(spacing: 6) {
                StableTextField(prompt: placeholder.isEmpty ? "–" : placeholder, text: $text)
                    .keyboardType(keyboard).monospacedDigit()
                    .foregroundStyle(state.isAuto || state.showsEstimate ? Color.secondary : Color.primary)
                    .italic(state.isAuto || state.showsEstimate)
                if state.isAuto || state.showsEstimate { EstimateTag() }
                if !unit.isEmpty { Text(unit).font(.footnote).foregroundStyle(.secondary) }
            }
            .padding(10)
            .background(Color(.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            if let hint { Text(hint).font(.caption2).foregroundStyle(.secondary) }
        }
        .accessibilityElement(children: .contain)
    }
}

/// 由其他字段算出的只读值（如充电单价）：虚线框、次要颜色，不可编辑。
struct DerivedField: View {
    let title: String
    let unit: String
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            HStack(spacing: 6) {
                Text(text.isEmpty ? "自动计算" : text)
                    .monospacedDigit()
                    .foregroundStyle(text.isEmpty ? Color.secondary.opacity(0.6) : Color.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .lineLimit(1)
                if !unit.isEmpty { Text(unit).font(.footnote).foregroundStyle(.secondary) }
            }
            .padding(10)
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.secondary.opacity(0.35), style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
        }
        .accessibilityElement(children: .combine)
    }
}

/// 横向可滚动的胶囊单选。
struct ChipPicker<ID: Hashable>: View {
    let options: [(ID, String)]
    let selection: ID?
    var tone: Tone = .brand
    let onSelect: (ID) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(options, id: \.0) { id, label in
                    let on = selection == id
                    Button { onSelect(id) } label: {
                        Text(label).font(.subheadline.weight(on ? .semibold : .regular))
                            .padding(.horizontal, 12).padding(.vertical, 7)
                            .foregroundStyle(on ? Color.white : Color.primary)
                            .background(on ? tone.color : Color(.tertiarySystemGroupedBackground), in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(on ? .isSelected : [])
                }
            }
            .padding(.horizontal, 1)
        }
    }
}

/// 电量、油量百分比：默认显示「未填」，点击后出现滑块和微调；必须能回到「未填」，因为空值和 0 含义不同。
struct LevelField: View {
    let title: String
    var tone: Tone = .elec
    let state: FieldState
    let label: String
    var startValue: Double = 50
    var locked = false
    let onSet: (Double) -> Void
    let onClear: () -> Void

    var body: some View {
        let value = JSNumber.parse(state.text)
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title).font(.caption).foregroundStyle(.secondary)
                Spacer()
                if value != nil {
                    Text(label).font(.subheadline.weight(.semibold)).monospacedDigit()
                        .foregroundStyle(state.isAuto || state.showsEstimate ? Color.secondary : Color.primary)
                    if (state.isAuto || state.showsEstimate) && !locked { EstimateTag() }
                }
            }
            if let v = value, locked {
                Slider(value: .constant(min(max(v, 0), 100)), in: 0...100, step: 1).tint(tone.color).disabled(true)
                Label("充到上限，结束 SOC 固定", systemImage: "lock.fill").font(.caption).foregroundStyle(.secondary)
            } else if let v = value {
                Slider(value: Binding(get: { min(max(v, 0), 100) }, set: { onSet($0.rounded()) }), in: 0...100, step: 1)
                    .tint(tone.color)
                    .sensoryFeedback(.selection, trigger: Int(v / 10))
                HStack(spacing: 12) {
                    Stepper("", onIncrement: { onSet(min(100, v.rounded() + 1)) }, onDecrement: { onSet(max(0, v.rounded() - 1)) })
                        .labelsHidden().fixedSize()
                    Spacer()
                    Button { onClear() } label: { Label("清除", systemImage: "xmark.circle.fill").font(.footnote) }
                        .buttonStyle(.plain).foregroundStyle(.secondary).accessibilityLabel("清除\(title)")
                }
            } else {
                Button { onSet(startValue) } label: {
                    Text("未填").frame(maxWidth: .infinity, alignment: .leading).padding(10)
                        .foregroundStyle(.secondary)
                        .background(Color(.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(title)，未填，点按设置")
            }
        }
    }
}

/// 按车辆油表方式输入油量：按格用分段或步进；知道油箱容积时可在百分比和升之间切换，默认用上次选的单位。
struct FuelGaugeField: View {
    let title: String
    let field: FormField
    @Bindable var model: RecordFormModel

    var body: some View {
        let v = model.state.vehicle
        let st = model.state.state(field)
        switch v.fuelGaugeMode {
        case "bars" where (v.fuelGaugeBars ?? 0) > 0:
            let n = v.fuelGaugeBars!
            let cur = JSNumber.parse(st.text).map { Int(($0 / 100 * Double(n)).rounded()) }
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(title).font(.caption).foregroundStyle(.secondary); Spacer()
                    if cur != nil { Text(model.state.levelLabel(field)).font(.subheadline.weight(.semibold)); if st.isAuto || st.showsEstimate { EstimateTag() } }
                }
                if n <= 8 {
                    HStack(spacing: 4) {
                        ForEach(1...n, id: \.self) { k in
                            Button { model.tapBar(field, k) } label: {
                                RoundedRectangle(cornerRadius: 4, style: .continuous)
                                    .fill((cur ?? 0) >= k ? Color.vFuel : Color(.tertiarySystemGroupedBackground)).frame(height: 28)
                            }
                            .buttonStyle(.plain).accessibilityLabel("第 \(k) 格")
                        }
                    }
                    Text("亮了几格就点第几格，再点一次清除").font(.caption2).foregroundStyle(.secondary)
                } else {
                    Stepper(cur.map { "\($0)/\(n) 格" } ?? "未填", onIncrement: { model.tapBar(field, min(n, (cur ?? 0) + 1)) },
                            onDecrement: { model.tapBar(field, max(1, (cur ?? 1) - 1)) })
                }
            }
        case _ where (v.tankCapacityL ?? 0) > 0:
            VStack(alignment: .trailing, spacing: 4) {
                Picker("油量单位", selection: Binding(get: { model.state.fuelUnit }, set: { model.setFuelUnit($0) })) {
                    Text("%").tag("pct")
                    Text("L").tag("liters")
                }
                .pickerStyle(.segmented).frame(width: 96).controlSize(.mini)
                if model.state.fuelUnit == "liters" {
                    NumberField(title: title, unit: "L", placeholder: "仪表显示的剩余升数",
                                text: Binding(get: { model.state.litersText(field) }, set: { model.setLiters(field, $0) }), state: st)
                } else {
                    level(st)
                }
            }
        default:
            level(st)
        }
    }

    private func level(_ st: FieldState) -> some View {
        LevelField(title: title, tone: .fuel, state: st, label: model.state.levelLabel(field), startValue: model.state.prefill.lastFuelPct ?? 50,
                   onSet: { model.setLevel(field, $0) }, onClear: { model.clearLevel(field) })
    }
}
