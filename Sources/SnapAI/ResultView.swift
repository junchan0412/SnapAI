import SwiftUI
import AppKit
import SnapAILogic

struct ResultView: View {
    @ObservedObject var vm: ResultViewModel
    @ObservedObject private var settings: AppSettings
    var onClose: () -> Void
    var onOpenAISettings: () -> Void = {}
    var onOpenModelCompare: (() -> Void)? = nil

    @State private var showConversationLibrary = false
    @State private var isSourceExpanded = false
    @State private var followsOutput = true
    @StateObject private var readingAnchor = ResultReadingAnchor()

    init(vm: ResultViewModel,
         onClose: @escaping () -> Void,
         onOpenAISettings: @escaping () -> Void = {},
         onOpenModelCompare: (() -> Void)? = nil) {
        self.vm = vm
        self.settings = vm.settings
        self.onClose = onClose
        self.onOpenAISettings = onOpenAISettings
        self.onOpenModelCompare = onOpenModelCompare
    }

    private var inlineThreadSnapshot: (priorTurns: [ConversationMessage], activeFollowUp: String?) {
        guard let session = vm.conversationSession else { return ([], nil) }
        let nonSystem = session.messages.filter { $0.role != .system }
        guard nonSystem.count > 1 else { return ([], nil) }
        if nonSystem.last?.role == .assistant {
            guard nonSystem.count > 2 else { return ([], nil) }
            let promptMsg = nonSystem[nonSystem.count - 2]
            let prompt = promptMsg.role == .user ? promptMsg.content : nil
            return (Array(nonSystem.dropLast(2)), prompt)
        } else if nonSystem.last?.role == .user {
            return (Array(nonSystem.dropLast(1)), nonSystem.last?.content)
        }
        return ([], nil)
    }

