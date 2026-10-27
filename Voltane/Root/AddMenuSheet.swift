import SwiftUI
import VoltaneKit

/// 标签栏中间「＋」弹出的记录菜单：按车型只显示可用的补能类型，充电中时优先给出「结束充电」。
struct AddMenuSheet: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var charging: Record?

    var body: some View {
        NavigationStack {
            Group {
                if let v = app.currentVehicle, v.canEdit { grid(v) }
                else {
                    ContentUnavailableView(app.currentVehicle?.isArchived == true ? "车辆已归档" : "只能查看", systemImage: "lock.fill",
                                           description: Text(app.currentVehicle == nil ? "请先添加或加入一辆车。" : "你在这辆车上没有记录权限。"))
                }
            }
            .navigationTitle("记一笔").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("关闭") { dismiss() } } }
        }
        .task {
            guard let id = app.currentVehicleId else { return }
            let ep = API.overview(vehicleId: id)
            if let c = await app.repository.cached(ep) { charging = c.value.inProgress.first }
            if let r = try? await app.repository.fetch(ep) { charging = r.value.inProgress.first }
        }
    }

    private func grid(_ v: Vehicle) -> some View {
        var tiles: [(String, String, String, Tone, () -> Void)] = []
        if let r = charging {
            tiles.append(("结束充电", "充电中，补齐结束时的数据", "checkmark.circle.fill", .elec, { go(.editRecord(r, finish: true)) }))
        }
        if v.hasFuel { tiles.append(("加油", "满到满算油耗", "fuelpump.fill", .fuel, { go(.record(kind: .fuel, vehicleId: v.id)) })) }
        if v.hasElec && charging == nil { tiles.append(("充电", "支持分两步记", "bolt.fill", .elec, { go(.record(kind: .charge, vehicleId: v.id)) })) }
        tiles.append(("状态快照", "停车前后记一下电量", "gauge.with.dots.needle.33percent", .snapshot, { go(.record(kind: .snapshot, vehicleId: v.id)) }))
        tiles.append(("记一笔", "保险、保养、停车…", "yensign.circle.fill", .expense, { go(.expense(vehicleId: v.id)) }))
        return ScrollView {
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                ForEach(Array(tiles.enumerated()), id: \.offset) { _, t in
                    Button(action: t.4) {
                        HStack(spacing: 12) {
                            IconBadge(systemName: t.2, tone: t.3, size: 44)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(t.0).font(.headline)
                                Text(t.1).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(14).frame(maxWidth: .infinity)
                        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(16)
        }
        .background(Color(.systemGroupedBackground))
    }

    private func go(_ next: ActiveSheet) {
        dismiss()
        Task {
            try? await Task.sleep(for: .milliseconds(350))
            app.sheet = next
        }
    }
}
