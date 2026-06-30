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

    // 打字机
    private var fullText: String = ""
    private var streamDone: Bool = false
    private var typewriterTimer: Timer?
    private var charsPerTick: Int { settings.typewriterSpeed.charsPerTick }
    private var tickInterval: TimeInterval { settings.typewriterSpeed.tickInterval }

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

    // MARK: - 启动

    func start(text: String,
               originalText: String? = nil,
               action: AIAction,
               imageData: Data? = nil,
               imageMimeType: String = "image/png",
               submissionPrivacy: PrivacySubmissionDiagnostic? = nil,
               autoReplaceEnabled: Bool = false) {
        self.action = action
        self.targetLanguage = action.targetLanguage
        self.sourceText = text
        self.replacementOriginalText = originalText ?? text
        self.pendingImageData = imageData
        self.pendingImageMimeType = imageMimeType
        self.submissionPrivacy = submissionPrivacy
        self.autoReplaceEnabled = autoReplaceEnabled
        thinkingText = ""
        showThinking = false
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
        var act = action
        act.targetLanguage = targetLanguage
        let userContent = act.render(text: sourceText)
        let hasImage = pendingImageData != nil

        var messages: [ChatMessage] = []
        let systemPrompt = settings.effectiveSystemPrompt
        if !systemPrompt.isEmpty {
            messages.append(ChatMessage(role: .system, content: systemPrompt))
        }
        // #3 图片内容挂载到第一条 user 消息
        var userMsg = ChatMessage(role: .user, content: userContent)
        if let img = pendingImageData {
            userMsg.imageData = img
            userMsg.imageMimeType = pendingImageMimeType
            pendingImageData = nil
        }
        messages.append(userMsg)
        history = messages
        runStream(hasImage: hasImage)
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
        if !fullText.isEmpty {
            history.append(ChatMessage(role: .assistant, content: fullText))
        }
        history.append(ChatMessage(role: .user, content: prepared.text))
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
        guard !fullText.isEmpty else { return }
        onReplace?(replacementOriginalText, fullText)
    }

    /// #8 追加到文档
    func appendToDocument() {
        guard !fullText.isEmpty else { return }
        onAppend?(fullText)
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
        ConversationExport(actionName: action.name,
                           sourceText: sourceText,
                           outputText: completeText,
                           providerName: activeProviderName,
                           modelName: activeModelName.isEmpty ? settings.model : activeModelName,
                           elapsed: elapsed,
                           diagnostics: requestDiagnostics?.summaryText(includeAttemptMessages: false) ?? "",
                           protectsContent: submissionPrivacy?.contentExportProtectionEnabled == true,
                           date: date)
    }

    // MARK: - 内部

    private func resetOutput() {
        stopTypewriter()
        fullText = ""
        output = ""
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
        let contextDiagnostic = AIRequestContextDiagnostic.make(settings: settings)
        let requestHasImage = hasImage || history.contains { $0.imageData != nil }
        let payloadDiagnostic = AIRequestPayloadDiagnostic.make(messages: history,
                                                                explicitHasImage: requestHasImage)
        let actionPipeline = ActionPipelineDiagnostic.make(action: action,
                                                           settings: settings,
                                                           hasImage: requestHasImage)
        let routes = AIRequestRouter.candidates(settings: settings,
                                                action: action,
                                                sourceText: sourceText,
                                                hasImage: requestHasImage,
                                                routingTextCharacterCount: payloadDiagnostic.textCharacterCount)
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
        let typewriterOn = settings.typewriterSpeed != .off
        let thinkingEnabled = action.thinkingMode

        if typewriterOn { startTypewriter() }

        // #2 DeepSeek R1 <think> tag 状态机
        var inThinkTag = false
        var thinkBuffer = ""

        client.stream(messages: history, action: action) { [weak self] token in
            guard let self = self else { return }
            if thinkingEnabled {
                // 检测 <think> 标签(DeepSeek R1 style)
                var remaining = thinkBuffer + token
                thinkBuffer = ""
                while !remaining.isEmpty {
                    if inThinkTag {
                        if let end = remaining.range(of: "</think>") {
                            self.thinkingText += String(remaining[remaining.startIndex..<end.lowerBound])
                            remaining = String(remaining[end.upperBound...])
                            inThinkTag = false
                        } else if remaining.hasSuffix("<") || remaining.hasSuffix("</") {
                            thinkBuffer = remaining
                            remaining = ""
                        } else {
                            self.thinkingText += remaining
                            remaining = ""
                        }
                    } else {
                        if let start = remaining.range(of: "<think>") {
                            self.fullText += String(remaining[remaining.startIndex..<start.lowerBound])
                            remaining = String(remaining[start.upperBound...])
                            inThinkTag = true
                        } else {
                            self.fullText += remaining
                            remaining = ""
                        }
                    }
                }
            } else {
                self.fullText += token
            }
            if !typewriterOn { self.output = self.fullText }
        } onThinking: { [weak self] thinking in
            // Anthropic extended thinking 块
            self?.thinkingText += thinking
        } onComplete: { [weak self] error in
            guard let self = self else { return }
            self.streamDone = true
            if let error = error {
                let safeErrorMessage = SensitiveTextSanitizer.sanitizedMessage(error.localizedDescription)
                let outputCharacterCount = self.fullText.count
                let nextRoute = routes.indices.contains(index + 1) ? routes[index + 1] : nil
                let fallbackDecision = AIRequestFallbackDecision.decide(
                    fallbackEnabled: self.settings.fallbackEnabled,
                    hasNextRoute: nextRoute != nil,
                    outputCharacterCount: outputCharacterCount,
                    requiresCloudFallbackConfirmation: routeDiagnostics.requiresCloudFallbackConfirmation(from: route,
                                                                                                          to: nextRoute)
                )
                var failedDiagnostics = routeDiagnostics
                failedDiagnostics.mark(route: route,
                                       status: .failed,
                                       message: safeErrorMessage,
                                       elapsedMilliseconds: AIRequestAttemptDiagnostic.elapsedMilliseconds(since: routeStartedAt),
                                       outputCharacterCount: outputCharacterCount,
                                       fallbackDecision: fallbackDecision)
                self.updateRequestDiagnostics(failedDiagnostics)
                if fallbackDecision.shouldTryNext {
                    self.stopTypewriter()
                    self.output = ""
                    self.errorMessage = nil
                    self.routeNote = route.fallbackSwitchNote
                    self.runRoute(at: index + 1, routes: routes, diagnostics: failedDiagnostics)
                    return
                }
                if let note = fallbackDecision.userNote {
                    self.routeNote = note
                }
                self.errorMessage = safeErrorMessage
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
        if let start = startTime { elapsed = Date().timeIntervalSince(start) }
        charCount = fullText.count
        if recordUsage {
            // #11 使用统计
            settings.recordActionUsage(actionName: action.name)
        }
        if saveHistory && action.saveHistory {
            saveToHistoryIfNeeded()
        } else if recordUsage {
            settings.save()
        }
        if recordUsage,
           autoReplaceEnabled,
           action.replaceByDefault,
           !fullText.isEmpty,
           errorMessage == nil {
            autoReplaceEnabled = false
            onReplace?(replacementOriginalText, fullText)
        }
    }

    private func saveToHistoryIfNeeded() {
        guard !savedToHistory, !fullText.isEmpty, errorMessage == nil else { return }
        savedToHistory = true
        settings.addHistory(action: action.name, source: sourceText, output: fullText,
                            provider: activeProviderName.isEmpty ? (settings.activeProvider?.name ?? "") : activeProviderName,
                            model: activeModelName.isEmpty ? settings.model : activeModelName,
                            tags: submissionPrivacy?.historyTags ?? [],
                            contentStorage: submissionPrivacy?.effectiveHistoryContentStorage)
    }

    private func startTypewriter() {
        stopTypewriter()
        let timer = Timer(timeInterval: tickInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
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