    var body: some View {
        VStack(spacing: 0) {
            ResultWorkspaceHeader(
                action: vm.action,
                actions: settings.enabledActions,
                modelName: vm.activeModelName.isEmpty ? settings.model : vm.activeModelName,
                providerName: vm.activeProviderName.isEmpty ? (settings.activeProvider?.name ?? "") : vm.activeProviderName,
                switchableModels: settings.switchableEntries,
                isStreaming: vm.isGenerating,
                isPresenting: vm.isPresenting,
                hasError: vm.errorMessage != nil,
                isTranslation: vm.isTranslation,
                targetLanguage: vm.targetLanguage,
                isPinned: $vm.isPinned,
                onSwitchAction: vm.switchAction,
                onSwitchModel: { providerID, model in
                    settings.activate(providerID: providerID, model: model, recordManualPreference: true)
                    if !vm.sourceText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || vm.hasSourceImage {
                        vm.regenerate()
                    }
                },
                onChangeLanguage: vm.changeLanguage,
                onOpenSavedSessions: { showConversationLibrary = true },
                onOpenModelCompare: onOpenModelCompare,
                onClose: onClose
            )

            ZStack(alignment: .top) {
                SnapAIFormDivider(inset: 0)
                if vm.isGenerating {
                    SnapAIStreamingProgressBar()
                }
            }

            scrollContent

            SnapAIFormDivider(inset: 0)
            footer
        }
        .frame(minWidth: 460, maxWidth: .infinity, minHeight: 460, maxHeight: .infinity)
        .snapAIFloatingPanelSurface()
        .sheet(isPresented: $showConversationLibrary) {
            ConversationLibraryView(settings: settings, restore: vm.restoreConversation)
        }
        .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification)) { _ in
            if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion { vm.revealFullOutput() }
        }
    }

    private var scrollContent: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    ResultSourceSection(text: $vm.sourceText,
                                        isExpanded: $isSourceExpanded,
                                        isStreaming: vm.isGenerating,
                                        hasImage: vm.hasSourceImage,
                                        onResend: vm.resendEdited)

                    let thread = inlineThreadSnapshot
                    if !thread.priorTurns.isEmpty || thread.activeFollowUp != nil || vm.conversationSession?.sourceImageData != nil {
                        ResultInlineConversationThread(
                            priorTurns: thread.priorTurns,
                            activeFollowUpPrompt: thread.activeFollowUp,
                            sourceImageData: vm.conversationSession?.sourceImageData,
                            isGenerating: vm.isGenerating,
                            onCopyCode: vm.copyCodeBlock,
                            onBranch: vm.branchConversation
                        )
                    }

                    ResultThinkingSection(state: vm.thinkingState, isExpanded: $vm.showThinking)

                    if let reason = vm.incompleteResultReason {
                        SnapAIIncompleteResultBanner(
                            title: reason.title,
                            systemImage: reason == .cancelled ? "stop.circle" : "exclamationmark.bubble",
                            onDismiss: vm.dismissIncompleteResultNotice
                        )
                    }
                    if let notice = vm.transientNotice {
                        SnapAITransientNoticeBanner(title: notice, onDismiss: vm.dismissTransientNotice)
                    }
                    if let error = vm.errorMessage {
                        errorBlock(error)
                    }

                    ResultOutputDisplay(
                        state: vm.outputState,
                        isStreaming: vm.isStreaming,
                        onMarkdownReady: {
                            vm.markMarkdownReady()
                            guard followsOutput else { readingAnchor.restore(); return }
                            vm.markFinalAutoScroll()
                            proxy.scrollTo("output", anchor: .bottom)
                        },
                        onCopyCode: vm.copyCodeBlock
                    )
                    .background(ResultReadingAnchorObserver(anchor: readingAnchor,
                        isStreaming: vm.isStreaming, followsOutput: followsOutput))
                    .font(SnapAIUI.Typography.readingText)
                    .lineSpacing(4.5)
                }
                .frame(maxWidth: 820, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .background(ResultScrollActivityObserver {
                    readingAnchor.cancel()
                    followsOutput = false
                })
            }
            .snapAIScrollEdge()
            .background(ResultOutputAutoScrollObserver(state: vm.outputState) {
                guard followsOutput, vm.shouldAutoScroll() else { return }
                var transaction = Transaction()
                transaction.disablesAnimations = true
                withTransaction(transaction) {
                    proxy.scrollTo("output", anchor: .bottom)
                }
            })
            .onChange(of: vm.isStreaming) {
                if vm.isStreaming {
                    followsOutput = true
                } else if followsOutput {
                    vm.markFinalAutoScroll()
                    proxy.scrollTo("output", anchor: .bottom)
                }
            }
            .onChange(of: followsOutput) {
                if followsOutput {
                    proxy.scrollTo("output", anchor: .bottom)
                }
            }
            .onChange(of: isSourceExpanded) {
                if isSourceExpanded { followsOutput = false }
            }
        }
    }

    private var footer: some View {
        VStack(spacing: 9) {
            ResultOperationFeedbackHost(coordinator: vm.operationCoordinator)

            SnapAIGlassToolbarGroup(spacing: 6) {
                Button { vm.showRouteDetails.toggle() } label: {
                    Image(systemName: vm.showRouteDetails ? "info.circle.fill" : "info.circle")
                        .foregroundStyle(vm.showRouteDetails ? Color.accentColor : .secondary)
                }
                .buttonStyle(SnapAIIconButtonStyle(size: 26, circular: false))
                .help(vm.showRouteDetails ? "收起请求详情" : "查看路由、耗时与诊断")
                .accessibilityLabel(vm.showRouteDetails ? SnapAIL10n.string("Hide request details") : SnapAIL10n.string("View model, route, timing and diagnostics"))
                .accessibilityIdentifier("SnapAI.Result.RequestDetails")
                .popover(isPresented: $vm.showRouteDetails, arrowEdge: .bottom) {
                    requestDetails
                        .frame(width: 340)
                        .padding(12)
                }

                ResultInlineMetricsLabel(state: vm.completionState)

                if vm.isStreaming {
                    Button { followsOutput.toggle() } label: {
                        Image(systemName: followsOutput ? "arrow.down.to.line.compact" : "arrow.down.to.line")
                            .foregroundStyle(followsOutput ? Color.accentColor : .secondary)
                    }
                    .buttonStyle(SnapAIIconButtonStyle(size: 26, circular: false))
                    .help(followsOutput ? "已跟随输出，点击暂停自动滚动" : "继续跟随最新输出")
                    .accessibilityLabel(followsOutput ? "暂停自动滚动" : "继续自动滚动")
                }

                Spacer(minLength: 4)

                ResultActionsToolbar(vm: vm,
                                     outputState: vm.outputState,
                                     onOpenModelCompare: onOpenModelCompare)
            }

            FollowUpField(text: $vm.followUp,
                          canSend: canSendFollowUp,
                          onSubmit: vm.sendFollowUp,
                          onHistoryUp: vm.followUpHistoryUp,
                          onHistoryDown: vm.followUpHistoryDown,
                          historyAvailable: vm.followUpHistoryCount > 0,
                          shouldHandleHistoryNavigation: { text, direction in
                              vm.shouldHandleFollowUpHistoryNavigation(currentText: text,
                                                                       direction: direction)
                          })
                .disabled(vm.isGenerating)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .snapAIChrome()
    }

    private var requestDetails: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(SnapAIL10n.string("Request Details"))
                    .font(SnapAIUI.Typography.sectionTitle)
                Spacer()
                Text(vm.routeStatusTitle)
                    .font(SnapAIUI.Typography.metaText)
                    .foregroundStyle(.secondary)
            }
            SnapAIFormDivider(inset: 0)
            Text(routeStatusText.primaryText)
                .font(SnapAIUI.Typography.metaText)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
            ForEach(routeStatusText.detailLines, id: \.self) { line in
                Text(line)
                    .font(SnapAIUI.Typography.metaText)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
            ResultCompletionMetricsRow(
                state: vm.completionState,
                privacyStatus: vm.privacyProtectionStatusText,
                canCopyBriefDiagnostics: resultCommandEnabled(.copyBriefDiagnostics),
                onCopyBriefDiagnostics: vm.copyBriefRequestDiagnostics
            )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var routeStatusText: ResultRouteStatusText {
        ResultRouteStatusText.make(providerName: vm.activeProviderName,
                                   modelName: vm.activeModelName,
                                   fallbackModelName: vm.settings.model,
                                   contextSummary: vm.activeContextSummaryText,
                                   routeExplanation: vm.routeExplanationText,
                                   routeNote: vm.routeNote)
    }

    private var canSendFollowUp: Bool {
        !vm.isGenerating && !vm.followUp.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    @ViewBuilder
    private func errorBlock(_ err: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(err, systemImage: "exclamationmark.triangle.fill")
                .font(SnapAIUI.Typography.bodyText.weight(.medium))
                .foregroundStyle(SnapAIUI.StatusColor.error)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            if let recovery = vm.errorRecoverySuggestionText {
                Text(recovery)
                    .font(SnapAIUI.Typography.metaText)
                    .foregroundStyle(.secondary)
                    .lineLimit(4)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            HStack(spacing: 8) {
                if vm.errorRecoveryPrimaryAction == .settings {
                    errorSettingsButton(primary: true)
                    errorRetryButton(primary: false)
                } else {
                    errorRetryButton(primary: true)
                    errorSettingsButton(primary: false)
                }
                Spacer(minLength: 0)
                Menu {
                    Button { vm.copyBriefRequestDiagnostics() } label: {
                        Label(ResultDiagnosticsCommand.briefTitle,
                              systemImage: ResultDiagnosticsCommand.systemImage)
                    }
                    .disabled(!resultCommandEnabled(.copyBriefDiagnostics))
                    Button { vm.copyRequestDiagnostics() } label: {
                        Label(ResultDiagnosticsCommand.title,
                              systemImage: ResultDiagnosticsCommand.systemImage)
                    }
                    .disabled(!resultCommandEnabled(.copyDiagnostics))
                } label: {
                    Label("诊断", systemImage: "stethoscope")
                }
                .controlSize(.small)
                .help("复制请求诊断信息")
            }
        }
        .padding(12)
        .background(SnapAIUI.StatusColor.error.opacity(0.07),
                    in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .strokeBorder(SnapAIUI.StatusColor.error.opacity(0.20), lineWidth: 0.75)
        }
    }

    @ViewBuilder
    private func errorRetryButton(primary: Bool) -> some View {
        let label = Label(vm.errorRecoveryRetryDescriptor.compactTitle,
                          systemImage: vm.errorRecoveryRetryDescriptor.systemImage)
        let helpText = "\(vm.errorRecoveryRetryDescriptor.title): \(vm.errorRecoveryRetryDescriptor.subtitle)"
        if primary {
            Button { vm.retry() } label: { label }
                .buttonStyle(SnapAIPrimaryButtonStyle(compact: true))
                .help(helpText)
        } else {
            Button { vm.retry() } label: { label }
                .buttonStyle(SnapAISecondaryButtonStyle(compact: true))
                .help(helpText)
        }
    }

    @ViewBuilder
    private func errorSettingsButton(primary: Bool) -> some View {
        let label = Label(vm.errorRecoverySettingsDescriptor.compactTitle,
                          systemImage: vm.errorRecoverySettingsDescriptor.systemImage)
        let helpText = "\(vm.errorRecoverySettingsDescriptor.title): \(vm.errorRecoverySettingsDescriptor.subtitle)"
        if primary {
            Button { onOpenAISettings() } label: { label }
                .buttonStyle(SnapAIPrimaryButtonStyle(compact: true))
                .help(helpText)
        } else {
            Button { onOpenAISettings() } label: { label }
                .buttonStyle(SnapAISecondaryButtonStyle(compact: true))
                .help(helpText)
        }
    }

    private var resultCommandState: ResultCommandState {
        ResultCommandState(resultText: vm.outputState.text,
                           diagnosticsText: vm.requestDiagnosticText,
                           isStreaming: vm.isGenerating,
                           sourceText: vm.sourceText,
                           protectsContentExport: vm.contentExportProtectionEnabled,
                           recoveryCode: vm.errorRecoveryCode)
    }

    private func resultCommandEnabled(_ action: ResultCommandAction) -> Bool {
        ResultCommandFactory.isEnabled(action, in: resultCommandState)
    }
}
