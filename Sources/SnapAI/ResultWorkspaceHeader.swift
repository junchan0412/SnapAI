import SwiftUI
import SnapAILogic

struct ResultWorkspaceHeader: View {
    let action: AIAction
    let actions: [AIAction]
    let modelName: String
    let providerName: String
    let switchableModels: [(provider: AIProvider, model: String)]
    let isStreaming: Bool
    var isPresenting = false
    let hasError: Bool
    let isTranslation: Bool
    let targetLanguage: TargetLanguage
    @Binding var isPinned: Bool
    var onSwitchAction: (AIAction) -> Void
    var onSwitchModel: (String, String) -> Void = { _, _ in }
    var onChangeLanguage: (TargetLanguage) -> Void
    var onOpenSavedSessions: () -> Void = {}
    var onOpenModelCompare: (() -> Void)? = nil
    var onClose: () -> Void

    private var statusBadgeText: String? {
        if isStreaming { return "生成中" }
        if isPresenting { return "输出中" }
        if hasError { return "未完成" }
        return nil
    }

    private var displayModelTitle: String {
        if !modelName.isEmpty { return modelName }
        if !providerName.isEmpty { return providerName }
        return "选择模型"
    }

    var body: some View {
        HStack(spacing: 6) {
            actionMenu

            if isTranslation {
                languageMenu
            }

            modelMenu

            if let badge = statusBadgeText {
                HStack(spacing: 4) {
                    Circle()
                        .fill(hasError ? SnapAIUI.StatusColor.error : Color.accentColor)
                        .frame(width: 5.5, height: 5.5)
                    Text(badge)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(hasError ? SnapAIUI.StatusColor.error : .secondary)
                }
                .padding(.leading, 2)
            }

            Spacer(minLength: 6)

            HStack(spacing: 2) {
                if let onOpenModelCompare {
                    Button(action: onOpenModelCompare) {
                        Image(systemName: "rectangle.split.2x1")
                    }
                    .buttonStyle(SnapAIIconButtonStyle(size: 26, circular: false))
                    .disabled(isStreaming)
                    .help("双模型对照")
                    .accessibilityLabel("打开双模型对照")
                }

                Button(action: onOpenSavedSessions) {
                    Image(systemName: "clock.arrow.circlepath")
                }
                .buttonStyle(SnapAIIconButtonStyle(size: 26, circular: false))
                .disabled(isStreaming)
                .help("恢复已保存会话")
                .accessibilityLabel("恢复已保存会话")

                Button { isPinned.toggle() } label: {
                    Image(systemName: ResultPinCommand.systemImage(isPinned: isPinned))
                        .foregroundStyle(isPinned ? Color.accentColor : .secondary)
                }
                .buttonStyle(SnapAIIconButtonStyle(size: 26, circular: false))
                .background(isPinned ? SnapAIUI.Surface.selected : .clear,
                            in: RoundedRectangle(cornerRadius: SnapAIUI.controlRadius, style: .continuous))
                .keyboardShortcut("p", modifiers: [.command, .shift])
                .help("\(ResultPinCommand.title(isPinned: isPinned)) (⌘⇧P)")
                .accessibilityLabel(ResultPinCommand.title(isPinned: isPinned))

                Button(action: onClose) {
                    Image(systemName: "xmark")
                }
                .buttonStyle(SnapAIIconButtonStyle(size: 26, circular: false))
                .help("关闭结果面板 (Esc)")
                .accessibilityLabel("关闭结果面板")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .snapAIChrome()
    }

    private var actionMenu: some View {
        Menu {
            ForEach(actions) { candidate in
                Button {
                    if candidate.id != action.id { onSwitchAction(candidate) }
                } label: {
                    Label(candidate.name,
                          systemImage: candidate.id == action.id ? "checkmark" :
                            (candidate.icon.isEmpty ? "wand.and.stars" : candidate.icon))
                }
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: action.icon.isEmpty ? "sparkles" : action.icon)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                Text(action.name.isEmpty ? "SnapAI" : action.name)
                    .lineLimit(1)
                if actions.count > 1 {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 8.5, weight: .bold))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .buttonStyle(SnapAIChipButtonStyle(active: true))
        .fixedSize()
        .disabled(isStreaming || actions.count < 2)
        .help(isStreaming ? "生成完成后可切换动作" : "切换动作并重新处理")
        .accessibilityLabel("当前动作：\(action.name)")
    }

    private var modelMenu: some View {
        Menu {
            if switchableModels.isEmpty {
                Text("暂无可切换模型")
            } else {
                ForEach(Array(switchableModels.enumerated()), id: \.offset) { _, item in
                    Button {
                        onSwitchModel(item.provider.id, item.model)
                    } label: {
                        let isCurrent = item.model == modelName && (providerName.isEmpty || item.provider.name == providerName)
                        if isCurrent {
                            Label("\(item.provider.name) · \(item.model)", systemImage: "checkmark")
                        } else {
                            Text("\(item.provider.name) · \(item.model)")
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "cpu")
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(.secondary)
                Text(displayModelTitle)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: 140, alignment: .leading)
                if switchableModels.count > 1 {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 8.5, weight: .bold))
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .buttonStyle(SnapAIChipButtonStyle())
        .fixedSize()
        .disabled(isStreaming || switchableModels.isEmpty)
        .help(providerName.isEmpty ? displayModelTitle : "\(providerName) · \(displayModelTitle)（点击切换模型并重试）")
        .accessibilityLabel("当前模型：\(displayModelTitle)")
    }

    private var languageMenu: some View {
        Menu {
            ForEach(TargetLanguage.allCases) { language in
                Button { onChangeLanguage(language) } label: {
                    if language == targetLanguage {
                        Label(language.rawValue, systemImage: "checkmark")
                    } else {
                        Text(language.rawValue)
                    }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "globe")
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(.secondary)
                Text(targetLanguage.rawValue)
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.system(size: 8.5, weight: .bold))
                    .foregroundStyle(.tertiary)
            }
        }
        .buttonStyle(SnapAIChipButtonStyle())
        .fixedSize()
        .disabled(isStreaming)
        .help(isStreaming ? "生成完成后可切换目标语言" : "切换目标语言并重新翻译")
        .accessibilityLabel("目标语言：\(targetLanguage.rawValue)")
    }
}
