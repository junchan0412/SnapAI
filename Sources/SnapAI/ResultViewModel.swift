import Combine
import AppKit
import SnapAILogic

/// 浮动结果窗口的状态机
@MainActor
final class ResultViewModel: ObservableObject {

    @Published var sourceText: String = ""
    @Published var isStreaming: Bool = false
    @Published var errorMessage: String?
    @Published var followUp: String = ""
    @Published var isPinned: Bool = false
    @Published var action: AIAction = AIAction()
    @Published var targetLanguage: TargetLanguage = .auto
    @Published var activeProviderName: String = ""
    @Published var activeModelName: String = ""
    @Published var routeNote: String?
    @Published private var diagnosticText: ResultDiagnosticTextSnapshot = .empty
    let outputState = ResultOutputState()
    let thinkingState = ResultThinkingState()
    var completionState: ResultCompletionState { completionCoordinator.state }

    var elapsed: TimeInterval { completionState.metrics.elapsed }
    var charCount: Int { completionState.metrics.characterCount }
    var requestDiagnosticText: String { diagnosticText.fullText }
    var requestDiagnosticBriefText: String { diagnosticText.briefText }

    var output: String {
        get { outputState.text }
        set { outputState.replace(with: newValue) }
    }

    /// #2 Thinking/推理文本(Anthropic 或 DeepSeek R1 的 <think> 内容)
    var thinkingText: String {
        get { thinkingState.text }
        set { thinkingState.replace(with: newValue) }
    }
    @Published var showThinking: Bool = false
    @Published var showRouteDetails: Bool = false

    let settings: AppSettings
    private var client: AIClient
    private let completionCoordinator: ResultCompletionCoordinator
    private let routeAttemptCoordinator: ResultRouteAttemptCoordinator
    private let requestPreparationCoordinator: ResultRequestPreparationCoordinator
    private var history: [ChatMessage] = []
    private var autoReplaceEnabled = false
    private var replacementOriginalText: String = ""
    private var submissionPrivacy: PrivacySubmissionDiagnostic?
    private var requestDiagnostics: AIRequestDiagnostics?
    private var streamAccumulator = StreamingAccumulator()
    private var lastAutoScrollTime: TimeInterval = 0

