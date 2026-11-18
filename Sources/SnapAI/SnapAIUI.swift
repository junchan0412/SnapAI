import SwiftUI
import AppKit
import SnapAILogic

enum SnapAIUI {
    static let panelRadius: CGFloat = 14
    static let cardRadius: CGFloat = 10
    static let controlRadius: CGFloat = 7
    static let compactPadding: CGFloat = 12
    static let sectionPadding: CGFloat = 14

    static let quietFillOpacity: Double = 0.03
    static let regularFillOpacity: Double = 0.055
    static let selectedFillOpacity: Double = 0.11
    static let strokeOpacity: Double = 0.08
    static let focusStrokeOpacity: Double = 0.45
    static let minimumHitTarget: CGFloat = 28

    // MARK: - 间距阶
    static let tightSpacing: CGFloat = 6
    static let standardSpacing: CGFloat = 12
    static let looseSpacing: CGFloat = 18
    static let edgePadding: CGFloat = 20

    // MARK: - 字体阶（符合 macOS 原生密度，克制清爽）
    enum Typography {
        static let windowTitle = Font.system(size: 20, weight: .semibold)
        static let panelTitle = Font.system(size: 14, weight: .semibold)
        static let sectionTitle = Font.system(size: 13, weight: .semibold)
        static let sectionLabel = Font.system(size: 11.5, weight: .semibold)
        static let bodyText = Font.system(size: 13)
        static let readingText = Font.system(size: 14.5)
        static let metaText = Font.system(size: 11.5)
        static let toolbarLabel = Font.system(size: 12, weight: .medium)
        static let keycap = Font.system(size: 10.5, weight: .medium, design: .monospaced)
    }

    // MARK: - 语义表面
    enum Surface {
        static let canvas = Color(nsColor: .windowBackgroundColor)
        static let content = Color(nsColor: .textBackgroundColor)
        static let field = Color(nsColor: .textBackgroundColor)
        static let control = Color.primary.opacity(regularFillOpacity)
        static let quiet = Color.primary.opacity(quietFillOpacity)
        static let selected = Color.accentColor.opacity(selectedFillOpacity)
        static let divider = Color.primary.opacity(0.07)
        static let border = Color.primary.opacity(0.085)
        static let focus = Color.accentColor.opacity(focusStrokeOpacity)
    }

    // MARK: - 语义状态色
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

// MARK: - macOS 系统设置风格分组组件

struct SnapAISectionGroup<Trailing: View, Content: View>: View {
    let title: String?
    let subtitle: String?
    @ViewBuilder var trailing: () -> Trailing
    @ViewBuilder var content: () -> Content

    init(_ title: String? = nil,
         subtitle: String? = nil,
         @ViewBuilder trailing: @escaping () -> Trailing = { EmptyView() },
         @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.subtitle = subtitle
        self.trailing = trailing
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if title != nil || subtitle != nil || Trailing.self != EmptyView.self {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    VStack(alignment: .leading, spacing: 2) {
                        if let title, !title.isEmpty {
                            Text(title)
                                .font(SnapAIUI.Typography.sectionTitle)
                                .foregroundStyle(.primary)
                        }
                        if let subtitle, !subtitle.isEmpty {
                            Text(subtitle)
                                .font(SnapAIUI.Typography.metaText)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer(minLength: 8)
                    trailing()
                }
                .padding(.horizontal, 2)
            }
            VStack(alignment: .leading, spacing: 0) {
                content()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .snapAIGlassCard()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct SnapAISettingRow<Control: View>: View {
    let title: String
    var subtitle: String? = nil
    var icon: String? = nil
    var iconTint: Color = .accentColor
    @ViewBuilder var control: () -> Control

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            if let icon {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(iconTint)
                    .frame(width: 24, height: 24)
                    .background(iconTint.opacity(0.12),
                                in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(SnapAIUI.Typography.bodyText.weight(.medium))
                    .foregroundStyle(.primary)
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(SnapAIUI.Typography.metaText)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 16)
            control()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct SnapAIFormDivider: View {
    var inset: CGFloat = 14

    var body: some View {
        Rectangle()
            .fill(SnapAIUI.Surface.divider)
            .frame(height: 0.75)
            .padding(.leading, inset)
    }
}

// MARK: - 状态胶囊与快捷键键帽

struct SnapAIStatusPill: View {
    var title: String
    var systemImage: String
    var tint: Color = .secondary
    var filled: Bool = false

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: systemImage)
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(tint)
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(filled ? .primary : .secondary)
        }
        .lineLimit(1)
        .truncationMode(.middle)
        .padding(.horizontal, 8)
        .padding(.vertical, 3.5)
        .snapAIGlassPill(tint: filled ? tint : .secondary)
    }
}

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
            .padding(.horizontal, 5.5)
            .padding(.vertical, 2)
            .frame(minWidth: 20, minHeight: 19)
            .background(SnapAIUI.Surface.control,
                        in: RoundedRectangle(cornerRadius: 4.5, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 4.5, style: .continuous)
                    .strokeBorder(SnapAIUI.Surface.border, lineWidth: 0.6)
            }
            .accessibilityLabel("快捷键 \(text)")
    }
}

// MARK: - 按钮样式

struct SnapAIIconButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    var size: CGFloat = SnapAIUI.minimumHitTarget
    var circular: Bool = false

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
        let fill: Double = isPressed ? 0.12 : (isHovered ? 0.07 : 0)
        label
            .font(.system(size: 12.5, weight: .medium))
            .frame(width: max(size, 26), height: max(size, 26))
            .foregroundStyle(isEnabled ? (isHovered ? Color.primary : Color.secondary) : Color.secondary.opacity(0.4))
            .background {
                if circular {
                    Circle().fill(Color.primary.opacity(fill))
                } else {
                    RoundedRectangle(cornerRadius: SnapAIUI.controlRadius, style: .continuous)
                        .fill(Color.primary.opacity(fill))
                }
            }
            .contentShape(Rectangle())
            .overlay {
                RoundedRectangle(cornerRadius: circular ? size / 2 : SnapAIUI.controlRadius,
                                 style: .continuous)
                    .stroke(isFocused ? SnapAIUI.Surface.focus : .clear, lineWidth: 1.5)
            }
            .onHover { isHovered = $0 }
            .animation(reduceMotion ? nil : .easeOut(duration: 0.1), value: isHovered)
    }
}

