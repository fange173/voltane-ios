import SwiftUI
import UIKit

struct ToastAction: Identifiable {
    let id = UUID()
    let label: String
    let run: @MainActor () async -> Void
}

struct ToastItem: Identifiable {
    let id = UUID()
    var text: String
    var sub: String = ""
    var actions: [ToastAction] = []
    var isError = false
}

/// 底部悬浮提示：最多两个按钮，4.5 秒后消失，出现时让 VoiceOver 播报。
@MainActor @Observable
final class ToastCenter {
    private(set) var items: [ToastItem] = []

    func show(_ text: String, sub: String = "", actions: [ToastAction] = [], isError: Bool = false) {
        let item = ToastItem(text: text, sub: sub, actions: Array(actions.prefix(2)), isError: isError)
        items.append(item)
        if items.count > 3 { items.removeFirst() }
        UIAccessibility.post(notification: .announcement, argument: sub.isEmpty ? text : "\(text)，\(sub)")
        Task { [id = item.id] in
            try? await Task.sleep(for: .seconds(4.5))
            dismiss(id)
        }
    }

    func error(_ error: Error) {
        show(error.localizedDescription, isError: true)
    }

    func dismiss(_ id: UUID) {
        withAnimation(.snappy) { items.removeAll { $0.id == id } }
    }
}
