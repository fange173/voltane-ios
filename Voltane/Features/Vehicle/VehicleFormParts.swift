import SwiftUI
import VoltaneKit

/// Form 里的一行数字输入：标题在左，输入和单位在右。
struct FormNumberRow: View {
    let title: String
    var unit = ""
    var placeholder = "–"
    @Binding var text: String
    var keyboard: UIKeyboardType = .decimalPad

    var body: some View {
        HStack {
            Text(title)
            Spacer(minLength: 12)
            TextField(placeholder, text: $text)
                .keyboardType(keyboard).multilineTextAlignment(.trailing).monospacedDigit()
            if !unit.isEmpty { Text(unit).foregroundStyle(.secondary) }
        }
    }
}

/// 可以留空的日期行：未填时显示「选择日期」，选了之后可以清除。
struct OptionalDateRow: View {
    let title: String
    @Binding var date: LocalDateTime?
    var upTo: LocalDateTime?

    var body: some View {
        if let d = date {
            HStack {
                DatePicker(title, selection: Binding(get: { d.date() }, set: { date = Self.day($0) }),
                           in: ...(upTo?.date() ?? .distantFuture), displayedComponents: .date)
                Button { date = nil } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }
                    .buttonStyle(.borderless).accessibilityLabel("清除\(title)")
            }
        } else {
            HStack {
                Text(title)
                Spacer()
                Button("选择日期") { date = Self.day(min(Date(), upTo?.date() ?? Date())) }.buttonStyle(.borderless)
            }
        }
    }

    static func day(_ d: Date) -> LocalDateTime {
        let t = LocalDateTime(date: d)
        return LocalDateTime(year: t.year, month: t.month, day: t.day, hasTime: false)
    }
}

/// 必填的日期行（汇总的起止日期）。
struct DateRow: View {
    let title: String
    @Binding var date: LocalDateTime

    var body: some View {
        DatePicker(title, selection: Binding(get: { date.date() }, set: { date = OptionalDateRow.day($0) }), displayedComponents: .date)
    }
}

struct ColorSwatches: View {
    @Binding var color: String

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(VehicleParamsDraft.colors, id: \.self) { c in
                    Button { color = c } label: {
                        Circle().fill(Color(hex: c)).frame(width: 30, height: 30)
                            .overlay { if color == c { Image(systemName: "checkmark").font(.footnote.bold()).foregroundStyle(.white) } }
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("颜色 \(c)").accessibilityAddTraits(color == c ? .isSelected : [])
                }
            }
            .padding(.vertical, 2)
        }
    }
}

/// 带说明的单选行，用于车型、开始方式、角色。
struct RadioRow: View {
    let title: String
    var detail: String?
    var systemImage: String?
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                if let systemImage { Image(systemName: systemImage).frame(width: 24).foregroundStyle(Color.vBrand) }
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).foregroundStyle(.primary)
                    if let detail { Text(detail).font(.caption).foregroundStyle(.secondary) }
                }
                Spacer()
                if selected { Image(systemName: "checkmark").foregroundStyle(Color.vBrand).fontWeight(.semibold) }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

struct FormErrorSection: View {
    let message: String?

    var body: some View {
        if let message, !message.isEmpty {
            Section { Label(message, systemImage: "exclamationmark.triangle.fill").foregroundStyle(Color.vDanger).font(.footnote) }
        }
    }
}

extension Vehicle {
    var gradeOptions: [(String, String)] { Labels.fuelGrades.map { ($0, Labels.grade($0)) } }
}
