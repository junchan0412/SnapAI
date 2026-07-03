import SwiftUI
import Combine
import AppKit

/// 浮动结果窗口的状态机
@MainActor
final class ResultViewModel: ObservableObject {

    @Published var sourceText: String = ""
    @Published var output: String = ""
    @Published var isStreaming: Bool = false
    @Published var errorMessage: String?
    @Published var followUp: String = ""
    @Published var isPinned: Bool = false
    @Published var action: AIAction = AIAction()
    @Published var targetLanguage: TargetLanguage = .auto
    @Published var elapsed: TimeInterval = 0
    @Published var charCount: Int = 0
    @Published var activeProviderName: String = ""
    @Published var activeModelName: String = ""
    @Published var routeNote: String?
    @Published var requestDiagnosticText: String = ""
    @Published var requestDiagnosticBriefText: String = ""
    /// #2 Thinking/推理文本(Anthropic 或 DeepSeek R1 的 <think> 内容)
    @Published var thinkingText: String = ""
    @Published var showThinking: Bool = false
    @Published var showRouteDetails: Bool = false

    let settings: AppSettings
    private var client: AIClient
    private var history: [ChatMessage] = []
    private var startTime: Date?
    private var savedToHistory = false
    private var metricsFinished = false
    private var autoReplaceEnabled = false
    private var replacementOriginalText: String = ""
    private var submissionPrivacy: PrivacySubmissionDiagnostic?
    private var requestDiagnostics: AIRequestDiagnostics?
    private var streamAccumulator = StreamingAccumulator()

    // 打字机
    private var streamDone: Bool = false
    private var typewriterTimer: Timer?
    private var charsPerTick: Int { settings.typewriterSpeed.charsPerTick }
    private var tickInterval: TimeInterval { settings.typewriterSpeed.tickInterval }
    private var fullText: String {
        get { streamAccumulator.outputText }
        set { streamAccumulator.outputText = newValue }
    }

    // #5 追问历史(↑/↓ 浏览)
    private var followUpHistory = FollowUpHistoryStore()
    var followUpHistoryCount: Int { followUpHistory.count }

    /// #3 替换原文回调
    var onReplace: ((String, String) -> Void)?
    /// #8 追加回调
    var onAppend: ((String) -> Void)?
    /// 追问发送前的隐私处理/确认回调,由 AppDelegate 提供系统 UI。
    var prepareFollowUpSubmission: ((String, AIAction) -> PrivacyPreparedSubmission?)?
    /// 原文重发/动作切换前的隐私处理/确认回调。
    var prepareSourceSubmission: ((String, AIAction) -> PrivacyPreparedSubmission?)?

    init(settings: AppSettings) {
        self.settings = settings
        self.client = AIClient(settings: settings)
    }

    // #3 图片(来自截图/粘贴)
    private var pendingImageData: Data? = nil
    private var pendingImageMimeType: String = "image/png"
    private var pendingCaptureMethod: TextCaptureMethod?
    private var pendingSourceContext: SelectionSourceContext?

    var completeText: String { fullText }
    var isTranslation: Bool { action.isTranslation }
    var privacyProtectionStatusText: String? {
        submissionPrivacy?.protectionSummaryText
    }
    var contentExportProtectionEnabled: Bool {
        submissionPrivacy?.contentExportProtectionEnabled == true
    }
    var errorRecoverySuggestionText: String? {
        AIRequestDiagnostics.visibleErrorRecoverySuggestion(diagnostics: requestDiagnostics,
                                                            errorMessage: errorMessage)
    }
    var errorRecoveryCode: String? {
        AIRequestDiagnostics.visibleErrorRecoveryCode(diagnostics: requestDiagnostics,
                                                      errorMessage: errorMessage)
    }
    var errorRecoverySettingsDescriptor: ResultRecoverySettingsDescriptor {
        ResultRecoveryCommand.openAISettingsDescriptor(recoveryCode: errorRecoveryCode)
    }
    var errorRecoveryRetryDescriptor: ResultRecoveryRetryDescriptor {
        ResultRecoveryCommand.retryDescriptor(recoveryCode: errorRecoveryCode)
    }
    var errorRecoveryPrimaryAction: ResultRecoveryPrimaryAction {
        ResultRecoveryCommand.primaryAction(recoveryCode: errorRecoveryCode)
    }
    var requestHealthStatusText: String {
        requestDiagnostics?.healthStatusLine ?? "none"
    }
    var routeExplanationText: String? {
        requestDiagnostics?.visibleRouteExplanation
    }
    var routeStatusTitle: String {
        requestDiagnostics?.visibleRouteStatusTitle ?? (settings.autoRouteEnabled ? "自动路由" : "固定模型")
    }
    var activeContextSummaryText: String? {
        guard settings.contextStatusSummary.hasActiveContext else { return nil }
        let summary = settings.contextStatusSummary
        return "\(summary.activeProfileName) · \(summary.activeContextCharacterCount) 字"
    }

