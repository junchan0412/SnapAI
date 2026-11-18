import SwiftUI
import SnapAILogic

struct ResultThinkingSection: View {
    @ObservedObject var state: ResultThinkingState
    @Binding var isExpanded: Bool

    var body: some View {
        if !state.text.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Button {
                    isExpanded.toggle()
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 10.5, weight: .semibold))
                        Text("推理过程")
                            .font(.system(size: 11.5, weight: .medium))
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.system(size: 9, weight: .semibold))
                    }
                    .foregroundStyle(.secondary)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                if isExpanded {
                    HStack(alignment: .top, spacing: 8) {
                        RoundedRectangle(cornerRadius: 1, style: .continuous)
                            .fill(Color.secondary.opacity(0.3))
                            .frame(width: 2)
                        Text(state.text)
                            .font(.system(size: 12))
                            .lineSpacing(3)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(.vertical, 4)
                    .padding(.leading, 4)
                }
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
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("正在思考回答…")
                    .font(SnapAIUI.Typography.bodyText)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .id("output")
            .transition(.opacity)
            .accessibilityLabel("AI 正在生成结果")
        case .streamingText:
            VStack(alignment: .leading, spacing: 4) {
                Text(state.text)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(Color.accentColor.opacity(0.75))
                    .frame(width: 6, height: 14)
                    .accessibilityHidden(true)
            }
            .id("output")
            .transition(.opacity)
            .accessibilityLabel("AI 正在生成结果")
        case .markdown:
            MarkdownView(text: state.text,
                         onPresentationReady: onMarkdownReady,
                         onCopyCode: onCopyCode,
                         bottomAnchorID: "output")
                .equatable()
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
    var onOpenModelCompare: (() -> Void)? = nil

    var body: some View {
        let state = commandState
        HStack(spacing: 6) {
            Button(action: vm.copyOutput) {
                Label("复制", systemImage: "doc.on.doc")
            }
            .buttonStyle(SnapAIPrimaryButtonStyle(compact: true))
            .keyboardShortcut("c", modifiers: [.command, .shift])
            .help(ResultCommandFactory.helpText(for: .copyOutput, in: state))
            .accessibilityLabel(ResultCommandFactory.accessibilityLabel(for: .copyOutput, in: state))
            .disabled(!ResultCommandFactory.isEnabled(.copyOutput, in: state))

            Button(action: vm.replaceOriginal) {
                Label("替换原文", systemImage: "arrow.uturn.backward")
            }
            .buttonStyle(SnapAISecondaryButtonStyle(compact: true))
            .keyboardShortcut(.return, modifiers: [.command])
            .help(ResultCommandFactory.helpText(for: .replaceOriginal, in: state))
            .accessibilityLabel(ResultCommandFactory.accessibilityLabel(for: .replaceOriginal, in: state))
            .disabled(vm.restoredConversation || !ResultCommandFactory.isEnabled(.replaceOriginal, in: state))

            Menu {
                menuButton(.appendToDocument, action: vm.appendToDocument,
                           shortcut: "\r", modifiers: [.command, .shift], state: state)
                menuButton(.copyMarkdown, action: vm.copyConversationMarkdown,
                           shortcut: "c", modifiers: [.command, .option], state: state)
                if let onOpenModelCompare {
                    Divider()
                    Button {
                        onOpenModelCompare()
                    } label: {
                        Label("双模型对照…", systemImage: "rectangle.split.2x1")
                    }
                    .disabled(vm.isGenerating)
                }
                Divider()
                menuButton(.exportConversation, action: vm.exportConversation,
                           shortcut: "e", modifiers: [.command], state: state)
                menuButton(.copyBriefDiagnostics, action: vm.copyBriefRequestDiagnostics,
                           shortcut: "d", modifiers: [.command, .shift], state: state)
                menuButton(.copyDiagnostics, action: vm.copyRequestDiagnostics,
                           shortcut: "d", modifiers: [.command, .option], state: state)
            } label: {
                Image(systemName: "ellipsis")
                    .frame(width: 26, height: 26)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("更多操作：追加到文档、复制完整对话、导出记录")
            .accessibilityLabel("更多结果操作")

            if vm.isPresenting {
                Button(action: vm.revealFullOutput) {
                    Image(systemName: "forward.end.fill")
                }
                .buttonStyle(SnapAIIconButtonStyle(size: 26, circular: false))
                .help("立即显示全文 (Esc)")
                .accessibilityLabel("立即显示全文")
                .keyboardShortcut(.cancelAction)
            } else if vm.isGenerating {
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
        .buttonStyle(SnapAIIconButtonStyle(size: 26, circular: false))
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
        .disabled((command == .appendToDocument && vm.restoredConversation) || !ResultCommandFactory.isEnabled(command, in: state))
    }

    private var commandState: ResultCommandState {
        ResultCommandState(resultText: outputState.text,
                           diagnosticsText: vm.requestDiagnosticText,
                           isStreaming: vm.isGenerating,
                           sourceText: vm.sourceText,
                           protectsContentExport: vm.contentExportProtectionEnabled,
                           recoveryCode: vm.errorRecoveryCode)
    }
}
