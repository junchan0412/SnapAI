import SwiftUI
import SnapAILogic

struct ResultWorkspaceHeader: View {
    let action: AIAction
    let actions: [AIAction]
    let modelName: String
    let providerName: String
    let isStreaming: Bool
    let hasError: Bool
    let isTranslation: Bool
    let targetLanguage: TargetLanguage
    @Binding var isPinned: Bool
    var onSwitchAction: (AIAction) -> Void
    var onChangeLanguage: (TargetLanguage) -> Void
    var onClose: () -> Void

    private var modelSummary: String {
        [providerName, modelName].filter { !$0.isEmpty }.joined(separator: " · ")
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: action.icon.isEmpty ? "text.bubble" : action.icon)
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(.tint)
                .frame(width: 36, height: 36)
                .background(SnapAIUI.Surface.selected,
                            in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            VStack(alignment: .leading, spacing: 5) {
                actionMenu
                HStack(spacing: 5) {
                    if isStreaming {
                        Text("正在生成")
                            .foregroundStyle(.tint)
                        if !modelSummary.isEmpty {
                            Text("·")
                        }
                    } else if hasError {
                        Text("请求未完成")
                            .foregroundStyle(SnapAIUI.StatusColor.error)
                        if !modelSummary.isEmpty {
                            Text("·")
                        }
                    }
                    if !modelSummary.isEmpty {
                        Text(modelSummary)
                            .truncationMode(.middle)
                    } else if !isStreaming && !hasError {
                        Text("SnapAI")
                    }
                }
                .font(SnapAIUI.Typography.metaText)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if isTranslation {
                languageMenu
            }
            HStack(spacing: 2) {
                Button { isPinned.toggle() } label: {
                    Image(systemName: ResultPinCommand.systemImage(isPinned: isPinned))
                        .foregroundStyle(isPinned ? Color.accentColor : .secondary)
                }
                .buttonStyle(SnapAIIconButtonStyle(circular: false))
                .background(isPinned ? SnapAIUI.Surface.selected : .clear,
                            in: RoundedRectangle(cornerRadius: SnapAIUI.controlRadius, style: .continuous))
                .keyboardShortcut("p", modifiers: [.command, .shift])
                .help("\(ResultPinCommand.title(isPinned: isPinned)) (⌘⇧P)")
                .accessibilityLabel(ResultPinCommand.title(isPinned: isPinned))
                Button(action: onClose) {
                    Image(systemName: "xmark")
                }
                .buttonStyle(SnapAIIconButtonStyle(circular: false))
                .help("关闭结果面板")
                .accessibilityLabel("关闭结果面板")
            }
        }
        .padding(.horizontal, SnapAIUI.edgePadding)
        .padding(.vertical, 16)
        .background(SnapAIUI.Surface.chrome)
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
            HStack(spacing: 6) {
                Text(action.name.isEmpty ? "SnapAI" : action.name)
                    .font(SnapAIUI.Typography.panelTitle)
                    .lineLimit(1)
                if actions.count > 1 {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .disabled(isStreaming || actions.count < 2)
        .help(isStreaming ? "生成完成后可切换动作" : "切换动作并重新处理原文")
        .accessibilityLabel("当前动作：\(action.name)")
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
            Label(targetLanguage.rawValue, systemImage: "globe")
                .font(SnapAIUI.Typography.toolbarLabel)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .disabled(isStreaming)
        .help(isStreaming ? "生成完成后可切换目标语言" : "切换目标语言并重新翻译")
        .accessibilityLabel("目标语言：\(targetLanguage.rawValue)")
    }
}
