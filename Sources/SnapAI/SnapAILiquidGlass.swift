import AppKit
import SwiftUI
import SnapAILogic

// MARK: - Liquid Glass 基础设施（macOS 26+，低版本自动回退）
//
// 设计约束（全项目统一）：
// 1. 结构性 chrome（窗口标题栏、工具栏、footer、历史列表列）一律透明——只留
//    内容，由窗口/面板自身的材质提供 backdrop。禁止再引入新的不透明色块。
// 2. 需要抬升的内容（卡片、输入框、代码块）走 glassCard/gfield 修饰符：
//    macOS 26+ 用 Liquid Glass，低版本回退到现有 Surface 语义色。
// 3. 信息密度处理：供应商端点只显示 host；API Key 健康只显示计数摘要，
//    永不显示 Key 明文/掩码（见 AIProvider.displayHost、Diagnostics.apiKeyHealth）。
// 4. 数据面 Divider 一律删除；仅保留控件内部/菜单内部的语义分隔。

/// macOS 26 Liquid Glass 是否可用。调用方永远走此开关，不要散写 #available。
enum SnapAILiquidGlass {
    static var isAvailable: Bool {
        if #available(macOS 26, *) { return true }
        return false
    }
}

private struct SnapAIGlassCardModifier: ViewModifier {
    var radius: CGFloat
    var interactive: Bool

    func body(content: Content) -> some View {
        if #available(macOS 26, *) {
            content
                .glassEffect(
                    interactive ? .regular.interactive() : .regular,
                    in: RoundedRectangle(cornerRadius: radius, style: .continuous)
                )
        } else {
            content
                .background(SnapAIUI.Surface.content,
                            in: RoundedRectangle(cornerRadius: radius, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .stroke(SnapAIUI.Surface.border, lineWidth: 1)
                }
        }
    }
}

private struct SnapAIGlassFieldModifier: ViewModifier {
    var radius: CGFloat

    func body(content: Content) -> some View {
        if #available(macOS 26, *) {
            content
                .glassEffect(.regular, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
        } else {
            content
                .background(SnapAIUI.Surface.field,
                            in: RoundedRectangle(cornerRadius: radius, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .stroke(SnapAIUI.Surface.divider, lineWidth: 1)
                }
        }
    }
}

private struct SnapAIGlassPillModifier: ViewModifier {
    var tint: Color

    func body(content: Content) -> some View {
        if #available(macOS 26, *) {
            content
                .glassEffect(.regular.tint(tint.opacity(0.35)), in: .capsule)
        } else {
            content
                .background(tint.opacity(0.11), in: Capsule(style: .continuous))
        }
    }
}

extension View {
    /// 需要抬升的内容卡片（设置卡片、历史行、更新说明卡、onboarding 步骤）。
    /// macOS 26+ 为 Liquid Glass，低版本回退到 Surface.content + 边框。
    func snapAIGlassCard(radius: CGFloat = SnapAIUI.cardRadius,
                         interactive: Bool = false) -> some View {
        modifier(SnapAIGlassCardModifier(radius: radius, interactive: interactive))
    }

    /// 文本输入框/搜索框/编辑器表面。macOS 26+ 为 Liquid Glass，低版本回退 field。
    func snapAIGlassField(radius: CGFloat = SnapAIUI.controlRadius) -> some View {
        modifier(SnapAIGlassFieldModifier(radius: radius))
    }

    /// 胶囊形状态徽标。macOS 26+ 为 tinted glass，低版本回退到 tint 淡填充。
    func snapAIGlassPill(tint: Color) -> some View {
        modifier(SnapAIGlassPillModifier(tint: tint))
    }

    /// 结构性 chrome 透明化：标题栏、工具栏、footer、侧栏列表列统一用它，
    /// 只留排版，不再绘制任何背景色块。需要圆角裁剪时由调用方另行 clipShape。
    func snapAIChrome() -> some View {
        background(.clear)
    }
}

// MARK: - 滚动边缘效果（macOS 26+，低版本无操作）

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
    /// 滚动列表的边缘淡化。macOS 26+ 生效，低版本为无操作，保持行为一致。
    func snapAIScrollEdge() -> some View {
        modifier(SnapAIScrollEdgeModifier())
    }
}

// MARK: - 工具栏玻璃组（macOS 26+ 融合，低版本为普通 HStack）

/// 一组并排的操作按钮（如结果 footer 操作行）。macOS 26+ 用 GlassEffectContainer
/// 把组内 glass 元素融合成连续液态玻璃；低版本退化为等价 HStack，无视觉回归。
struct SnapAIGlassToolbarGroup<Content: View>: View {
    var spacing: CGFloat = 8
    @ViewBuilder var content: () -> Content

    var body: some View {
        Group {
            if #available(macOS 26, *) {
                GlassEffectContainer(spacing: spacing) {
                    HStack(spacing: spacing) {
                        content()
                    }
                }
            } else {
                HStack(spacing: spacing) {
                    content()
                }
            }
        }
    }
}

// MARK: - 侧栏毛玻璃（behind-window vibrancy）
//
// 参考 macOS 系统设置：左侧栏是 behind-window 的 .sidebar 毛玻璃（桌面透过来），
// 右侧详情区是不透明基底。SwiftUI 的 NavigationSplitView 侧栏本应自动获得该材质，
// 但当宿主 NSWindow 不透明时无法透出桌面。此处显式铺一层 behind-window 材质，
// 并由 WindowCoordinator 把设置窗口设为 isOpaque=false + clear 背景，保证真实透明。
struct SnapAIVisualEffect: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .sidebar
    var blendingMode: NSVisualEffectView.BlendingMode = .behindWindow

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
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
    /// 侧栏 behind-window 毛玻璃底。铺在侧栏内容最底层，桌面透过窗口显现。
    func snapAISidebarGlass() -> some View {
        background(SnapAIVisualEffect(material: .sidebar).ignoresSafeArea())
    }
}
