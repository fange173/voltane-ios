import SwiftUI
import VoltaneKit

/// 时间线条目的显示文案，对应网页版 `records.js` 的 itemTitle / itemRow。
struct TimelineDisplay {
    let item: TimelineItem
    var vehicles: [Vehicle]

    private var vehicle: Vehicle? { vehicles.first { $0.id == item.vehicleId } }

    var title: String {
        switch item {
        case .expense(let e):
            return (Labels.expense[e.category] ?? "费用") + ((e.title ?? "").isEmpty ? "" : " · \(e.title!)")
        case .record(let r):
            switch r.kind {
            case "fuel":
                return "\(Labels.grade(r.fuelGrade).isEmpty ? "加油" : Labels.grade(r.fuelGrade)) \(r.fuelLiters.map { Fmt.num($0) + "L" } ?? "")".trimmingCharacters(in: .whitespaces)
            case "charge":
                let base = Labels.chargeLabel(r.chargeType) ?? "充电"
                if r.isInProgress { return "\(base) · 充电中" }
                return "\(base) \(r.chargeKwh.map { Fmt.num($0) + "kWh" } ?? "")".trimmingCharacters(in: .whitespaces)
            default:
                var parts: [String] = []
                if let s = r.socBeforePct { parts.append("电 \(Fmt.num(s, 0))%") }
                if let f = r.fuelLevelBeforePct { parts.append("油 \(Fmt.fuelLevel(f, vehicle: vehicle))") }
                return (Labels.snapshotTags[r.snapshotTag ?? ""] ?? "快照") + (parts.isEmpty ? "" : " · " + parts.joined(separator: " "))
            }
        }
    }

    var systemImage: String {
        switch item {
        case .expense(let e):
            switch e.category {
            case "insurance": "shield.fill"; case "maintenance", "repair": "wrench.and.screwdriver.fill"
            case "parking": "parkingsign.circle.fill"; case "wash": "drop.fill"; default: "yensign.circle.fill"
            }
        case .record(let r):
            switch r.kind { case "fuel": "fuelpump.fill"; case "charge": "bolt.fill"; default: "gauge.with.dots.needle.33percent" }
        }
    }

    var tone: Tone {
        switch item {
        case .expense: .expense
        case .record(let r): r.kind == "fuel" ? .fuel : r.kind == "charge" ? .elec : .snapshot
        }
    }

    var cents: Int? {
        switch item { case .expense(let e): e.amountCents; case .record(let r): r.amountCents }
    }

    func subtitle(now: LocalDateTime = LocalDateTime(date: Date()), showDate: Bool = true) -> String {
        var parts: [String] = []
        let t = item.occurredAt
        parts.append(showDate ? "\(Fmt.relDay(t, now: now)) \(t.timeText)" : t.timeText)
        switch item {
        case .record(let r):
            if let o = r.odometerKm, !r.isOdometerEstimated { parts.append("\(Fmt.km(o)) km") } else if r.isOdometerEstimated { parts.append("里程估算") }
            if let p = r.placeName, !p.isEmpty { parts.append(p) }
        case .expense(let e):
            if let o = e.odometerKm { parts.append("\(Fmt.km(o)) km") }
            if let v = e.vendor, !v.isEmpty { parts.append(v) }
        }
        return parts.joined(separator: " · ")
    }

    var tags: [(String, Tone)] {
        guard case .record(let r) = item else { return [] }
        var out: [(String, Tone)] = []
        if r.kind == "fuel" && r.fuelIsFull == true { out.append(("满", .fuel)) }
        if r.source == "auto_fix" { out.append(("自动补", .fuel)) }
        return out
    }

    /// 补录的记录很常见，只用小图标标出，不占文字徽章的位置。
    var isBackfill: Bool {
        guard case .record(let r) = item else { return false }
        return r.source == "backfill" || r.source == "import"
    }

    var badges: [Record.Badge] {
        switch item { case .record(let r): r.badges ?? []; case .expense(let e): e.badges ?? [] }
    }

    var creator: UserBrief? {
        switch item { case .record(let r): r.createdBy; case .expense(let e): e.createdBy }
    }
}

struct BadgeView: View {
    let badge: Record.Badge

    var body: some View {
        if badge.kind == "idle", let d = badge.perDay {
            Pill(text: "\(badge.anomaly != nil ? "● " : "")\(Fmt.num(d)) kWh/天", tone: badge.anomaly != nil ? .fuel : .snapshot)
                .accessibilityLabel("静置耗电 \(Fmt.num(d)) kWh/天")
        } else if let p = badge.per100 {
            let unit = badge.energy == "elec" ? "kWh" : badge.energy == "combined" ? "L 折合" : "L"
            let text = "\(badge.anomaly != nil ? "● " : "")\(Fmt.num(p)) \(unit)\(badge.quality != "A" ? "·估" : "")"
            Pill(text: text, tone: badge.anomaly != nil ? .fuel : badge.energy == "fuel" ? .fuel : .elec)
        }
    }
}

struct AvatarView: View {
    let user: UserBrief?
    var size: CGFloat = 20

    var body: some View {
        if let user {
            Text(String(user.name.prefix(1)))
                .font(.system(size: size * 0.5, weight: .bold)).foregroundStyle(.white)
                .frame(width: size, height: size).background(Color(hex: user.color), in: Circle())
                .accessibilityLabel(user.name)
        }
    }
}

/// 列表里的一行：图标、标题与标签、副标题、金额、能耗徽章。
struct RecordRow: View {
    @Environment(AppModel.self) private var app
    let item: TimelineItem
    var showDate = true
    var pending = false

    var body: some View {
        let d = TimelineDisplay(item: item, vehicles: app.vehicles)
        HStack(spacing: 12) {
            IconBadge(systemName: d.systemImage, tone: d.tone, size: 40)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 5) {
                    Text(d.title).font(.body.weight(.medium)).lineLimit(1)
                    ForEach(Array(d.tags.enumerated()), id: \.offset) { Pill(text: $0.element.0, tone: $0.element.1) }
                    if d.isBackfill {
                        Image(systemName: "clock.arrow.circlepath").font(.caption2).foregroundStyle(.tertiary).accessibilityLabel("补录")
                    }
                    if pending { Pill(text: "待同步", tone: .fuel) }
                }
                Text(d.subtitle(showDate: showDate)).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 6)
            VStack(alignment: .trailing, spacing: 3) {
                if d.cents != nil || d.tone != .snapshot {
                    Text(Fmt.money(d.cents)).font(.body.weight(.semibold)).monospacedDigit()
                        .foregroundStyle(d.cents == nil ? .tertiary : .primary)
                }
                HStack(spacing: 4) {
                    ForEach(Array(d.badges.enumerated()), id: \.offset) { BadgeView(badge: $0.element) }
                    if (app.vehicles.first { $0.id == item.vehicleId }?.memberCount ?? 1) > 1 {
                        AvatarView(user: d.creator)
                    }
                }
            }
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}
