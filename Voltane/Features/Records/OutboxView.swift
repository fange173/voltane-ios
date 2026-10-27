import SwiftUI
import VoltaneKit

/// 待同步的离线记录：可以逐条编辑或丢弃，联网后自动重发。
struct OutboxView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    let vehicleId: Int
    @State private var items: [OutboxItem] = []

    var body: some View {
        List {
            if items.isEmpty {
                ContentUnavailableView("没有待同步的记录", systemImage: "checkmark.icloud", description: Text("离线时新建的记录和费用会先存在这里，联网后自动同步。"))
                    .listRowBackground(Color.clear)
            }
            ForEach(items) { item in
                Button { app.sheet = .pendingEdit(item) } label: {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(item.label).font(.body.weight(.medium))
                        Text("\(item.queuedAt.formatted(date: .abbreviated, time: .shortened)) 保存在本机").font(.caption).foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(.plain)
                .swipeActions { Button("丢弃", role: .destructive) { Task { await app.outbox.remove(item.id); await refresh() } } }
            }
        }
        .navigationTitle("待同步")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("关闭") { dismiss() } }
            ToolbarItem(placement: .primaryAction) { Button("立即同步") { Task { await app.flushOutbox(); await refresh() } }.disabled(items.isEmpty) }
        }
        .task(id: app.outboxCount) { await refresh() }
    }

    private func refresh() async {
        items = await app.outbox.items(vehicleId: vehicleId)
        await app.refreshOutboxCount()
    }
}
