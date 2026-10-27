import SwiftUI

/// 液态玻璃兼容层：iOS 26 及以上用系统玻璃，iOS 17–25 降级成系统材质。
/// 所有带 `#available(iOS 26` 的代码只写在这个目录里，功能页面只调用这里的 `v` 前缀接口。
private struct VGlassBackground<S: InsettableShape>: ViewModifier {
    let shape: S
    let tint: Color?
    let interactive: Bool
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    func body(content: Content) -> some View {
        if #available(iOS 26, *) {
            content.glassEffect(Glass.regular.tint(tint).interactive(interactive), in: shape)
        } else if reduceTransparency {
            content
                .background(Color(.secondarySystemBackground), in: shape)
                .overlay(shape.strokeBorder(Color(.separator), lineWidth: 0.5))
        } else {
            content
                .background(.regularMaterial, in: shape)
                .background((tint ?? .clear).opacity(0.12), in: shape)
                .overlay(shape.strokeBorder(Color(.separator), lineWidth: 0.5))
        }
    }
}

extension View {
    /// 悬浮在内容之上的控件层背景。
    func vGlass<S: InsettableShape>(in shape: S, tint: Color? = nil, interactive: Bool = false) -> some View {
        modifier(VGlassBackground(shape: shape, tint: tint, interactive: interactive))
    }

    func vGlass(tint: Color? = nil, interactive: Bool = false) -> some View {
        modifier(VGlassBackground(shape: Capsule(), tint: tint, interactive: interactive))
    }

    func vGlassID(_ id: some Hashable & Sendable, in namespace: Namespace.ID) -> some View {
        modifier(VGlassIDModifier(id: id, namespace: namespace))
    }

    /// 标签栏始终完整显示，滚动时不收起。
    func vTabBarFixed() -> some View {
        if #available(iOS 26, *) { return AnyView(self.tabBarMinimizeBehavior(.never)) } else { return AnyView(self) }
    }

    /// 滚动内容靠近顶部导航栏时的柔和边缘。
    func vScrollEdgeSoft() -> some View {
        if #available(iOS 26, *) { return AnyView(self.scrollEdgeEffectStyle(.soft, for: .top)) } else { return AnyView(self) }
    }

}

private struct VGlassIDModifier<ID: Hashable & Sendable>: ViewModifier {
    let id: ID
    let namespace: Namespace.ID

    func body(content: Content) -> some View {
        if #available(iOS 26, *) {
            content.glassEffectID(id, in: namespace)
        } else {
            content.matchedGeometryEffect(id: id, in: namespace)
        }
    }
}

/// 玻璃容器：iOS 26 上相邻玻璃元素会融合；旧系统原样排列。
struct VGlassContainer<Content: View>: View {
    var spacing: CGFloat = 8
    @ViewBuilder var content: Content

    var body: some View {
        if #available(iOS 26, *) {
            GlassEffectContainer(spacing: spacing) { content }
        } else {
            content
        }
    }
}

struct VGlassButtonStyle: PrimitiveButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        if #available(iOS 26, *) {
            Button(configuration).buttonStyle(.glass)
        } else {
            Button(configuration).buttonStyle(.bordered)
        }
    }
}

struct VGlassProminentButtonStyle: PrimitiveButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        if #available(iOS 26, *) {
            Button(configuration).buttonStyle(.glassProminent)
        } else {
            Button(configuration).buttonStyle(.borderedProminent)
        }
    }
}

extension PrimitiveButtonStyle where Self == VGlassButtonStyle {
    static var vGlass: VGlassButtonStyle { VGlassButtonStyle() }
}

extension PrimitiveButtonStyle where Self == VGlassProminentButtonStyle {
    static var vGlassProminent: VGlassProminentButtonStyle { VGlassProminentButtonStyle() }
}
