import Combine
import Foundation
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
        get {
            // 读取前冲刷挂起更新,保证 complete/诊断路径看到最新值。
            thinkingState.flush()
            return thinkingState.text
        }
        set { thinkingState.replace(with: newValue) }
    }
    @Published var showThinking: Bool = false
    @Published var showRouteDetails: Bool = false

    /// 取消生成或流式中途出错后,若保留了部分结果,则标记原因以提示用户当前不完整。
    @Published var incompleteResultReason: IncompleteResultReason?

    enum IncompleteResultReason {
        case cancelled
        case interrupted

        var title: String {
            switch self {
            case .cancelled: return "已停止生成,当前为部分结果"
            case .interrupted: return "生成被中断,当前为部分结果"
            }
        }
    }

    /// #bug2 瞬时非模态提示(如「未检测到选中的文字」),取代阻塞式模态 alert。
    @Published var transientNotice: String?

    var transientNoticeWork: DispatchWorkItem?

    let settings: AppSettings
    var client: AIClient
    let completionCoordinator: ResultCompletionCoordinator
    let routeAttemptCoordinator: ResultRouteAttemptCoordinator
    let requestPreparationCoordinator: ResultRequestPreparationCoordinator
    let streamingCoordinator: ResultStreamingCoordinator
    let submissionCoordinator: ResultSubmissionCoordinator
    let operationCoordinator: ResultOperationCoordinator
    var autoReplaceEnabled = false
    var replacementOriginalText: String = ""
    var submissionPrivacy: PrivacySubmissionDiagnostic?
    var requestDiagnostics: AIRequestDiagnostics?
    var lastAutoScrollTime: TimeInterval = 0

    // #5 追问历史(↑/↓ 浏览)
    var followUpHistory = FollowUpHistoryStore()
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
        self.streamingCoordinator = ResultStreamingCoordinator()
        self.submissionCoordinator = ResultSubmissionCoordinator(settings: settings)
        self.operationCoordinator = ResultOperationCoordinator()
    }

    // #3 图片(来自截图/粘贴)
    var pendingCaptureMethod: TextCaptureMethod?
    var pendingSourceContext: SelectionSourceContext?

    var completeText: String {
        // completeText 用于结束态落盘/导出,先冲刷 UI 缓冲避免漏字。
        outputState.flush()
        return streamingCoordinator.completeText
    }
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
        self.pendingCaptureMethod = captureMethod
        self.pendingSourceContext = sourceContext
        self.submissionPrivacy = submissionPrivacy
        self.autoReplaceEnabled = autoReplaceEnabled
        thinkingText = ""
        showThinking = false
        showRouteDetails = false
        resetOutput()
        sendInitial(imageData: imageData, imageMimeType: imageMimeType)
    }

    func resendEdited() {
        guard !isStreaming, !sourceText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        var currentAction = action
        currentAction.targetLanguage = targetLanguage
        guard let prepared = submissionCoordinator.prepare(text: sourceText,
                                                           action: currentAction,
                                                           using: prepareSourceSubmission) else { return }
        action = currentAction
        sourceText = prepared.text
        submissionPrivacy = prepared.diagnostic
        thinkingText = ""
        resetOutput()
        sendInitial()
    }

    func changeLanguage(_ lang: TargetLanguage) {
        var nextAction = action
        nextAction.targetLanguage = lang
        guard let prepared = submissionCoordinator.prepare(text: sourceText,
                                                           action: nextAction,
                                                           using: prepareSourceSubmission) else { return }
        targetLanguage = lang
        action = nextAction
        sourceText = prepared.text
        submissionPrivacy = prepared.diagnostic
        thinkingText = ""
        resetOutput()
        sendInitial()
    }

    /// #4 切换到另一个动作,对相同原文重新发起
    func switchAction(_ newAction: AIAction) {
        guard let prepared = submissionCoordinator.prepare(text: sourceText,
                                                           action: newAction,
                                                           using: prepareSourceSubmission) else { return }
        action = newAction
        targetLanguage = newAction.targetLanguage
        sourceText = prepared.text
        submissionPrivacy = prepared.diagnostic
        thinkingText = ""
        showThinking = false
        resetOutput()
        sendInitial()
    }

    private func sendInitial(imageData: Data? = nil,
                             imageMimeType: String = "image/png") {
        let hasImage = submissionCoordinator.beginInitialRequest(
            action: action,
            targetLanguage: targetLanguage,
            sourceText: sourceText,
            imageData: imageData,
            imageMimeType: imageMimeType,
            sourceContext: pendingSourceContext
        )
        runStream(hasImage: hasImage)
    }

    // MARK: - 追问

    func sendFollowUp() {
        let q = followUp.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty, !isStreaming else { return }
        guard let prepared = submissionCoordinator.prepare(text: q,
                                                           action: action,
                                                           using: prepareFollowUpSubmission) else { return }
        // #5 追问历史
        followUpHistory.record(q)
        submissionCoordinator.appendFollowUp(assistantText: completeText,
                                             userText: prepared.text)
        submissionPrivacy = prepared.diagnostic
        followUp = ""
        thinkingText = ""
        resetOutput()
        runStream(hasImage: false)
    }

    func regenerate() {
        guard !isStreaming else { return }
        thinkingText = ""
        resetOutput()
        runStream(hasImage: false)
    }

    func retry() {
        guard !isStreaming else { return }
        thinkingText = ""
        resetOutput()
        runStream(hasImage: false)
    }

    func cancel() {
        guard isStreaming else { return }
        client.cancel()
        streamingCoordinator.stopAndDiscardPendingPresentation()
        outputState.flush()
        thinkingState.flush()
        output = completeText
        isStreaming = false
        if !completeText.isEmpty { incompleteResultReason = .cancelled }
        finishMetrics(recordUsage: false, saveHistory: false)
    }

    func copyOutput() {
        copy(completeText, success: "结果已复制", empty: "当前没有可复制的结果。")
    }

    func copyConversationMarkdown() {
        copy(completeText.isEmpty ? "" : conversationExport().markdown,
             success: "对话 Markdown 已复制", empty: "当前没有可复制的对话内容。")
    }

    func copyCodeBlock(_ code: String) {
        copy(code, success: "代码块已复制", empty: "该代码块没有可复制的内容。")
    }

    func copyRequestDiagnostics() {
        copy(requestDiagnosticText, success: "完整诊断已复制",
             empty: "当前没有可复制的请求诊断。")
    }

    func copyBriefRequestDiagnostics() {
        copy(requestDiagnosticBriefText, success: "精简诊断已复制",
             empty: "当前没有可复制的请求诊断。")
    }

    func replaceOriginal() {
        operationCoordinator.replace(original: replacementOriginalText,
                                     replacement: completeText, handler: onReplace)
    }

    func appendToDocument() {
        operationCoordinator.append(text: completeText, handler: onAppend)
    }

    func exportConversation() {
        operationCoordinator.export(
            markdown: completeText.isEmpty ? "" : conversationExport().markdown,
            actionName: action.name
        )
    }

    private func copy(_ text: String, success: String, empty: String) {
        operationCoordinator.copy(text: text, successMessage: success,
                                  emptyMessage: empty)
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
        outputState.flush()
        thinkingState.flush()
        streamingCoordinator.reset()
        output = ""
        thinkingText = ""
        showRouteDetails = false
        errorMessage = nil
        routeNote = nil
        incompleteResultReason = nil
        operationCoordinator.clearFeedback()
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
            history: submissionCoordinator.messages,
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
        let routeStartedAt = completionCoordinator.markRouteStarted()
        var firstTokenMilliseconds: Int?
        let thinkingEnabled = action.thinkingMode

        streamingCoordinator.begin(
            speed: settings.typewriterSpeed,
            onOutputChunk: { [weak self] chunk in
                self?.outputState.append(chunk)
            },
            onDrained: { [weak self] in
                guard let self else { return }
                self.outputState.flush()
                self.thinkingState.flush()
                self.isStreaming = false
                self.finishMetrics(recordUsage: true, saveHistory: true)
            }
        )
        let typewriterOn = streamingCoordinator.usesTypewriter

        client.stream(messages: submissionCoordinator.messages, action: action) { [weak self] token in
            guard let self = self else { return }
            if firstTokenMilliseconds == nil {
                firstTokenMilliseconds = AIRequestAttemptDiagnostic.elapsedMilliseconds(since: routeStartedAt)
            }
            let immediateOutputDelta = self.streamingCoordinator.appendContentToken(
                token,
                extractsThinkTags: thinkingEnabled)
            _ = self.thinkingState.replaceCoalesced(with: self.streamingCoordinator.thinkingText)
            if let immediateOutputDelta {
                self.outputState.append(immediateOutputDelta)
            }
        } onThinking: { [weak self] thinking in
            // Anthropic extended thinking 块
            guard let self = self else { return }
            let next = self.streamingCoordinator.appendExternalThinking(thinking)
            _ = self.thinkingState.replaceCoalesced(with: next)
        } onComplete: { [weak self] error in
            guard let self = self else { return }
            let immediateOutputDelta = self.streamingCoordinator.finish()
            // 结束态立即落定,不再合并延迟。
            self.thinkingState.replace(with: self.streamingCoordinator.thinkingText)
            if let immediateOutputDelta {
                self.outputState.append(immediateOutputDelta)
            }
            self.outputState.flush()
            if let error = error {
                let recordedFailure = self.routeAttemptCoordinator.recordFailure(
                    error: error,
                    outputText: self.completeText,
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
                    self.streamingCoordinator.reset()
                    self.output = ""
                    self.thinkingText = self.streamingCoordinator.thinkingText
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
                self.streamingCoordinator.stopAndDiscardPendingPresentation()
                self.output = self.completeText
                self.isStreaming = false
                if !self.completeText.isEmpty { self.incompleteResultReason = .interrupted }
                self.finishMetrics(recordUsage: false, saveHistory: false)
            } else {
                let completedDiagnostics = self.routeAttemptCoordinator.recordSuccess(
                    attempt: attempt,
                    routeStartedAt: routeStartedAt,
                    firstTokenMilliseconds: firstTokenMilliseconds,
                    outputCharacterCount: self.completeText.count
                )
                self.updateRequestDiagnostics(completedDiagnostics)
                if !typewriterOn {
                    self.outputState.flush()
                    self.thinkingState.flush()
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
            outputText: completeText,
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

}
