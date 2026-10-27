import SwiftUI
import UIKit

/// 键盘是否弹出：弹出时底部的保存栏收起，避免和键盘工具栏的「完成」叠在一起，保存改放导航栏右上角。
struct KeyboardVisibility: ViewModifier {
    @Binding var visible: Bool

    func body(content: Content) -> some View {
        content
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in withAnimation(.snappy) { visible = true } }
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in withAnimation(.snappy) { visible = false } }
    }
}

extension View {
    func trackKeyboard(_ visible: Binding<Bool>) -> some View { modifier(KeyboardVisibility(visible: visible)) }
}
