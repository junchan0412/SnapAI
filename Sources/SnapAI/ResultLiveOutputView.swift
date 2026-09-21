import SwiftUI
import SnapAILogic

struct ResultThinkingSection: View {
    @ObservedObject var state: ResultThinkingState
    @Binding var isExpanded: Bool

    var body: some View {
        if !state.text.isEmpty {
            DisclosureGroup(isExpanded: $isExpanded) {
                if isExpanded {
                    Text(state.text)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(SnapAIUI.compactPadding)
                        .snapAIGlassCard(radius: SnapAIUI.controlRadius)
                        .clipShape(RoundedRectangle(cornerRadius: SnapAIUI.controlRadius, style: .continuous))
                }
            } label: {
                Label("思考过程", systemImage: "brain")
                    .font(SnapAIUI.Typography.metaText)
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
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    ProgressView().controlSize(.small)
                    Text("正在准备回答")
                        .font(SnapAIUI.Typography.sectionTitle)
                }
                Text("结果会实时显示在这里。")
                    .font(SnapAIUI.Typography.metaText)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .id("output")
            .transition(.opacity)
            .accessibilityLabel("AI 正在生成结果")
        case .streamingText:
            VStack(alignment: .leading, spacing: 4) {
                Text(state.text)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
                RoundedRectangle(cornerRadius: 1)
                    .fill(Color.accentColor.opacity(0.6))
                    .frame(width: 3, height: 15)
                    .accessibilityHidden(true)
            }
            .id("output")
            .transition(.opacity)
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
        HStack(spacing: SnapAIUI.tightSpacing) {
            Button(action: vm.copyOutput) {
                Label("复制结果", systemImage: "doc.on.doc")
            }
            .buttonStyle(SnapAIPrimaryButtonStyle())
            .controlSize(.small)
            .keyboardShortcut("c", modifiers: [.command, .shift])
            .help(ResultCommandFactory.helpText(for: .copyOutput, in: state))
            .disabled(!ResultCommandFactory.isEnabled(.copyOutput, in: state))

            Button(action: vm.replaceOriginal) {
                Label("替换原文", systemImage: "arrow.uturn.left.square")
            }
            .buttonStyle(SnapAISecondaryButtonStyle())
            .controlSize(.small)
            .keyboardShortcut(.return, modifiers: [.command])
            .help(ResultCommandFactory.helpText(for: .replaceOriginal, in: state))
            .disabled(!ResultCommandFactory.isEnabled(.replaceOriginal, in: state))

            Menu {
                menuButton(.copyMarkdown, action: vm.copyConversationMarkdown,
                           shortcut: "c", modifiers: [.command, .option], state: state)
                menuButton(.appendToDocument, action: vm.appendToDocument,
                           shortcut: "\r", modifiers: [.command, .shift], state: state)
                Divider()
                menuButton(.exportConversation, action: vm.exportConversation,
                           shortcut: "e", modifiers: [.command], state: state)
                menuButton(.copyBriefDiagnostics, action: vm.copyBriefRequestDiagnostics,
                           shortcut: "d", modifiers: [.command, .shift], state: state)
                menuButton(.copyDiagnostics, action: vm.copyRequestDiagnostics,
                           shortcut: "d", modifiers: [.command, .option], state: state)
            } label: {
                Image(systemName: "ellipsis")
                    .frame(width: 26, height: 30)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .controlSize(.small)
            .help("更多操作:复制完整结果、追加到文档、导出对话")
            .accessibilityLabel("更多结果操作")

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
        .buttonStyle(SnapAIIconButtonStyle(size: 30, circular: false))
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
        ResultCommandState(resultText: outputState.text,
                                  diagnosticsText: vm.requestDiagnosticText,
                                  isStreaming: vm.isStreaming,
                                  sourceText: vm.sourceText,
                                  protectsContentExport: vm.contentExportProtectionEnabled,
                                  recoveryCode: vm.errorRecoveryCode)
    }
}
