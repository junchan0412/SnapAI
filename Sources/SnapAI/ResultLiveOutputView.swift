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

    var body: some View {
        switch ResultContentRenderMode.resolve(text: state.text,
                                               isStreaming: isStreaming) {
        case .waiting:
            HStack(spacing: 6) {
                Text("思考中").foregroundStyle(.secondary)
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
            MarkdownView(text: state.text)
                .equatable()
                .id("output")
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

            commandButton(.copyOutput,
                          action: vm.copyOutput,
                          shortcut: KeyboardShortcut("c", modifiers: [.command, .shift]),
                          state: state)
            commandButton(.copyMarkdown,
                          action: vm.copyConversationMarkdown,
                          shortcut: KeyboardShortcut("c", modifiers: [.command, .option]),
                          state: state)
            commandButton(.replaceOriginal,
                          action: vm.replaceOriginal,
                          shortcut: KeyboardShortcut(.return, modifiers: [.command]),
                          state: state)
            commandButton(.appendToDocument,
                          action: vm.appendToDocument,
                          shortcut: KeyboardShortcut(.return, modifiers: [.command, .shift]),
                          state: state)
            commandButton(.exportConversation,
                          action: vm.exportConversation,
                          shortcut: KeyboardShortcut("e", modifiers: [.command]),
                          state: state)

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
