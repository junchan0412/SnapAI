import SwiftUI
import AppKit
import SnapAILogic

struct TypingCursor: View {
    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { context in
            let on = Int(context.date.timeIntervalSinceReferenceDate * 2) % 2 == 0
            RoundedRectangle(cornerRadius: 1).fill(Color.primary).frame(width: 7, height: 15)
                .opacity(on ? 1 : 0.15)
        }
    }
}

struct ResultView: View {
    @ObservedObject var vm: ResultViewModel
    var onClose: () -> Void
    var onOpenAISettings: () -> Void = {}

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            scrollContent
            Divider()
            footer
        }
        .frame(minWidth: 320, maxWidth: .infinity, minHeight: 200, maxHeight: .infinity)
        .background(.regularMaterial)
    }

    // MARK: - Header

    private var header: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: SnapAIUI.cardRadius, style: .continuous)
                        .fill(Color.accentColor.opacity(0.16))
                    Image(systemName: vm.action.icon.isEmpty ? "sparkles" : vm.action.icon)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.tint)
                }
                .frame(width: 32, height: 32)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(vm.action.name.isEmpty ? "SnapAI" : vm.action.name)
                            .font(.headline)
                            .lineLimit(1)
                        if vm.isStreaming {
                            ProgressView().controlSize(.small)
                        }
                    }
                    HStack(spacing: 6) {
                        if vm.isPinned {
                            Label(ResultPinCommand.statusTitle,
                                  systemImage: ResultPinCommand.statusSystemImage)
                        } else if vm.isStreaming {
                            Label("生成中", systemImage: "sparkles")
                        } else {
                            Label("就绪", systemImage: "checkmark.circle")
                        }
                    }
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                }

                // #7 翻译类语言切换
                if vm.isTranslation {
                    Menu {
                        ForEach(TargetLanguage.allCases) { lang in
                            Button {
                                vm.changeLanguage(lang)
                            } label: {
                                if lang == vm.targetLanguage { Label(lang.rawValue, systemImage: "checkmark") }
                                else { Text(lang.rawValue) }
                            }
                        }
                    } label: {
                        Label(vm.targetLanguage.rawValue, systemImage: "globe").font(.caption)
                    }
                    .menuStyle(.borderlessButton).fixedSize().disabled(vm.isStreaming)
                }

                Spacer()
                Button { vm.isPinned.toggle() } label: {
                    Image(systemName: ResultPinCommand.systemImage(isPinned: vm.isPinned))
                        .foregroundStyle(vm.isPinned ? Color.accentColor : .secondary)
                }
                .buttonStyle(SnapAIIconButtonStyle(size: 26))
                .keyboardShortcut("p", modifiers: [.command, .shift])
                .help("\(ResultPinCommand.title(isPinned: vm.isPinned)) (⌘⇧P)")
                .accessibilityLabel(ResultPinCommand.title(isPinned: vm.isPinned))
                Button { onClose() } label: {
                    Image(systemName: "xmark")
                }
                .buttonStyle(SnapAIIconButtonStyle(size: 26))
                .help("关闭")
                .accessibilityLabel("关闭")
            }
            .padding(.horizontal, 14).padding(.vertical, 12)

            // #4 动作切换栏
            actionSwitcher
            routeStatusBar
        }
    }

    @ViewBuilder
    private var actionSwitcher: some View {
        let enabled = vm.settings.enabledActions
        if enabled.count > 1 {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(enabled) { act in
                        Button {
                            if act.id != vm.action.id { vm.switchAction(act) }
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: act.icon.isEmpty ? "sparkles" : act.icon).font(.caption2)
                                Text(act.name).font(.caption2)
                            }
                            .padding(.horizontal, 9).padding(.vertical, 5)
                            .background(act.id == vm.action.id ? Color.accentColor.opacity(0.18) : Color.primary.opacity(0.045))
                            .clipShape(Capsule())
                            .overlay(Capsule().stroke(act.id == vm.action.id ? Color.accentColor.opacity(0.32) : Color.primary.opacity(0.05), lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(act.id == vm.action.id ? Color.accentColor : .primary)
                        .disabled(vm.isStreaming)
                    }
                }
                .padding(.horizontal, 14).padding(.bottom, 8)
            }
        }
    }

    @ViewBuilder
    private var routeStatusBar: some View {
        let routeText = routeStatusText
        if routeText.primaryText != "正在准备请求" || !routeText.detailLines.isEmpty || vm.isStreaming {
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 7) {
                    SnapAIStatusPill(title: vm.isStreaming ? "生成中" : vm.routeStatusTitle,
                                     systemImage: vm.isStreaming ? "sparkles" : "point.3.connected.trianglepath.dotted",
                                     tint: vm.isStreaming ? .accentColor : .secondary,
                                     filled: vm.isStreaming)
                    Text(routeText.primaryText)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .foregroundStyle(.primary)
                    Spacer(minLength: 0)
                    if !routeText.detailLines.isEmpty {
                        Button {
                            withAnimation(.easeInOut(duration: 0.16)) {
                                vm.showRouteDetails.toggle()
                            }
                        } label: {
                            Image(systemName: vm.showRouteDetails ? "chevron.up.circle.fill" : "chevron.down.circle")
                                .font(.system(size: 13, weight: .semibold))
                                .frame(width: 20, height: 20)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(vm.showRouteDetails ? Color.accentColor : .secondary)
                        .help(vm.showRouteDetails ? "收起路由详情" : "展开路由详情")
                        .accessibilityLabel(vm.showRouteDetails ? "收起路由详情" : "展开路由详情")
                    }
                }
                if vm.showRouteDetails && !routeText.detailLines.isEmpty {
                    VStack(alignment: .leading, spacing: 3) {
                        ForEach(routeText.detailLines, id: \.self) { line in
                            Text(line)
                                .lineLimit(2)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .foregroundStyle(.secondary)
                    .padding(.top, 1)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            .font(.caption2)
            .padding(.horizontal, 14)
            .padding(.bottom, 8)
        }
    }

    private var routeStatusText: ResultRouteStatusText {
        ResultRouteStatusText.make(providerName: vm.activeProviderName,
                                   modelName: vm.activeModelName,
                                   fallbackModelName: vm.settings.model,
                                   contextSummary: vm.activeContextSummaryText,
                                   routeExplanation: vm.routeExplanationText,
                                   routeNote: vm.routeNote)
    }

    // MARK: - Scroll content

    private var scrollContent: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    sourceEditor

                    ResultThinkingSection(state: vm.thinkingState,
                                          isExpanded: Binding(get: { vm.showThinking },
                                                              set: { vm.showThinking = $0 }))

                    if let err = vm.errorMessage {
                        VStack(alignment: .leading, spacing: 6) {
                            Label(err, systemImage: "exclamationmark.triangle.fill")
                                .font(.callout).foregroundStyle(.red)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            if let recovery = vm.errorRecoverySuggestionText {
                                Label(recovery, systemImage: "wrench.and.screwdriver")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            // #12 重试按钮
                            HStack(spacing: 8) {
                                if vm.errorRecoveryPrimaryAction == .settings {
                                    errorSettingsButton
                                    errorRetryButton
                                } else {
                                    errorRetryButton
                                    errorSettingsButton
                                }
                                Button { vm.copyBriefRequestDiagnostics() } label: {
                                    Label("精简",
                                          systemImage: ResultDiagnosticsCommand.systemImage)
                                }
                                .controlSize(.small)
                                .disabled(!resultCommandEnabled(.copyBriefDiagnostics))
                                .help(ResultDiagnosticsCommand.briefTitle)
                                Button { vm.copyRequestDiagnostics() } label: {
                                    Label("完整",
                                          systemImage: ResultDiagnosticsCommand.systemImage)
                                }
                                .controlSize(.small)
                                .disabled(!resultCommandEnabled(.copyDiagnostics))
                                .help(ResultDiagnosticsCommand.title)
                            }
                        }
                    }

                    ResultOutputDisplay(state: vm.outputState,
                                        isStreaming: vm.isStreaming)
                }
                .padding(14)
            }
            .background(ResultOutputAutoScrollObserver(state: vm.outputState) {
                guard vm.shouldAutoScroll() else { return }
                proxy.scrollTo("output", anchor: .bottom)
            })
            .onChange(of: vm.isStreaming) {
                guard !vm.isStreaming else { return }
                vm.markFinalAutoScroll()
                withAnimation(.easeOut(duration: 0.12)) {
                    proxy.scrollTo("output", anchor: .bottom)
                }
            }
        }
    }

    private var sourceEditor: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label("原文", systemImage: "quote.opening")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                Spacer()
                Button { vm.resendEdited() } label: {
                    Label("重新发送", systemImage: "arrow.up.circle")
                        .font(.caption.weight(.medium))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.tint)
                .disabled(vm.isStreaming)
            }
            TextEditor(text: $vm.sourceText)
                .font(.callout).scrollContentBackground(.hidden)
                .frame(minHeight: 34, maxHeight: 92)
                .padding(8)
                .background(Color.primary.opacity(0.045))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.primary.opacity(0.06), lineWidth: 1))
                .disabled(vm.isStreaming)
        }
    }

    // MARK: - Footer

    private var footer: some View {
        VStack(spacing: 6) {
            ResultOperationFeedbackHost(coordinator: vm.operationCoordinator)

            ResultCompletionMetricsRow(
                state: vm.completionState,
                privacyStatus: vm.privacyProtectionStatusText,
                canCopyBriefDiagnostics: resultCommandEnabled(.copyBriefDiagnostics),
                onCopyBriefDiagnostics: vm.copyBriefRequestDiagnostics
            )

            HStack(spacing: 8) {
                FollowUpField(text: $vm.followUp, onSubmit: vm.sendFollowUp,
                              onHistoryUp: vm.followUpHistoryUp,
                              onHistoryDown: vm.followUpHistoryDown,
                              shouldHandleHistoryNavigation: { text, direction in
                                  vm.shouldHandleFollowUpHistoryNavigation(currentText: text,
                                                                           direction: direction)
                              })
                    .disabled(vm.isStreaming)

                Button { vm.sendFollowUp() } label: {
                    Image(systemName: "paperplane.fill")
                }
                .buttonStyle(SnapAIIconButtonStyle(size: 30, circular: false))
                .keyboardShortcut(.return, modifiers: [.command, .option])
                .help("发送追问 (⌘⌥↩)")
                .accessibilityLabel("发送追问")
                .disabled(!canSendFollowUp)
            }

            ResultActionsToolbar(vm: vm, outputState: vm.outputState)
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
    }

    private var canSendFollowUp: Bool {
        !vm.isStreaming && !vm.followUp.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var errorRetryButton: some View {
        Button { vm.retry() } label: {
            Label(vm.errorRecoveryRetryDescriptor.compactTitle,
                  systemImage: vm.errorRecoveryRetryDescriptor.systemImage)
        }
        .controlSize(.small)
        .help("\(vm.errorRecoveryRetryDescriptor.title): \(vm.errorRecoveryRetryDescriptor.subtitle)")
    }

    private var errorSettingsButton: some View {
        Button { onOpenAISettings() } label: {
            Label(vm.errorRecoverySettingsDescriptor.compactTitle,
                  systemImage: vm.errorRecoverySettingsDescriptor.systemImage)
        }
        .controlSize(.small)
        .help("\(vm.errorRecoverySettingsDescriptor.title): \(vm.errorRecoverySettingsDescriptor.subtitle)")
    }

    private var resultCommandState: ResultCommandState {
        ResultCommandState(resultText: vm.completeText,
                           diagnosticsText: vm.requestDiagnosticText,
                           isStreaming: vm.isStreaming,
                           sourceText: vm.sourceText,
                           protectsContentExport: vm.contentExportProtectionEnabled,
                           recoveryCode: vm.errorRecoveryCode)
    }

    private func resultCommandEnabled(_ action: ResultCommandAction) -> Bool {
        ResultCommandFactory.isEnabled(action, in: resultCommandState)
    }

}

// MARK: - 追问框(#5 支持↑/↓浏览历史)

struct FollowUpField: View {
    @Binding var text: String
    var onSubmit: () -> Void
    var onHistoryUp: () -> Void
    var onHistoryDown: () -> Void
    var shouldHandleHistoryNavigation: (String, FollowUpHistoryNavigationDirection) -> Bool

    var body: some View {
        ZStack(alignment: .topLeading) {
            FollowUpTextView(text: $text,
                             onSubmit: onSubmit,
                             onHistoryUp: onHistoryUp,
                             onHistoryDown: onHistoryDown,
                             shouldHandleHistoryNavigation: shouldHandleHistoryNavigation)
                .frame(minHeight: CGFloat(FollowUpInputBehavior.minHeight),
                       maxHeight: CGFloat(FollowUpInputBehavior.maxHeight))

            if text.isEmpty {
                Text(FollowUpInputBehavior.placeholder)
                    .font(.callout)
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .allowsHitTesting(false)
            }
        }
        .background(Color.primary.opacity(0.045))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.primary.opacity(0.06), lineWidth: 1))
        .help(FollowUpInputBehavior.helpText)
        .accessibilityLabel(FollowUpInputBehavior.accessibilityLabel)
        .accessibilityHint(FollowUpInputBehavior.helpText)
    }
}

