import SwiftUI
import AppKit
import SnapAILogic

enum SnapAIUI {
    static let panelRadius: CGFloat = 16
    static let cardRadius: CGFloat = 12
    static let controlRadius: CGFloat = 8
    static let compactPadding: CGFloat = 12
    static let sectionPadding: CGFloat = 16

    static let quietFillOpacity: Double = 0.025
    static let regularFillOpacity: Double = 0.045
    static let selectedFillOpacity: Double = 0.10
    static let strokeOpacity: Double = 0.08
    static let focusStrokeOpacity: Double = 0.42
    static let minimumHitTarget: CGFloat = 32

    // MARK: - 间距阶(统一各界面留白,避免硬编码)
    static let tightSpacing: CGFloat = 8
    static let standardSpacing: CGFloat = 12
    static let looseSpacing: CGFloat = 20
    static let edgePadding: CGFloat = 20

    // MARK: - 字体阶(清晰层级,取代散落的 .headline/.caption 直写)
    enum Typography {
        static let windowTitle = Font.system(size: 26, weight: .semibold)
        static let panelTitle = Font.system(size: 17, weight: .semibold)
        static let sectionTitle = Font.system(size: 14, weight: .semibold)
        static let sectionLabel = Font.system(size: 12, weight: .medium)
        static let bodyText = Font.system(size: 14)
        static let metaText = Font.system(size: 12)
        static let toolbarLabel = Font.system(size: 12, weight: .medium)
        static let keycap = Font.system(size: 11, weight: .medium, design: .monospaced)
    }

    // MARK: - 语义表面(统一浅色/深色模式下的层次)
    // 结构性区域统一用 canvas 窗口基底,消除标题栏、工具栏、footer 与正文之间的接缝色差;
    // 仅真正需要抬升的内容(content/field:文本编辑器、输入框、卡片、代码块)使用文本背景色并配边框强调层次。
    enum Surface {
        static let canvas = Color(nsColor: .windowBackgroundColor)
        static let content = Color(nsColor: .textBackgroundColor)
        static let field = Color(nsColor: .textBackgroundColor)
        static let control = Color.primary.opacity(regularFillOpacity)
        static let quiet = Color.primary.opacity(quietFillOpacity)
        static let selected = Color.accentColor.opacity(selectedFillOpacity)
        static let divider = Color(nsColor: .separatorColor).opacity(0.55)
        static let border = divider
        static let focus = Color.accentColor.opacity(focusStrokeOpacity)
    }

    // MARK: - 语义状态色(取代散落的 .green/.orange/.red 硬编码)
    enum StatusColor {
        static let success = Color(nsColor: .systemGreen)
        static let warning = Color(nsColor: .systemOrange)
        static let error = Color(nsColor: .systemRed)
        static let info = Color.accentColor
        static let neutral = Color.secondary

        static func tint(for kind: ResultOperationFeedback.Kind) -> Color {
            switch kind {
            case .success: return success
            case .warning: return warning
            case .error: return error
            }
        }
    }
}

@MainActor
final class SnapAITransientState<Value>: ObservableObject {
    @Published private(set) var value: Value?
    private var dismissWorkItem: DispatchWorkItem?

    func show(_ value: Value, autoDismiss: TimeInterval) {
        dismissWorkItem?.cancel()
        self.value = value

        guard autoDismiss > 0 else { return }
        let workItem = DispatchWorkItem { [weak self] in
            self?.value = nil
            self?.dismissWorkItem = nil
        }
        dismissWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + autoDismiss, execute: workItem)
    }

    func clear() {
        dismissWorkItem?.cancel()
        dismissWorkItem = nil
        value = nil
    }
}

struct SnapAIStatusPill: View {
    var title: String
    var systemImage: String
    var tint: Color = .secondary
    var filled: Bool = false

    var body: some View {
        Label {
            Text(title).foregroundStyle(.primary)
        } icon: {
            Image(systemName: systemImage).foregroundStyle(tint)
        }
            .font(SnapAIUI.Typography.sectionLabel)
            .lineLimit(1)
            .truncationMode(.middle)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .snapAIGlassPill(tint: filled ? tint : .secondary)
    }
}

struct SnapAIIconButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    var size: CGFloat = SnapAIUI.minimumHitTarget
    var circular: Bool = true

    func makeBody(configuration: Configuration) -> some View {
        SnapAIIconButtonBody(label: configuration.label,
                             isPressed: configuration.isPressed,
                             isEnabled: isEnabled,
                             size: size,
                             circular: circular)
    }
}

private struct SnapAIIconButtonBody: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isFocused) private var isFocused
    let label: ButtonStyleConfiguration.Label
    let isPressed: Bool
    let isEnabled: Bool
    var size: CGFloat
    var circular: Bool
    @State private var isHovered = false

    var body: some View {
        let fill: Double = isPressed ? 0.12 : (isHovered ? 0.075 : 0)
        label
            .font(.system(size: 13, weight: .semibold))
            .frame(width: max(size, SnapAIUI.minimumHitTarget),
                   height: max(size, SnapAIUI.minimumHitTarget))
            .foregroundStyle(isEnabled ? (isHovered ? Color.primary : Color.secondary) : Color.secondary.opacity(0.45))
            .background {
                Group {
                    if circular {
                        Circle().fill(Color.primary.opacity(fill))
                    } else {
                        RoundedRectangle(cornerRadius: SnapAIUI.controlRadius, style: .continuous)
                            .fill(Color.primary.opacity(fill))
                    }
                }
            }
            .contentShape(Rectangle())
            .overlay {
                RoundedRectangle(cornerRadius: circular ? size / 2 : SnapAIUI.controlRadius,
                                 style: .continuous)
                    .stroke(isFocused ? SnapAIUI.Surface.focus : .clear, lineWidth: 2)
            }
            .onHover { isHovered = $0 }
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: isHovered)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.1), value: isPressed)
    }
}

