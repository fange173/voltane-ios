import SwiftUI
import UIKit

/// toast 放在单独的浮层窗口里，才能显示在 sheet 之上；窗口只接住 toast 本身的点击，其余触摸透传给下面的页面。
@MainActor
final class ToastWindowController {
    private var window: UIWindow?

    func install(app: AppModel) {
        guard window == nil,
              let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first else { return }
        let w = PassThroughWindow(windowScene: scene)
        let host = UIHostingController(rootView: ToastOverlay { [weak w] in w?.toastFrame = $0 }.environment(app))
        host.view.backgroundColor = .clear
        w.windowLevel = .normal + 1
        w.backgroundColor = .clear
        w.rootViewController = host
        w.isHidden = false
        window = w
    }
}

/// 浮层窗口的内容：跟随 App 的主题设置。
private struct ToastOverlay: View {
    @Environment(AppModel.self) private var app
    let onFrame: (CGRect) -> Void

    var body: some View {
        ToastHost(onFrame: onFrame)
            .padding(.bottom, 8)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            .preferredColorScheme(app.colorScheme)
            .tint(Color.vBrand)
    }
}

/// 只有落在 toast 区域内的触摸才由本窗口处理；SwiftUI 宿主视图对空白处也会返回子视图，不能靠 hitTest 结果判断。
private final class PassThroughWindow: UIWindow {
    var toastFrame: CGRect = .zero

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        guard toastFrame.contains(point) else { return nil }
        return super.hitTest(point, with: event)
    }
}
