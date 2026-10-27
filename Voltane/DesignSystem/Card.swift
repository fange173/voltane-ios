import SwiftUI
import VoltaneKit

/// 内容卡片：圆角 20、内边距 16，背景用系统分组背景色。
struct Card<Content: View>: View {
    var padding: CGFloat = 16
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}

struct SectionTitle: View {
    let title: String
    var trailing: String?
    var action: (() -> Void)?

    var body: some View {
        HStack {
            Text(title).font(.headline)
            Spacer()
            if let trailing, let action { Button(trailing, action: action).font(.subheadline) }
        }
        .padding(.horizontal, 4)
    }
}

struct QualityBadge: View {
    let quality: String?
    var err: Double?

    var body: some View {
        if let quality, quality != "A" {
            let text = quality == "B" && err != nil ? "估 ±\(Fmt.num(err))" : (Labels.quality[quality] ?? quality)
            Text(text)
                .font(.caption2.weight(.bold))
                .padding(.horizontal, 6).padding(.vertical, 1)
                .foregroundStyle(Color.quality(quality))
                .background(Color.quality(quality).opacity(0.14), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                .accessibilityLabel("数据质量：\(Labels.quality[quality] ?? quality)")
        }
    }
}

struct Pill: View {
    let text: String
    var tone: Tone = .snapshot

    var body: some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 7).padding(.vertical, 2)
            .foregroundStyle(tone.text)
            .background(tone.soft, in: Capsule())
    }
}

struct IconBadge: View {
    let systemName: String
    var tone: Tone = .brand
    var size: CGFloat = 36

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: size * 0.46, weight: .semibold))
            .foregroundStyle(tone.text)
            .frame(width: size, height: size)
            .background(tone.soft, in: RoundedRectangle(cornerRadius: size * 0.3, style: .continuous))
            .accessibilityHidden(true)
    }
}

/// 大数字加单位，缺值显示「–」。
struct MetricView: View {
    let value: String
    var unit: String = ""
    var tone: Tone = .brand
    var caption: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            if let caption { Text(caption).font(.caption).foregroundStyle(.secondary) }
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value)
                    .font(.system(.title2, design: .rounded, weight: .bold))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .foregroundStyle(tone == .brand ? Color.primary : tone.text)
                    .lineLimit(1).minimumScaleFactor(0.7)
                if !unit.isEmpty { Text(unit).font(.footnote).foregroundStyle(.secondary) }
            }
        }
        .accessibilityElement(children: .combine)
    }
}
