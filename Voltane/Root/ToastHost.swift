import SwiftUI

/// 底部悬浮提示的显示层，放在单独的浮层窗口里（见 `ToastWindowController`），在标签栏和 sheet 之上。
struct ToastHost: View {
    @Environment(AppModel.self) private var app
    /// toast 所占区域（窗口坐标），浮层窗口据此决定哪些触摸透传。
    var onFrame: (CGRect) -> Void = { _ in }

    var body: some View {
        VStack(spacing: 8) {
            ForEach(app.toasts.items) { item in
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.text).font(.subheadline.weight(.semibold)).foregroundStyle(item.isError ? Color.vDanger : Color.primary)
                        if !item.sub.isEmpty { Text(item.sub).font(.caption).foregroundStyle(.secondary) }
                    }
                    Spacer(minLength: 4)
                    ForEach(item.actions) { action in
                        Button(action.label) {
                            app.toasts.dismiss(item.id)
                            Task { await action.run() }
                        }
                        .font(.subheadline.weight(.semibold))
                        .buttonStyle(.plain)
                        .foregroundStyle(Color.vBrand)
                    }
                }
                .padding(.horizontal, 16).padding(.vertical, 12)
                .vGlass(in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                .padding(.horizontal, 16)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .onTapGesture { app.toasts.dismiss(item.id) }
                .accessibilityElement(children: .combine)
            }
        }
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { onFrame($0) }
        .padding(.bottom, 84)
        .animation(.snappy, value: app.toasts.items.count)
        .allowsHitTesting(!app.toasts.items.isEmpty)
    }
}