    // 打字机
    private var streamDone: Bool = false
    private var typewriterTimer: Timer?
    private var typewriterBuffer = TypewriterBuffer()
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
        self.completionCoordinator = ResultCompletionCoordinator(settings: settings)
        self.routeAttemptCoordinator = ResultRouteAttemptCoordinator(settings: settings)
        self.requestPreparationCoordinator = ResultRequestPreparationCoordinator(settings: settings)
    }

    // #3 图片(来自截图/粘贴)
    private var pendingImageData: Data? = nil
    private var pendingImageMimeType: String = "image/png"
    private var pendingCaptureMethod: TextCaptureMethod?
    private var pendingSourceContext: SelectionSourceContext?

    var completeText: String { fullText }
    var isTranslation: Bool { action.isTranslation }

    func shouldAutoScroll(currentTime: TimeInterval = ProcessInfo.processInfo.systemUptime) -> Bool {
        let shouldScroll = ResultAutoScrollPolicy.shouldScroll(lastScrollTime: lastAutoScrollTime,
                                                               currentTime: currentTime,
                                                               isStreaming: isStreaming)
        if shouldScroll {
            lastAutoScrollTime = currentTime
        }
        return shouldScroll
    }

    func markFinalAutoScroll(currentTime: TimeInterval = ProcessInfo.processInfo.systemUptime) {
        lastAutoScrollTime = currentTime
    }

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
        typewriterBuffer.removeAll()
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
        typewriterBuffer.removeAll()
        output = ""
        thinkingText = ""
        showRouteDetails = false
        streamDone = false
        errorMessage = nil
        routeNote = nil
        requestDiagnostics = nil
        if diagnosticText != .empty {
            diagnosticText = .empty
        }
        completionCoordinator.reset()
    }

    private func runStream(hasImage: Bool) {
        let input = ResultRequestPreparationInput(
            action: action,
            sourceText: sourceText,
            history: history,
            explicitHasImage: hasImage,
            captureMethod: pendingCaptureMethod,
            sourceContext: pendingSourceContext,
            submissionPrivacy: submissionPrivacy
        )
        switch requestPreparationCoordinator.prepare(input) {
        case .ready(let request):
            submissionPrivacy = request.submissionPrivacy
            runRoute(at: 0,
                     routes: request.routes,
                     diagnostics: request.diagnostics)
        case .unavailable(let message, let diagnostics, let privacy):
            submissionPrivacy = privacy
            errorMessage = message
            updateRequestDiagnostics(diagnostics)
        }
    }

    private func runRoute(at index: Int,
                          routes: [AIRequestRoute],
                          diagnostics: AIRequestDiagnostics) {
        let preparation = routeAttemptCoordinator.prepare(index: index,
                                                          routes: routes,
                                                          diagnostics: diagnostics)
        switch preparation {
        case .advance(let nextIndex, let diagnostics, let note):
            updateRequestDiagnostics(diagnostics)
            if let note { routeNote = note }
            runRoute(at: nextIndex, routes: routes, diagnostics: diagnostics)
            return
        case .unavailable(let diagnostics, let message):
            updateRequestDiagnostics(diagnostics)
            errorMessage = message
            return
        case .ready(let attempt):
            updateRequestDiagnostics(attempt.diagnostics)
            executeRoute(attempt, routes: routes)
        }
    }

    private func executeRoute(_ attempt: ResultRunnableRouteAttempt,
                              routes: [AIRequestRoute]) {
        let route = attempt.route
        client = AIClient(settings: attempt.scopedSettings)
        activeProviderName = route.providerName
        activeModelName = route.modelName
        routeNote = attempt.routeNote

        isStreaming = true
        streamDone = false
        let routeStartedAt = completionCoordinator.markRouteStarted()
        var firstTokenMilliseconds: Int?
        let typewriterOn = settings.typewriterSpeed != .off
        let thinkingEnabled = action.thinkingMode

        if typewriterOn { startTypewriter() }

        client.stream(messages: history, action: action) { [weak self] token in
            guard let self = self else { return }
            if firstTokenMilliseconds == nil {
                firstTokenMilliseconds = AIRequestAttemptDiagnostic.elapsedMilliseconds(since: routeStartedAt)
            }
            let visibleText = self.streamAccumulator.appendContentToken(
                token,
                extractsThinkTags: thinkingEnabled
            )
            self.thinkingText = self.streamAccumulator.thinkingText
            if typewriterOn {
                self.typewriterBuffer.enqueue(visibleText)
            } else {
                self.output = self.fullText
            }
        } onThinking: { [weak self] thinking in
            // Anthropic extended thinking 块
            guard let self = self else { return }
            self.streamAccumulator.appendExternalThinking(thinking)
            self.thinkingText = self.streamAccumulator.thinkingText
        } onComplete: { [weak self] error in
            guard let self = self else { return }
            let finalVisibleText = self.streamAccumulator.finish()
            self.thinkingText = self.streamAccumulator.thinkingText
            self.streamDone = true
            if typewriterOn {
                self.typewriterBuffer.enqueue(finalVisibleText)
            }
            if let error = error {
                let recordedFailure = self.routeAttemptCoordinator.recordFailure(
                    error: error,
                    outputText: self.fullText,
                    thinkingText: self.thinkingText,
                    routeStartedAt: routeStartedAt,
                    routes: routes,
                    attempt: attempt,
                    firstTokenMilliseconds: firstTokenMilliseconds
                )
                let failure = recordedFailure.failure
                let failedDiagnostics = recordedFailure.diagnostics
                self.updateRequestDiagnostics(failedDiagnostics)
                if failure.decision.shouldTryNext {
                    self.stopTypewriter()
                    self.output = ""
                    self.streamAccumulator.resetForFallback()
                    self.typewriterBuffer.removeAll()
                    self.thinkingText = self.streamAccumulator.thinkingText
                    self.errorMessage = nil
                    self.routeNote = route.fallbackSwitchNote
                    self.runRoute(at: attempt.index + 1,
                                  routes: routes,
                                  diagnostics: failedDiagnostics)
                    return
                }
                if let note = failure.decision.userNote {
                    self.routeNote = note
                }
                self.errorMessage = failure.safeErrorMessage
                self.stopTypewriter()
                self.output = self.fullText
                self.typewriterBuffer.removeAll()
                self.isStreaming = false
                self.finishMetrics(recordUsage: false, saveHistory: false)
            } else {
                let completedDiagnostics = self.routeAttemptCoordinator.recordSuccess(
                    attempt: attempt,
                    routeStartedAt: routeStartedAt,
                    firstTokenMilliseconds: firstTokenMilliseconds,
                    outputCharacterCount: self.fullText.count
                )
                self.updateRequestDiagnostics(completedDiagnostics)
                if !typewriterOn {
                    self.output = self.fullText
                    self.isStreaming = false
                    self.finishMetrics(recordUsage: true, saveHistory: true)
                }
            }
        }
    }

    private func updateRequestDiagnostics(_ diagnostics: AIRequestDiagnostics) {
        requestDiagnostics = diagnostics
        let text = ResultDiagnosticTextSnapshot(fullText: diagnostics.summaryText,
                                                briefText: diagnostics.briefSummaryText)
        if diagnosticText != text {
            diagnosticText = text
        }
    }

    private func finishMetrics(recordUsage: Bool, saveHistory: Bool) {
        let context = ResultCompletionContext(
            recordUsage: recordUsage,
            saveHistory: saveHistory,
            action: action,
            sourceText: sourceText,
            outputText: fullText,
            errorMessage: errorMessage,
            providerName: activeProviderName,
            modelName: activeModelName,
            historyTags: submissionPrivacy?.historyTags ?? [],
            contentStorage: submissionPrivacy?.effectiveHistoryContentStorage,
            autoReplaceEnabled: autoReplaceEnabled,
            replacementOriginalText: replacementOriginalText
        )
        guard let outcome = completionCoordinator.finish(context: context,
                                                         onReplace: onReplace) else {
            return
        }
        if outcome.didAutoReplace {
            autoReplaceEnabled = false
        }
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
        let nextText = typewriterBuffer.dequeue(maxCharacters: charsPerTick)
        if !nextText.isEmpty {
            output += nextText
        } else if streamDone && typewriterBuffer.isEmpty {
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