    // MARK: - 启动

    func start(text: String,
               originalText: String? = nil,
               action: AIAction,
               imageData: Data? = nil,
               imageMimeType: String = "image/png",
               submissionPrivacy: PrivacySubmissionDiagnostic? = nil,
               autoReplaceEnabled: Bool = false,
               captureMethod: TextCaptureMethod? = nil,
               sourceContext: SelectionSourceContext? = nil) {
        self.action = action
        self.targetLanguage = action.targetLanguage
        self.sourceText = text
        self.replacementOriginalText = originalText ?? text
        self.pendingImageData = imageData
        self.pendingImageMimeType = imageMimeType
        self.pendingCaptureMethod = captureMethod
        self.pendingSourceContext = sourceContext
        self.submissionPrivacy = submissionPrivacy
        self.autoReplaceEnabled = autoReplaceEnabled
        thinkingText = ""
        showThinking = false
        showRouteDetails = false
        resetOutput()
        history = []
        sendInitial()
    }

    func resendEdited() {
        guard !isStreaming, !sourceText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        var currentAction = action
        currentAction.targetLanguage = targetLanguage
        guard let prepared = preparedSourceSubmission(for: sourceText, action: currentAction) else { return }
        action = currentAction
        sourceText = prepared.text
        submissionPrivacy = prepared.diagnostic
        history = []
        thinkingText = ""
        resetOutput()
        sendInitial()
    }

    func changeLanguage(_ lang: TargetLanguage) {
        var nextAction = action
        nextAction.targetLanguage = lang
        guard let prepared = preparedSourceSubmission(for: sourceText, action: nextAction) else { return }
        targetLanguage = lang
        action = nextAction
        sourceText = prepared.text
        submissionPrivacy = prepared.diagnostic
        history = []
        thinkingText = ""
        resetOutput()
        sendInitial()
    }

    /// #4 切换到另一个动作,对相同原文重新发起
    func switchAction(_ newAction: AIAction) {
        guard let prepared = preparedSourceSubmission(for: sourceText, action: newAction) else { return }
        action = newAction
        targetLanguage = newAction.targetLanguage
        sourceText = prepared.text
        submissionPrivacy = prepared.diagnostic
        thinkingText = ""
        showThinking = false
        history = []
        resetOutput()
        sendInitial()
    }

    private func sendInitial() {
        let payload = RequestSession.initialMessages(settings: settings,
                                                     action: action,
                                                     targetLanguage: targetLanguage,
                                                     sourceText: sourceText,
                                                     imageData: pendingImageData,
                                                     imageMimeType: pendingImageMimeType,
                                                     sourceContext: pendingSourceContext)
        pendingImageData = nil
        history = payload.messages
        runStream(hasImage: payload.hasImage)
    }

    private func preparedSourceSubmission(for text: String,
                                          action: AIAction) -> PrivacyPreparedSubmission? {
        if let prepareSourceSubmission {
            return prepareSourceSubmission(text, action)
        }
        let risk = PrivacyRiskAssessment.assess(originalText: text,
                                                redactionPreview: PrivacyRedactionPreview(output: text, reports: []),
                                                redactionEnabled: false,
                                                hasImage: false,
                                                saveHistoryEnabled: action.saveHistory,
                                                historyContentStorage: settings.historyContentStorage)
        return PrivacyPreparedSubmission(
            text: text,
            diagnostic: PrivacySubmissionDiagnostic(originalCharacterCount: text.count,
                                                    submittedCharacterCount: text.count,
                                                    hasImage: false,
                                                    redactionEnabled: false,
                                                    redactionMatchCount: 0,
                                                    invalidRedactionRuleCount: 0,
                                                    saveHistoryEnabled: action.saveHistory,
                                                    historyContentStorage: settings.historyContentStorage,
                                                    previewRequired: false,
                                                    riskAssessment: risk)
        )
    }