// MARK: - 主按钮样式(用于结果浮窗错误恢复、设置等场景的主操作)

/// 用主色调填充的强调按钮,在多个并列操作中明确「主操作」。
struct SnapAIPrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.isFocused) private var isFocused
    var tint: Color = .accentColor

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.callout.weight(.semibold))
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .foregroundStyle(.white)
            .background {
                RoundedRectangle(cornerRadius: SnapAIUI.controlRadius, style: .continuous)
                    .fill(tint.opacity(isEnabled ? (configuration.isPressed ? 0.8 : 1) : 0.4))
            }
            .contentShape(Rectangle())
            .overlay {
                RoundedRectangle(cornerRadius: SnapAIUI.controlRadius + 2, style: .continuous)
                    .stroke(isFocused ? SnapAIUI.Surface.focus : .clear, lineWidth: 2)
                    .padding(-3)
            }
    }
}

struct SnapAISecondaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.isFocused) private var isFocused

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.callout.weight(.medium))
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .foregroundStyle(isEnabled ? Color.primary : Color.secondary)
            .background(Color.primary.opacity(configuration.isPressed ? 0.12 : 0.055),
                        in: RoundedRectangle(cornerRadius: SnapAIUI.controlRadius))
            .overlay {
                RoundedRectangle(cornerRadius: SnapAIUI.controlRadius)
                    .stroke(isFocused ? SnapAIUI.Surface.focus : SnapAIUI.Surface.border,
                            lineWidth: isFocused ? 2 : 1)
            }
            .contentShape(Rectangle())
    }
}

// MARK: - 语义状态徽标(取代散落的手写 pill)

struct SnapAISemanticPill: View {
    enum Tone {
        case success, warning, error, info, neutral
        var color: Color {
            switch self {
            case .success: return SnapAIUI.StatusColor.success
            case .warning: return SnapAIUI.StatusColor.warning
            case .error: return SnapAIUI.StatusColor.error
            case .info: return SnapAIUI.StatusColor.info
            case .neutral: return SnapAIUI.StatusColor.neutral
            }
        }
    }

    let title: String
    let systemImage: String
    let tone: Tone

    var body: some View {
        SnapAIStatusPill(title: title, systemImage: systemImage, tint: tone.color, filled: true)
    }
}

struct SnapAIKeycap: View {
    let text: String

    var body: some View {
        Text(text)
            .font(SnapAIUI.Typography.keycap)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 5)
            .frame(minWidth: 20, minHeight: 20)
            .background(SnapAIUI.Surface.control,
                        in: RoundedRectangle(cornerRadius: 4, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .stroke(SnapAIUI.Surface.divider, lineWidth: 0.5)
            }
            .accessibilityLabel("快捷键 \(text)")
    }
}

// MARK: - 破坏性操作二次确认(统一设置/历史中的删除与清空)

private struct SnapAIConfirmDestructiveModifier: ViewModifier {
    @Binding var isPresented: Bool
    let title: String
    let message: String
    let action: () -> Void

    func body(content: Content) -> some View {
        content.confirmationDialog(
            title,
            isPresented: $isPresented,
            titleVisibility: .visible
        ) {
            Button(title, role: .destructive, action: action)
            Button("取消", role: .cancel) {}
        } message: {
            if !message.isEmpty { Text(message) }
        }
    }
}

extension View {
    /// 绑定一个 Bool 状态:当其为 true 时弹出系统确认对话框,确认后执行 action。
    func snapAIConfirmDestructive(isPresented: Binding<Bool>,
                                  title: String,
                                  message: String = "",
                                  action: @escaping () -> Void) -> some View {
        modifier(SnapAIConfirmDestructiveModifier(isPresented: isPresented,
                                                  title: title,
                                                  message: message,
                                                  action: action))
    }
}

// MARK: - 流式生成进度条(收敛分散的「生成中」弱信号为单一强主视觉)

struct SnapAIStreamingProgressBar: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            if reduceMotion {
                Rectangle()
                    .fill(Color.accentColor.opacity(0.5))
            } else {
                ProgressView()
                    .progressViewStyle(.linear)
                    .controlSize(.mini)
            }
        }
        .frame(height: 2)
        .clipped()
        .accessibilityHidden(true)
    }
}

// MARK: - 不完整结果标记(取消/出错时提示当前为部分结果)

struct SnapAIIncompleteResultBanner: View {
    let title: String
    let systemImage: String
    var onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: systemImage)
                .foregroundStyle(SnapAIUI.StatusColor.warning)
            Text(title)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 4)
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .frame(width: 18, height: 18)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("关闭提示")
        }
        .font(.caption)
        .foregroundStyle(.primary)
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        .background(SnapAIUI.StatusColor.warning.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: SnapAIUI.cardRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: SnapAIUI.cardRadius, style: .continuous)
                .stroke(SnapAIUI.StatusColor.warning.opacity(0.2), lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(title)
    }
}

// MARK: - 瞬时非模态提示(#bug2:取代「未检测到选中文字」阻塞式模态 alert)

struct SnapAITransientNoticeBanner: View {
    let title: String
    var onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(SnapAIUI.StatusColor.error)
            Text(title)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 4)
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .frame(width: 18, height: 18)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("关闭提示")
        }
        .font(.caption)
        .foregroundStyle(.primary)
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        .background(SnapAIUI.StatusColor.error.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: SnapAIUI.cardRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: SnapAIUI.cardRadius, style: .continuous)
                .stroke(SnapAIUI.StatusColor.error.opacity(0.2), lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(title)
    }
}