struct SnapAIPrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.isFocused) private var isFocused
    var tint: Color = .accentColor
    var compact: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: compact ? 12 : 12.5, weight: .semibold))
            .padding(.horizontal, compact ? 10 : 12)
            .padding(.vertical, compact ? 5.5 : 6.5)
            .foregroundStyle(.white)
            .background {
                RoundedRectangle(cornerRadius: SnapAIUI.controlRadius, style: .continuous)
                    .fill(tint.opacity(isEnabled ? (configuration.isPressed ? 0.82 : 1) : 0.38))
            }
            .contentShape(Rectangle())
            .overlay {
                RoundedRectangle(cornerRadius: SnapAIUI.controlRadius + 1.5, style: .continuous)
                    .stroke(isFocused ? SnapAIUI.Surface.focus : .clear, lineWidth: 1.5)
                    .padding(-2)
            }
    }
}

struct SnapAISecondaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.isFocused) private var isFocused
    var compact: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        SnapAISecondaryButtonBody(label: configuration.label,
                                  isPressed: configuration.isPressed,
                                  isEnabled: isEnabled,
                                  isFocused: isFocused,
                                  compact: compact)
    }
}

private struct SnapAISecondaryButtonBody: View {
    let label: ButtonStyleConfiguration.Label
    let isPressed: Bool
    let isEnabled: Bool
    let isFocused: Bool
    let compact: Bool
    @State private var isHovered = false

    var body: some View {
        let fillOpacity = isPressed ? 0.12 : (isHovered ? 0.08 : 0.045)
        label
            .font(.system(size: compact ? 12 : 12.5, weight: .medium))
            .padding(.horizontal, compact ? 9 : 11)
            .padding(.vertical, compact ? 5.5 : 6.5)
            .foregroundStyle(isEnabled ? Color.primary : Color.secondary.opacity(0.5))
            .background(Color.primary.opacity(fillOpacity),
                        in: RoundedRectangle(cornerRadius: SnapAIUI.controlRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: SnapAIUI.controlRadius, style: .continuous)
                    .strokeBorder(isFocused ? SnapAIUI.Surface.focus : SnapAIUI.Surface.border,
                                  lineWidth: isFocused ? 1.5 : 0.75)
            }
            .contentShape(Rectangle())
            .onHover { isHovered = $0 }
    }
}

struct SnapAIChipButtonStyle: ButtonStyle {
    var active: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .modifier(SnapAIChipSurface(active: active))
            .opacity(configuration.isPressed ? 0.8 : 1.0)
    }
}

/// 轻量胶囊型工具栏选择胶囊（用于动作切换、模型切换等）。
struct SnapAIChipSurface: ViewModifier {
    var active: Bool = false
    @State private var isHovered = false

    func body(content: Content) -> some View {
        let fill = active
            ? Color.accentColor.opacity(isHovered ? 0.16 : 0.11)
            : Color.primary.opacity(isHovered ? 0.08 : 0.045)
        let stroke = active
            ? Color.accentColor.opacity(0.28)
            : Color.primary.opacity(0.08)
        content
            .font(.system(size: 12, weight: .medium))
            .padding(.horizontal, 9)
            .frame(height: 26)
            .background(fill, in: Capsule(style: .continuous))
            .overlay {
                Capsule(style: .continuous)
                    .strokeBorder(stroke, lineWidth: 0.65)
            }
            .contentShape(Capsule(style: .continuous))
            .onHover { isHovered = $0 }
    }
}

extension View {
    func snapAIChip(active: Bool = false) -> some View {
        modifier(SnapAIChipSurface(active: active))
    }
}

// MARK: - 破坏性操作二次确认

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

// MARK: - 流式生成进度条与状态横幅

struct SnapAIStreamingProgressBar: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            if reduceMotion {
                Rectangle()
                    .fill(Color.accentColor.opacity(0.55))
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

struct SnapAIIncompleteResultBanner: View {
    let title: String
    let systemImage: String
    var onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(SnapAIUI.StatusColor.warning)
            Text(title)
                .font(SnapAIUI.Typography.metaText)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 4)
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 18, height: 18)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("关闭提示")
        }
        .foregroundStyle(.primary)
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(SnapAIUI.StatusColor.warning.opacity(0.09),
                    in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(SnapAIUI.StatusColor.warning.opacity(0.22), lineWidth: 0.75)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(title)
    }
}

struct SnapAITransientNoticeBanner: View {
    let title: String
    var onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(SnapAIUI.StatusColor.error)
            Text(title)
                .font(SnapAIUI.Typography.metaText)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 4)
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 18, height: 18)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("关闭提示")
        }
        .foregroundStyle(.primary)
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(SnapAIUI.StatusColor.error.opacity(0.09),
                    in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(SnapAIUI.StatusColor.error.opacity(0.22), lineWidth: 0.75)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(title)
    }
}