    // MARK: - 追问

    func sendFollowUp() {
        let q = followUp.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty, !isStreaming else { return }
        let prepared: PrivacyPreparedSubmission
        if let prepareFollowUpSubmission {
            guard let confirmed = prepareFollowUpSubmission(q, action) else { return }
            prepared = confirmed
        } else {
            let risk = PrivacyRiskAssessment.assess(originalText: q,
                                                    redactionPreview: PrivacyRedactionPreview(output: q, reports: []),
                                                    redactionEnabled: false,
                                                    hasImage: false,
                                                    saveHistoryEnabled: action.saveHistory,
                                                    historyContentStorage: settings.historyContentStorage)
            prepared = PrivacyPreparedSubmission(
                text: q,
                diagnostic: PrivacySubmissionDiagnostic(originalCharacterCount: q.count,
                                                        submittedCharacterCount: q.count,
                                                        hasImage: false,
                                                        redactionEnabled: false,
                                                        redactionMatchCount: 0,
                                                        invalidRedactionRuleCount: 0,
                                                        saveHistoryEnabled: action.saveHistory,
                                                        historyContentStorage: settings.historyContentStorage,
                                                        previewRequired: false,
                                                        riskAssessment: risk)
            )
        }
        // #5 追问历史
        followUpHistory.record(q)
        RequestSession.appendFollowUp(to: &history,
                                      assistantText: fullText,
                                      userText: prepared.text)
        submissionPrivacy = prepared.diagnostic
        followUp = ""
        thinkingText = ""
        resetOutput()
        runStream(hasImage: false)
    }

    /// #5 浏览追问历史
    func followUpHistoryUp() {
        if FollowUpInputBehavior.shouldBrowseHistory(currentText: followUp) {
            followUpHistory.resetNavigation()
        }
        guard let previous = followUpHistory.previous() else { return }
        followUp = previous
    }

    func followUpHistoryDown() {
        guard let next = followUpHistory.next() else { return }
        followUp = next
    }

    func shouldHandleFollowUpHistoryNavigation(currentText: String,
                                               direction: FollowUpHistoryNavigationDirection) -> Bool {
        followUpHistory.shouldHandleNavigation(currentText: currentText,
                                               direction: direction)
    }

    func regenerate() {
        guard !isStreaming else { return }
        thinkingText = ""
        resetOutput()
        runStream(hasImage: false)
    }

    /// #12 错误后重试
    func retry() {
        guard !isStreaming else { return }
        thinkingText = ""
        resetOutput()
        runStream(hasImage: false)
    }

    func cancel() {
        guard isStreaming else { return }
        client.cancel()
        stopTypewriter()
        output = fullText
        isStreaming = false
        finishMetrics(recordUsage: false, saveHistory: false)
    }

