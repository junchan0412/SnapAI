import SwiftUI
import SnapAILogic

struct ResultThinkingSection: View {
    @ObservedObject var state: ResultThinkingState
    @Binding var isExpanded: Bool

    var body: some View {
        if !state.text.isEmpty {
            DisclosureGroup(isExpanded: $isExpanded) {
                Text(state.text)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
                    .background(Color.primary.opacity(0.04))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            } label: {
                Label("思考过程", systemImage: "brain")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct ResultOutputDisplay: View {
    @ObservedObject var state: ResultOutputState
    let isStreaming: Bool
    var onMarkdownReady: () -> Void = {}
    var onCopyCode: (String) -> Void = { _ in }

    var body: some View {
        switch ResultContentRenderMode.resolve(text: state.text,
                                               isStreaming: isStreaming) {
        case .waiting:
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text("等待响应…").foregroundStyle(.secondary)
                TypingCursor()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .id("output")
            .accessibilityLabel("AI 正在生成结果")
        case .streamingText:
            VStack(alignment: .leading, spacing: 4) {
                Text(state.text)
                    .frame(maxWidth: .infinity, alignment: .leading)
                TypingCursor()
            }
            .id("output")
            .accessibilityLabel("AI 正在生成结果")
        case .markdown:
            MarkdownView(text: state.text,
                         onPresentationReady: onMarkdownReady,
                         onCopyCode: onCopyCode)
                .equatable()
                .id("output")
                .transition(.opacity)
        case .empty:
            EmptyView()
        }
    }
}

struct ResultOutputAutoScrollObserver: View {
    @ObservedObject var state: ResultOutputState
    var onOutputChange: () -> Void

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .accessibilityHidden(true)
            .onChange(of: state.text) {
                onOutputChange()
            }
    }
}

struct ResultActionsToolbar: View {
    @ObservedObject var vm: ResultViewModel
    @ObservedObject var outputState: ResultOutputState

    var body: some View {
        let state = commandState
        HStack(spacing: 7) {
            Spacer(minLength: 0)

            // 主操作:复制结果、替换原文(最常用,保留可见图标按钮)
            commandButton(.copyOutput,
                          action: vm.copyOutput,
                          shortcut: KeyboardShortcut("c", modifiers: [.command, .shift]),
                          state: state)
            commandButton(.replaceOriginal,
                          action: vm.replaceOriginal,
                          shortcut: KeyboardShortcut(.return, modifiers: [.command]),
                          state: state)

            // 次要操作收纳为单一菜单,降低按钮密度;快捷键作为菜单快捷键仍生效。
            Menu {
                menuButton(.copyMarkdown, action: vm.copyConversationMarkdown,
                           shortcut: "c", modifiers: [.command, .option], state: state)
                menuButton(.appendToDocument, action: vm.appendToDocument,
                           shortcut: "\r", modifiers: [.command, .shift], state: state)
                Divider()
                menuButton(.exportConversation, action: vm.exportConversation,
                           shortcut: "e", modifiers: [.command], state: state)
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .controlSize(.small)
            .help("更多操作:复制完整结果、追加到文档、导出对话")

            if vm.isStreaming {
                commandButton(.stop,
                              action: vm.cancel,
                              shortcut: .cancelAction,
                              state: state)
            } else {
                commandButton(.regenerate,
                              action: vm.regenerate,
                              shortcut: KeyboardShortcut("r", modifiers: [.command]),
                              state: state)
            }
        }
    }

    private func commandButton(_ command: ResultCommandAction,
                               action handler: @escaping () -> Void,
                               shortcut: KeyboardShortcut,
                               state: ResultCommandState) -> some View {
        Button(action: handler) {
            Image(systemName: ResultCommandFactory.descriptor(for: command, in: state).systemImage)
        }
        .controlSize(.small)
        .keyboardShortcut(shortcut)
        .help(ResultCommandFactory.helpText(for: command, in: state))
        .accessibilityLabel(ResultCommandFactory.accessibilityLabel(for: command, in: state))
        .disabled(!ResultCommandFactory.isEnabled(command, in: state))
    }

    @ViewBuilder
    private func menuButton(_ command: ResultCommandAction,
                            action handler: @escaping () -> Void,
                            shortcut keyEquivalent: String,
                            modifiers: EventModifiers,
                            state: ResultCommandState) -> some View {
        Button {
            handler()
        } label: {
            if ResultCommandFactory.isEnabled(command, in: state) {
                Label(ResultCommandFactory.menuTitle(for: command, in: state),
                      systemImage: ResultCommandFactory.descriptor(for: command, in: state).systemImage)
            } else {
                Text(ResultCommandFactory.menuTitle(for: command, in: state))
            }
        }
        .keyboardShortcut(KeyEquivalent(Character(keyEquivalent)), modifiers: modifiers)
        .disabled(!ResultCommandFactory.isEnabled(command, in: state))
    }

    private var commandState: ResultCommandState {
        _ = outputState.text
        return ResultCommandState(resultText: vm.completeText,
                                  diagnosticsText: vm.requestDiagnosticText,
                                  isStreaming: vm.isStreaming,
                                  sourceText: vm.sourceText,
                                  protectsContentExport: vm.contentExportProtectionEnabled,
                                  recoveryCode: vm.errorRecoveryCode)
    }
}