private struct FollowUpTextView: NSViewRepresentable {
    @Binding var text: String
    var onSubmit: () -> Void
    var onHistoryUp: () -> Void
    var onHistoryDown: () -> Void
    var shouldHandleHistoryNavigation: (String, FollowUpHistoryNavigationDirection) -> Bool
    @Environment(\.isEnabled) private var isEnabled

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasHorizontalScroller = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.toolTip = FollowUpInputBehavior.helpText
        scrollView.setAccessibilityLabel(FollowUpInputBehavior.accessibilityLabel)
        scrollView.setAccessibilityHelp(FollowUpInputBehavior.helpText)

        let textView = NSTextView()
        textView.delegate = context.coordinator
        textView.drawsBackground = false
        textView.isRichText = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isHorizontallyResizable = false
        textView.isVerticallyResizable = true
        textView.autoresizingMask = [.width]
        textView.textContainerInset = NSSize(width: 7, height: 6)
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(width: 0,
                                                       height: CGFloat.greatestFiniteMagnitude)
        textView.font = NSFont.systemFont(ofSize: NSFont.systemFontSize)
        textView.string = text
        textView.toolTip = FollowUpInputBehavior.helpText
        textView.setAccessibilityLabel(FollowUpInputBehavior.accessibilityLabel)
        textView.setAccessibilityHelp(FollowUpInputBehavior.helpText)