    func copyOutput() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(fullText, forType: .string)
    }

    func copyConversationMarkdown() {
        guard !fullText.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(conversationExport().markdown, forType: .string)
    }

    func copyRequestDiagnostics() {
        guard !requestDiagnosticText.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(requestDiagnosticText, forType: .string)
    }

    func copyBriefRequestDiagnostics() {
        guard !requestDiagnosticBriefText.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(requestDiagnosticBriefText, forType: .string)
    }

    /// #3 替换原文
    func replaceOriginal() {
        ResultWriteBackCoordinator.replace(original: replacementOriginalText,
                                           replacement: fullText,
                                           handler: onReplace)
    }

    /// #8 追加到文档
    func appendToDocument() {
        ResultWriteBackCoordinator.append(text: fullText,
                                          handler: onAppend)
    }

    func exportConversation() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "\(action.name)-\(Int(Date().timeIntervalSince1970)).md"
        panel.allowedContentTypes = [.init(filenameExtension: "md") ?? .text]
        if panel.runModal() == .OK, let url = panel.url {
            try? conversationExport().markdown.write(to: url, atomically: true, encoding: .utf8)
        }
    }

    private func conversationExport(date: Date = Date()) -> ConversationExport {
        ResultPersistence.conversationExport(
            actionName: action.name,
            sourceText: sourceText,
            outputText: completeText,
            providerName: activeProviderName,
            modelName: activeModelName,
            fallbackModelName: settings.model,
            elapsed: elapsed,
            diagnostics: requestDiagnostics,
            protectsContent: submissionPrivacy?.contentExportProtectionEnabled == true,
            date: date
        )
    }

    // MARK: - 内部

    private func resetOutput() {
        stopTypewriter()
        streamAccumulator.resetForFallback()
        output = ""
        thinkingText = ""
        showRouteDetails = false
        streamDone = false
        errorMessage = nil
        routeNote = nil
        requestDiagnostics = nil
        requestDiagnosticText = ""
        requestDiagnosticBriefText = ""
        elapsed = 0
        charCount = 0
        savedToHistory = false
        metricsFinished = false
        startTime = Date()
    }

    private func runStream(hasImage: Bool) {
        refreshSubmissionPayloadCharacterCounts()
        let contextDiagnostic = AIRequestContextDiagnostic.make(settings: settings)
        let requestHasImage = hasImage || history.contains { $0.imageData != nil }
        let payloadDiagnostic = AIRequestPayloadDiagnostic.make(messages: history,
                                                                explicitHasImage: requestHasImage)
        let actionPipeline = ActionPipelineDiagnostic.make(action: action,
                                                           settings: settings,
                                                           hasImage: requestHasImage,
                                                           captureMethod: pendingCaptureMethod,
                                                           sourceKind: pendingSourceContext?.kind)
        let routes = AIRequestRouter.candidates(settings: settings,
                                                action: action,
                                                sourceText: sourceText,
                                                hasImage: requestHasImage,
                                                routingTextCharacterCount: payloadDiagnostic.textCharacterCount,
                                                routingMetrics: RoutingMetricsStore.shared.snapshot())
        guard !routes.isEmpty else {
            errorMessage = "没有可用的 AI 供应商或模型,请在设置中启用至少一个模型。"
            let unavailableSummary = AIRequestDiagnostics.noCandidateRouteReasonSummary(providers: settings.providers)
            let unavailableRecovery = AIRequestDiagnostics.noCandidateRouteRecoverySuggestion(providers: settings.providers)
            updateRequestDiagnostics(AIRequestDiagnostics(actionName: action.name,
                                                          actionRequiresReasoning: action.thinkingMode,
                                                          sourceCharacterCount: sourceText.count,
                                                          hasImage: requestHasImage,
                                                          fallbackEnabled: settings.fallbackEnabled,
                                                          autoRouteEnabled: settings.autoRouteEnabled,
                                                          routingPreference: settings.routingPreference,
                                                          candidateCount: 0,
                                                          actionPipeline: actionPipeline,
                                                          context: contextDiagnostic,
                                                          payload: payloadDiagnostic,
                                                          submissionPrivacy: submissionPrivacy,
                                                          candidateRoutes: [],
                                                          candidateUnavailabilitySummary: unavailableSummary,
                                                          candidateUnavailabilityRecoverySuggestion: unavailableRecovery))
            return
        }
        let diagnostics = AIRequestDiagnostics(actionName: action.name,
                                               actionRequiresReasoning: action.thinkingMode,
                                               sourceCharacterCount: sourceText.count,
                                               hasImage: requestHasImage,
                                               fallbackEnabled: settings.fallbackEnabled,
                                               autoRouteEnabled: settings.autoRouteEnabled,
                                               routingPreference: settings.routingPreference,
                                               candidateCount: routes.count,
                                               actionPipeline: actionPipeline,
                                               context: contextDiagnostic,
                                               payload: payloadDiagnostic,
                                               submissionPrivacy: submissionPrivacy,
                                               candidateRoutes: routes)
        runRoute(at: 0, routes: routes, diagnostics: diagnostics)
    }

    private func refreshSubmissionPayloadCharacterCounts() {
        guard let submissionPrivacy else { return }
        let counts = RequestSession.payloadCharacterCounts(messages: history)
        self.submissionPrivacy = submissionPrivacy.withPayloadCharacterCounts(
            finalUserPromptCharacterCount: counts.finalUserPrompt,
            systemPromptCharacterCount: counts.systemPrompt
        )
    }

    private func runRoute(at index: Int,
                          routes: [AIRequestRoute],
                          diagnostics: AIRequestDiagnostics) {
        let route = routes[index]
        var routeDiagnostics = diagnostics
        let hasNextRoute = routes.indices.contains(index + 1)
        if routeDiagnostics.shouldSkipRouteBeforeRequest(route,
                                                         autoRouteEnabled: settings.autoRouteEnabled,
                                                         hasNextRoute: hasNextRoute) {
            routeDiagnostics.mark(route: route,
                                  status: .skipped,
                                  message: routeDiagnostics.routeSkipMessage(for: route))
            updateRequestDiagnostics(routeDiagnostics)
            routeNote = routeDiagnostics.routeSkipSwitchNote(for: route,
                                                             nextRoute: routes[index + 1])
            runRoute(at: index + 1, routes: routes, diagnostics: routeDiagnostics)
            return
        }
        routeDiagnostics.mark(route: route, status: .running)
        updateRequestDiagnostics(routeDiagnostics)

        guard let scoped = AIRequestRouter.scopedSettings(from: settings, route: route) else {
            routeDiagnostics.mark(route: route,
                                  status: .skipped,
                                  message: "路由模型不可用或供应商已禁用")
            updateRequestDiagnostics(routeDiagnostics)
            if hasNextRoute {
                runRoute(at: index + 1, routes: routes, diagnostics: routeDiagnostics)
            } else {
                errorMessage = "路由到的模型不可用,请检查供应商和模型设置。"
            }
            return
        }

        client = AIClient(settings: scoped)
        activeProviderName = route.providerName
        activeModelName = route.modelName
        routeNote = routeDiagnostics.routeDisplayNote(for: route)

        isStreaming = true
        streamDone = false
        startTime = Date()
        let routeStartedAt = startTime ?? Date()
        var firstTokenMilliseconds: Int?
        let typewriterOn = settings.typewriterSpeed != .off
        let thinkingEnabled = action.thinkingMode

        if typewriterOn { startTypewriter() }

        client.stream(messages: history, action: action) { [weak self] token in
            guard let self = self else { return }
            if firstTokenMilliseconds == nil {
                firstTokenMilliseconds = AIRequestAttemptDiagnostic.elapsedMilliseconds(since: routeStartedAt)
            }
            self.streamAccumulator.appendContentToken(token,
                                                      extractsThinkTags: thinkingEnabled)
            self.thinkingText = self.streamAccumulator.thinkingText
            if !typewriterOn { self.output = self.fullText }
        } onThinking: { [weak self] thinking in
            // Anthropic extended thinking 块
            guard let self = self else { return }
            self.streamAccumulator.appendExternalThinking(thinking)
            self.thinkingText = self.streamAccumulator.thinkingText
        } onComplete: { [weak self] error in
            guard let self = self else { return }
            self.streamAccumulator.finish()
            self.thinkingText = self.streamAccumulator.thinkingText
            self.streamDone = true
            if let error = error {
                let failure = FallbackRunner.routeFailure(
                    error: error,
                    outputText: self.fullText,
                    thinkingText: self.thinkingText,
                    routeStartedAt: routeStartedAt,
                    route: route,
                    routes: routes,
                    index: index,
                    diagnostics: routeDiagnostics,
                    fallbackEnabled: self.settings.fallbackEnabled
                )
                let failedDiagnostics = failure.diagnosticsMarkingFailure(routeDiagnostics,
                                                                          route: route)
                RoutingMetricsStore.shared.recordFailure(
                    route: route,
                    elapsedMilliseconds: failure.elapsedMilliseconds,
                    firstTokenMilliseconds: firstTokenMilliseconds,
                    reason: failure.safeErrorMessage
                )
                self.updateRequestDiagnostics(failedDiagnostics)
                if failure.decision.shouldTryNext {
                    self.stopTypewriter()
                    self.output = ""
                    self.streamAccumulator.resetForFallback()
                    self.thinkingText = self.streamAccumulator.thinkingText
                    self.errorMessage = nil
                    self.routeNote = route.fallbackSwitchNote
                    self.runRoute(at: index + 1, routes: routes, diagnostics: failedDiagnostics)
                    return
                }
                if let note = failure.decision.userNote {
                    self.routeNote = note
                }
                self.errorMessage = failure.safeErrorMessage
                self.stopTypewriter()
                self.output = self.fullText
                self.isStreaming = false
                self.finishMetrics(recordUsage: false, saveHistory: false)
            } else if !typewriterOn {
                var completedDiagnostics = routeDiagnostics
                completedDiagnostics.mark(route: route,
                                          status: .succeeded,
                                          elapsedMilliseconds: AIRequestAttemptDiagnostic.elapsedMilliseconds(since: routeStartedAt),
                                          outputCharacterCount: self.fullText.count)
                RoutingMetricsStore.shared.recordSuccess(
                    route: route,
                    elapsedMilliseconds: AIRequestAttemptDiagnostic.elapsedMilliseconds(since: routeStartedAt),
                    firstTokenMilliseconds: firstTokenMilliseconds
                )
                self.updateRequestDiagnostics(completedDiagnostics)
                self.output = self.fullText
                self.isStreaming = false
                self.finishMetrics(recordUsage: true, saveHistory: true)
            } else {
                var completedDiagnostics = routeDiagnostics
                completedDiagnostics.mark(route: route,
                                          status: .succeeded,
                                          elapsedMilliseconds: AIRequestAttemptDiagnostic.elapsedMilliseconds(since: routeStartedAt),
                                          outputCharacterCount: self.fullText.count)
                RoutingMetricsStore.shared.recordSuccess(
                    route: route,
                    elapsedMilliseconds: AIRequestAttemptDiagnostic.elapsedMilliseconds(since: routeStartedAt),
                    firstTokenMilliseconds: firstTokenMilliseconds
                )
                self.updateRequestDiagnostics(completedDiagnostics)
            }
        }
    }

    private func updateRequestDiagnostics(_ diagnostics: AIRequestDiagnostics) {
        requestDiagnostics = diagnostics
        requestDiagnosticText = diagnostics.summaryText
        requestDiagnosticBriefText = diagnostics.briefSummaryText
    }

    private func finishMetrics(recordUsage: Bool, saveHistory: Bool) {
        guard !metricsFinished else { return }
        metricsFinished = true
        let completion = ResultPersistence.completionMetrics(startTime: startTime,
                                                             outputText: fullText)
        elapsed = completion.elapsed
        charCount = completion.characterCount
        if recordUsage {
            // #11 使用统计
            settings.recordActionUsage(actionName: action.name)
        }
        if saveHistory && action.saveHistory {
            saveToHistoryIfNeeded()
        } else if recordUsage {
            settings.save()
        }
        if ResultWriteBackCoordinator.shouldAutoReplace(recordUsage: recordUsage,
                                                        autoReplaceEnabled: autoReplaceEnabled,
                                                        replaceByDefault: action.replaceByDefault,
                                                        outputText: fullText,
                                                        errorMessage: errorMessage) {
            autoReplaceEnabled = false
            ResultWriteBackCoordinator.replace(original: replacementOriginalText,
                                               replacement: fullText,
                                               handler: onReplace)
        }
    }

    private func saveToHistoryIfNeeded() {
        savedToHistory = ResultPersistence.saveHistoryIfNeeded(
            settings: settings,
            alreadySaved: savedToHistory,
            action: action,
            sourceText: sourceText,
            outputText: fullText,
            errorMessage: errorMessage,
            providerName: activeProviderName,
            fallbackProviderName: settings.activeProvider?.name ?? "",
            modelName: activeModelName,
            fallbackModelName: settings.model,
            historyTags: submissionPrivacy?.historyTags ?? [],
            contentStorage: submissionPrivacy?.effectiveHistoryContentStorage
        )
    }

    private func startTypewriter() {
        stopTypewriter()
        let timer = Timer(timeInterval: tickInterval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.tick()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        typewriterTimer = timer
    }

    private func tick() {
        if output.count < fullText.count {
            let target = min(output.count + charsPerTick, fullText.count)
            let endIdx = fullText.index(fullText.startIndex, offsetBy: target)
            output = String(fullText[fullText.startIndex..<endIdx])
        } else if streamDone {
            isStreaming = false
            typewriterTimer?.invalidate()
            typewriterTimer = nil
            finishMetrics(recordUsage: true, saveHistory: true)
        }
    }

    private func stopTypewriter() {
        typewriterTimer?.invalidate()
        typewriterTimer = nil
    }
}
