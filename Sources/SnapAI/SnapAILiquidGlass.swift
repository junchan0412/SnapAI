import AppKit
import SwiftUI
import SnapAILogic

// MARK: - 原生材质与表面层级系统
//
// 层次规范：
// 1. 窗口基底：侧栏用 behind-window `.sidebar`，主内容区用 `.underWindowBackground`，
//    悬浮面板（快捷提问、结果浮窗、命令面板）用 `.popover` + 精致连续圆角描边。
// 2. 分组卡片（`snapAIGlassCard`）：静态表单与内容卡片采用半透明原生控件表面 + 细描边，
//    避免在嵌套内容上滥用折射玻璃导致视觉发糊；仅 `interactive == true` 时启用交互态玻璃。
// 3. 胶囊徽标与浮动工具条组（`snapAIGlassPill` / `SnapAIGlassToolbarGroup`）：在 macOS 26+
//    使用原生 Liquid Glass，低版本平滑回退到高对比轻填充。

enum SnapAILiquidGlass {
    static var isAvailable: Bool {
        if #available(macOS 26, *) { return true }
        return false
    }
}

private struct SnapAIGlassCardModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    var radius: CGFloat
    var interactive: Bool

    func body(content: Content) -> some View {
        if interactive, #available(macOS 26, *) {
            content
                .glassEffect(.regular.interactive(),
                             in: RoundedRectangle(cornerRadius: radius, style: .continuous))
        } else if interactive {
            content
                .background(.regularMaterial,
                            in: RoundedRectangle(cornerRadius: radius, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .strokeBorder(SnapAIUI.Surface.border, lineWidth: 0.75)
                }
        } else {
            let fillOpacity = colorScheme == .dark ? 0.065 : 0.78
            let baseFill = colorScheme == .dark
                ? Color.white.opacity(fillOpacity)
                : Color(nsColor: .controlBackgroundColor).opacity(fillOpacity)
            let borderOpacity = colorScheme == .dark ? 0.10 : 0.075
            content
                .background(baseFill,
                            in: RoundedRectangle(cornerRadius: radius, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .strokeBorder(Color.primary.opacity(borderOpacity), lineWidth: 0.75)
                }
        }
    }
}

private struct SnapAIGlassFieldModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    var radius: CGFloat

    func body(content: Content) -> some View {
        let fill = colorScheme == .dark
            ? Color.black.opacity(0.24)
            : Color(nsColor: .textBackgroundColor).opacity(0.92)
        let stroke = colorScheme == .dark
            ? Color.white.opacity(0.11)
            : Color.black.opacity(0.09)
        content
            .background(fill, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(stroke, lineWidth: 0.75)
            }
    }
}

private struct SnapAIGlassPillModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    var tint: Color

    func body(content: Content) -> some View {
        let fillOpacity = colorScheme == .dark ? 0.16 : 0.11
        let strokeOpacity = colorScheme == .dark ? 0.22 : 0.16
        content
            .background(tint.opacity(fillOpacity), in: Capsule(style: .continuous))
            .overlay {
                Capsule(style: .continuous)
                    .strokeBorder(tint.opacity(strokeOpacity), lineWidth: 0.6)
            }
    }
}

private struct SnapAIFloatingPanelSurfaceModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    var radius: CGFloat

    func body(content: Content) -> some View {
        let outerBorder = colorScheme == .dark
            ? Color.white.opacity(0.14)
            : Color.black.opacity(0.10)
        content
            .background {
                ZStack {
                    SnapAIVisualEffect(material: .popover, blendingMode: .behindWindow)
                    if colorScheme == .dark {
                        Color.black.opacity(0.14)
                    } else {
                        Color.white.opacity(0.32)
                    }
                }
                .allowsHitTesting(false)
            }
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(outerBorder, lineWidth: 0.85)
                    .allowsHitTesting(false)
            }
    }
}

extension View {
    /// 分组卡片表面（设置分组、提供商卡片、代码块等）。
    func snapAIGlassCard(radius: CGFloat = SnapAIUI.cardRadius,
                         interactive: Bool = false) -> some View {
        modifier(SnapAIGlassCardModifier(radius: radius, interactive: interactive))
    }

    /// 文本输入框/搜索框/编辑器表面。
    func snapAIGlassField(radius: CGFloat = SnapAIUI.controlRadius) -> some View {
        modifier(SnapAIGlassFieldModifier(radius: radius))
    }

    /// 胶囊形状态徽标。
    func snapAIGlassPill(tint: Color) -> some View {
        modifier(SnapAIGlassPillModifier(tint: tint))
    }

    /// 悬浮面板（快捷提问、结果浮窗、命令面板）统一毛玻璃圆角容器。
    func snapAIFloatingPanelSurface(radius: CGFloat = SnapAIUI.panelRadius) -> some View {
        modifier(SnapAIFloatingPanelSurfaceModifier(radius: radius))
    }

    /// 结构性透明容器，由底层窗口材质提供背景。
    func snapAIChrome() -> some View {
        background(.clear)
    }
}

// MARK: - 滚动边缘效果

private struct SnapAIScrollEdgeModifier: ViewModifier {
    func body(content: Content) -> some View {
        Group {
            if #available(macOS 26, *) {
                content.scrollEdgeEffectStyle(.soft, for: .all)
            } else {
                content
            }
        }
    }
}

extension View {
    func snapAIScrollEdge() -> some View {
        modifier(SnapAIScrollEdgeModifier())
    }
}

// MARK: - 工具栏操作组

struct SnapAIGlassToolbarGroup<Content: View>: View {
    var spacing: CGFloat = 6
    @ViewBuilder var content: () -> Content

    var body: some View {
        HStack(spacing: spacing) {
            content()
        }
    }
}

// MARK: - 原生毛玻璃（behind-window vibrancy）

private final class SnapAIBackdropView: NSVisualEffectView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

struct SnapAIVisualEffect: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .sidebar
    var blendingMode: NSVisualEffectView.BlendingMode = .behindWindow

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = SnapAIBackdropView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
        nsView.state = .active
    }
}

extension View {
    /// 侧栏 behind-window 毛玻璃底。
    func snapAISidebarGlass() -> some View {
        background(SnapAIVisualEffect(material: .sidebar).allowsHitTesting(false).ignoresSafeArea())
    }
}
