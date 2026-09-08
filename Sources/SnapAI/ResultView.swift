import SwiftUI
import AppKit
import SnapAILogic

struct ResultView: View {
    @ObservedObject var vm: ResultViewModel
    @ObservedObject private var settings: AppSettings
    var onClose: () -> Void
    var onOpenAISettings: () -> Void = {}

    @State private var isSourceExpanded = false
    @State private var followsOutput = true

    init(vm: ResultViewModel,
         onClose: @escaping () -> Void,
         onOpenAISettings: @escaping () -> Void = {}) {
        self.vm = vm
        self.settings = vm.settings
        self.onClose = onClose
        self.onOpenAISettings = onOpenAISettings
    }

    var body: some View {
        VStack(spacing: 0) {
            ResultWorkspaceHeader(
                action: vm.action,
                actions: settings.enabledActions,
                modelName: vm.activeModelName.isEmpty ? settings.model : vm.activeModelName,
                providerName: vm.activeProviderName,
                isStreaming: vm.isStreaming,
                hasError: vm.errorMessage != nil,
                isTranslation: vm.isTranslation,
                targetLanguage: vm.targetLanguage,
                isPinned: $vm.isPinned,
                onSwitchAction: vm.switchAction,
                onChangeLanguage: vm.changeLanguage,
                onClose: onClose
            )
            Divider()
            scrollContent
            Divider()
            footer
        }
        .frame(minWidth: 440, maxWidth: .infinity, minHeight: 460, maxHeight: .infinity)
        .background(SnapAIUI.Surface.canvas)
        .overlay(alignment: .top) {
            if vm.isStreaming {
                SnapAIStreamingProgressBar()
            }
        }
    }

    private var scrollContent: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    ResultSourceSection(text: $vm.sourceText,
                                        isExpanded: $isSourceExpanded,
                                        isStreaming: vm.isStreaming,
                                        onResend: vm.resendEdited)
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
                            guard followsOutput else { return }
                            vm.markFinalAutoScroll()
                            proxy.scrollTo("output", anchor: .bottom)
                        },
                        onCopyCode: vm.copyCodeBlock
                    )
                    .font(.system(size: 15))
                    .lineSpacing(4)
                }
                .frame(maxWidth: 820, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(SnapAIUI.edgePadding)
                .background(ResultScrollActivityObserver {
                    if vm.isStreaming { followsOutput = false }
                })
            }
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
        VStack(spacing: 12) {
            ResultOperationFeedbackHost(coordinator: vm.operationCoordinator)

            HStack(spacing: 8) {
                Button { vm.showRouteDetails.toggle() } label: {
                    Image(systemName: vm.showRouteDetails ? "info.circle.fill" : "info.circle")
                        .foregroundStyle(vm.showRouteDetails ? Color.accentColor : .secondary)
                }
                .buttonStyle(SnapAIIconButtonStyle(circular: false))
                .help(vm.showRouteDetails ? "收起请求详情" : "查看模型、路由、耗时与诊断")
                .accessibilityLabel(vm.showRouteDetails ? "收起请求详情" : "展开请求详情")
                .accessibilityIdentifier("SnapAI.Result.RequestDetails")
                .popover(isPresented: $vm.showRouteDetails, arrowEdge: .bottom) {
                    requestDetails
                        .frame(width: 360)
                        .padding(8)
                }

                if vm.isStreaming {
                    Button { followsOutput.toggle() } label: {
                        Image(systemName: followsOutput ? "arrow.down.to.line.compact" : "arrow.down.to.line")
                            .foregroundStyle(followsOutput ? Color.accentColor : .secondary)
                    }
                    .buttonStyle(SnapAIIconButtonStyle(circular: false))
                    .help(followsOutput ? "已跟随输出，点击暂停自动滚动" : "继续跟随最新输出")
                    .accessibilityLabel(followsOutput ? "暂停自动滚动" : "继续自动滚动")
                }
                Spacer(minLength: 0)
                ResultActionsToolbar(vm: vm, outputState: vm.outputState)
            }

            HStack(alignment: .bottom, spacing: 10) {
                FollowUpField(text: $vm.followUp,
                              onSubmit: vm.sendFollowUp,
                              onHistoryUp: vm.followUpHistoryUp,
                              onHistoryDown: vm.followUpHistoryDown,
                              historyAvailable: vm.followUpHistoryCount > 0,
                              shouldHandleHistoryNavigation: { text, direction in
                                  vm.shouldHandleFollowUpHistoryNavigation(currentText: text,
                                                                           direction: direction)
                              })
                    .disabled(vm.isStreaming)
                Button(action: vm.sendFollowUp) {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 14, weight: .semibold))
                        .frame(width: 18, height: 20)
                }
                .buttonStyle(SnapAIPrimaryButtonStyle())
                .keyboardShortcut(.return, modifiers: [.command, .option])
                .help("发送追问 (↩ 发送，⇧↩ 换行)")
                .accessibilityLabel("发送追问")
                .disabled(!canSendFollowUp)
            }
        }
        .padding(.horizontal, SnapAIUI.edgePadding)
        .padding(.vertical, 14)
        .background(SnapAIUI.Surface.chrome)
    }

    private var requestDetails: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("请求详情")
                    .font(SnapAIUI.Typography.sectionLabel)
                Spacer()
                Text(vm.routeStatusTitle)
                    .font(SnapAIUI.Typography.metaText)
                    .foregroundStyle(.secondary)
            }
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
        .padding(12)
        .background(SnapAIUI.Surface.quiet,
                    in: RoundedRectangle(cornerRadius: SnapAIUI.cardRadius, style: .continuous))
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
        !vm.isStreaming && !vm.followUp.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// 错误块:主恢复操作用主按钮强调,诊断类操作收纳为单一菜单,降低按钮密度。
    @ViewBuilder
    private func errorBlock(_ err: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(err, systemImage: "exclamationmark.triangle.fill")
                .font(.callout.weight(.medium))
                .foregroundStyle(SnapAIUI.StatusColor.error)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            if let recovery = vm.errorRecoverySuggestionText {
                Label(recovery, systemImage: "wrench.and.screwdriver")
                    .font(.caption)
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
                .help("复制请求诊断信息以便排查")
            }
        }
        .padding(SnapAIUI.compactPadding)
        .background(SnapAIUI.StatusColor.error.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: SnapAIUI.cardRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: SnapAIUI.cardRadius, style: .continuous)
                .stroke(SnapAIUI.StatusColor.error.opacity(0.18), lineWidth: 1)
        }
    }


    @ViewBuilder
    private func errorRetryButton(primary: Bool) -> some View {
        let label = Label(vm.errorRecoveryRetryDescriptor.compactTitle,
                          systemImage: vm.errorRecoveryRetryDescriptor.systemImage)
        let helpText = "\(vm.errorRecoveryRetryDescriptor.title): \(vm.errorRecoveryRetryDescriptor.subtitle)"
        if primary {
            Button { vm.retry() } label: { label }
                .buttonStyle(SnapAIPrimaryButtonStyle())
                .controlSize(.regular)
                .help(helpText)
        } else {
            Button { vm.retry() } label: { label }
                .buttonStyle(.bordered)
                .controlSize(.small)
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
                .buttonStyle(SnapAIPrimaryButtonStyle())
                .controlSize(.regular)
                .help(helpText)
        } else {
            Button { onOpenAISettings() } label: { label }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help(helpText)
        }
    }


    private var resultCommandState: ResultCommandState {
        ResultCommandState(resultText: vm.outputState.text,
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