        scrollView.documentView = textView
        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let textView = nsView.documentView as? NSTextView else { return }
        if textView.string != text {
            textView.string = text
        }
        textView.isEditable = isEnabled
        textView.textColor = isEnabled ? .labelColor : .disabledControlTextColor
        textView.toolTip = FollowUpInputBehavior.helpText
        textView.setAccessibilityLabel(FollowUpInputBehavior.accessibilityLabel)
        textView.setAccessibilityHelp(FollowUpInputBehavior.helpText)
        nsView.toolTip = FollowUpInputBehavior.helpText
        nsView.setAccessibilityLabel(FollowUpInputBehavior.accessibilityLabel)
        nsView.setAccessibilityHelp(FollowUpInputBehavior.helpText)
        context.coordinator.parent = self
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: FollowUpTextView
        init(_ parent: FollowUpTextView) { self.parent = parent }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            parent.text = textView.string
        }

        func textView(_ textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            if selector == #selector(NSResponder.insertNewline(_:)) {
                let flags = NSApp.currentEvent?.modifierFlags ?? []
                let behavior = FollowUpInputBehavior.returnKeyBehavior(
                    shift: flags.contains(.shift),
                    option: flags.contains(.option)
                )
                if behavior == .insertNewline {
                    textView.insertText("\n", replacementRange: textView.selectedRange())
                } else {
                    parent.onSubmit()
                }
                return true
            }
            if selector == #selector(NSResponder.moveUp(_:)) {
                if parent.shouldHandleHistoryNavigation(textView.string, .up) {
                    parent.onHistoryUp()
                    return true
                }
                return false
            }
            if selector == #selector(NSResponder.moveDown(_:)) {
                if parent.shouldHandleHistoryNavigation(textView.string, .down) {
                    parent.onHistoryDown()
                    return true
                }
                return false
            }
            return false
        }
    }
}
