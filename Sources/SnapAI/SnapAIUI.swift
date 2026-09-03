import SwiftUI
import SnapAILogic

enum SnapAIUI {
    static let panelRadius: CGFloat = 14
    static let cardRadius: CGFloat = 10
    static let controlRadius: CGFloat = 8
    static let compactPadding: CGFloat = 10
    static let sectionPadding: CGFloat = 12

    static let quietFillOpacity: Double = 0.028
    static let regularFillOpacity: Double = 0.05
    static let selectedFillOpacity: Double = 0.12
    static let strokeOpacity: Double = 0.08

    // MARK: - 间距阶(统一各界面留白,避免硬编码)
    static let tightSpacing: CGFloat = 8
    static let standardSpacing: CGFloat = 12
    static let looseSpacing: CGFloat = 20
    static let edgePadding: CGFloat = 16

    // MARK: - 字体阶(清晰层级,取代散落的 .headline/.caption 直写)
    enum Typography {
        static let panelTitle = Font.system(.title3, design: .rounded).weight(.semibold)
        static let sectionLabel = Font.caption.weight(.medium)
        static let bodyText = Font.callout
        static let metaText = Font.caption
    }

    // MARK: - 语义状态色(取代散落的 .green/.orange/.red 硬编码)
    enum StatusColor {
        static let success = Color.green
        static let warning = Color.orange
        static let error = Color.red
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

private struct SnapAISurfaceModifier: ViewModifier {
    var padding: CGFloat
    var fillOpacity: Double
    var strokeOpacity: Double
    var radius: CGFloat
    var isSelected: Bool

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(isSelected ? Color.accentColor.opacity(SnapAIUI.selectedFillOpacity) : Color.primary.opacity(fillOpacity))
            }
            .overlay {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .stroke(isSelected ? Color.accentColor.opacity(0.34) : Color.primary.opacity(strokeOpacity), lineWidth: 1)
            }
    }
}

extension View {
    func snapAISurface(padding: CGFloat = SnapAIUI.sectionPadding,
                       fillOpacity: Double = SnapAIUI.regularFillOpacity,
                       strokeOpacity: Double = SnapAIUI.strokeOpacity,
                       radius: CGFloat = SnapAIUI.cardRadius,
                       isSelected: Bool = false) -> some View {
        modifier(SnapAISurfaceModifier(padding: padding,
                                       fillOpacity: fillOpacity,
                                       strokeOpacity: strokeOpacity,
                                       radius: radius,
                                       isSelected: isSelected))
    }
}

struct SnapAIStatusPill: View {
    var title: String
    var systemImage: String
    var tint: Color = .secondary
    var filled: Bool = false

    var body: some View {
        Label(title, systemImage: systemImage)
            .font(.caption2.weight(.semibold))
            .lineLimit(1)
            .truncationMode(.middle)
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .foregroundStyle(tint)
            .background(filled ? tint.opacity(0.14) : Color.primary.opacity(0.045), in: Capsule())
            .overlay {
                Capsule()
                    .stroke(filled ? tint.opacity(0.24) : Color.primary.opacity(0.06), lineWidth: 1)
            }
    }
}

struct SnapAIIconButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    var size: CGFloat = 28
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
    let label: ButtonStyleConfiguration.Label
    let isPressed: Bool
    let isEnabled: Bool
    var size: CGFloat
    var circular: Bool
    @State private var isHovered = false

    var body: some View {
        let fill: Double = isPressed ? 0.14 : (isHovered ? 0.10 : 0.05)
        label
            .font(.system(size: 13, weight: .semibold))
            .frame(width: size, height: size)
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
            .onHover { isHovered = $0 }
            .scaleEffect(isPressed ? 0.94 : 1)
            .animation(.easeOut(duration: 0.12), value: isHovered)
            .animation(.easeOut(duration: 0.1), value: isPressed)
    }
}

// MARK: - 主按钮样式(用于结果浮窗错误恢复、设置等场景的主操作)

/// 用主色调填充的强调按钮,在多个并列操作中明确「主操作」。
struct SnapAIPrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    var tint: Color = .accentColor

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.callout.weight(.semibold))
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .foregroundStyle(.white)
            .background {
                RoundedRectangle(cornerRadius: SnapAIUI.controlRadius, style: .continuous)
                    .fill(tint.opacity(isEnabled ? (configuration.isPressed ? 0.8 : 1) : 0.4))
            }
            .contentShape(Rectangle())
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
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
        Label(title, systemImage: systemImage)
            .font(.caption2.weight(.semibold))
            .lineLimit(1)
            .truncationMode(.middle)
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .foregroundStyle(tone.color)
            .background(tone.color.opacity(0.14), in: Capsule())
            .overlay {
                Capsule().stroke(tone.color.opacity(0.24), lineWidth: 1)
            }
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
                progressTrack(phase: 0.5)
            } else {
                // 30Hz 足以保持连续感,同时把持续刷新次数降到原来的一半。
                TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: false)) { context in
                    let cycle = 1.35
                    let phase = context.date.timeIntervalSinceReferenceDate
                        .truncatingRemainder(dividingBy: cycle) / cycle
                    progressTrack(phase: phase)
                }
            }
        }
        .frame(height: 2.5)
        .accessibilityHidden(true)
    }

    private func progressTrack(phase: Double) -> some View {
        GeometryReader { proxy in
            let barWidth = max(36, proxy.size.width * 0.28)
            let travel = max(0, proxy.size.width - barWidth)
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                    .fill(Color.accentColor.opacity(0.14))
                RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.accentColor.opacity(0.35),
                                Color.accentColor,
                                Color.accentColor.opacity(0.35)
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: barWidth)
                    .offset(x: travel * phase)
            }
        }
        .frame(height: 2.5)
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
        .foregroundStyle(SnapAIUI.StatusColor.warning)
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
        .foregroundStyle(SnapAIUI.StatusColor.error)
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
