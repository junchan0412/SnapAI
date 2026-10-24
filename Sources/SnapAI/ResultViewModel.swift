import Combine
import Foundation
import SnapAILogic

/// 浮动结果窗口的状态机
@MainActor
final class ResultViewModel: ObservableObject {

    @Published var sourceText: String = ""
    @Published var isStreaming: Bool = false
    @Published private(set) var isGenerating: Bool = false
    var isPresenting: Bool { isStreaming && !isGenerating }
    @Published var errorMessage: String?
    @Published var followUp: String = ""
    @Published var isPinned: Bool = false
    @Published var action: AIAction = AIAction()
    @Published var targetLanguage: TargetLanguage = .auto
    @Published var activeProviderName: String = ""
    @Published var activeModelName: String = ""
    @Published var routeNote: String?
    private(set) var requestStartedAt: Date?
    private(set) var firstTokenAt: Date?
    private(set) var networkCompletedAt: Date?
    private(set) var presentationCompletedAt: Date?
    private(set) var markdownReadyAt: Date?

    @Published private var diagnosticText: ResultDiagnosticTextSnapshot = .empty
    let outputState = ResultOutputState()
    let thinkingState = ResultThinkingState()
    var completionState: ResultCompletionState { completionCoordinator.state }

    var elapsed: TimeInterval { completionState.metrics.elapsed }
    var charCount: Int { completionState.metrics.characterCount }
    var requestDiagnosticText: String { diagnosticText.fullText + timingDiagnosticText }
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
    private let session: URLSession
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
    private var requestID = UUID()
    private var awaitsAutomaticWriteBack = false
    private var finishRequestUsage: (() -> Void)?
    var retainedImageData: Data?
    var retainedImageMimeType = "image/png"
    var sourceImageData: Data?
    var sourceImageMimeType = "image/png"
    var hasSourceImage: Bool { sourceImageData != nil }
    var comparisonMessages: [ChatMessage] { submissionCoordinator.messages }

    @Published var conversationSession: ConversationSession?
    var restoredConversation = false

    // #5 追问历史(↑/↓ 浏览)
    var followUpHistory = FollowUpHistoryStore()
    var followUpHistoryCount: Int { followUpHistory.count }

    /// #3 替换原文回调
    var onReplace: ((String, String) -> Void)?
    /// #8 追加回调
    var onAppend: ((String) -> Void)?
    /// 追问发送前的隐私处理/确认回调,由 AppDelegate 提供系统 UI。
    var prepareFollowUpSubmission: ResultSubmissionCoordinator.PreparationHandler?
    /// 原文重发/动作切换前的隐私处理/确认回调。
    var prepareSourceSubmission: ResultSubmissionCoordinator.PreparationHandler?

    init(settings: AppSettings, session: URLSession = .shared) {
        self.settings = settings
        self.session = session
        self.client = AIClient(settings: settings, session: session)
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

#if DEBUG || SNAPAI_PREVIEW
    func setPreviewStreaming(_ active: Bool) {
        isGenerating = active
        isStreaming = active
    }
#endif

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
               retainedImageData: Data? = nil,
               retainedImageMimeType: String = "image/png",
               submissionPrivacy: PrivacySubmissionDiagnostic? = nil,
               autoReplaceEnabled: Bool = false,
               captureMethod: TextCaptureMethod? = nil,
               sourceContext: SelectionSourceContext? = nil,
               preparedMessages: [ChatMessage]? = nil) {
        restoredConversation = false
        self.action = action
        self.targetLanguage = action.targetLanguage
        self.sourceText = text
        self.replacementOriginalText = originalText ?? text
        self.pendingCaptureMethod = captureMethod
        self.pendingSourceContext = sourceContext
        self.submissionPrivacy = submissionPrivacy
        self.autoReplaceEnabled = autoReplaceEnabled
        self.sourceImageData = imageData
        self.sourceImageMimeType = imageMimeType
        self.retainedImageData = retainedImageData ?? imageData
        self.retainedImageMimeType = retainedImageData != nil ? retainedImageMimeType : imageMimeType
        thinkingText = ""
        showThinking = false
        showRouteDetails = false
        resetOutput()
        sendInitial(preparedMessages: preparedMessages)
    }

    func resendEdited() {
        guard !isGenerating,
              sourceImageData != nil || !sourceText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        var currentAction = action
        currentAction.targetLanguage = targetLanguage
        guard let prepared = prepareInitialSubmission(action: currentAction) else { return }
        action = currentAction
        sourceText = prepared.text
        submissionPrivacy = prepared.diagnostic
        thinkingText = ""
        resetOutput()
        sendInitial(preparedMessages: prepared.messages)
    }

    func changeLanguage(_ lang: TargetLanguage) {
        var nextAction = action
        nextAction.targetLanguage = lang
        guard let prepared = prepareInitialSubmission(action: nextAction) else { return }
        targetLanguage = lang
        action = nextAction
        sourceText = prepared.text
        submissionPrivacy = prepared.diagnostic
        thinkingText = ""
        resetOutput()
        sendInitial(preparedMessages: prepared.messages)
    }

    /// #4 切换到另一个动作,对相同原文重新发起
    func switchAction(_ newAction: AIAction) {
        guard let prepared = prepareInitialSubmission(action: newAction) else { return }
        action = newAction
        targetLanguage = newAction.targetLanguage
        sourceText = prepared.text
        submissionPrivacy = prepared.diagnostic
        thinkingText = ""
        showThinking = false
        resetOutput()
        sendInitial(preparedMessages: prepared.messages)
    }

    private func prepareInitialSubmission(action: AIAction) -> PrivacyPreparedSubmission? {
        let imageData = sourceImageData
        let imageMimeType = sourceImageMimeType
        let sourceContext = pendingSourceContext
        return submissionCoordinator.prepare(text: sourceText, action: action,
                                              messageBuilder: { [self] text in
            submissionCoordinator.initialMessages(action: action,
                                                   targetLanguage: action.targetLanguage,
                                                   sourceText: text,
                                                   imageData: imageData,
                                                   imageMimeType: imageMimeType,
                                                   sourceContext: sourceContext)
        }, using: prepareSourceSubmission)
    }

    private func sendInitial(preparedMessages: [ChatMessage]? = nil) {
        let messages = preparedMessages ?? submissionCoordinator.initialMessages(
            action: action,
            targetLanguage: targetLanguage,
            sourceText: sourceText,
            imageData: sourceImageData,
            imageMimeType: sourceImageMimeType,
            sourceContext: pendingSourceContext
        )
        conversationSession = ConversationSession(action: action, sourceText: sourceText,
            sourceImageData: retainedImageData, sourceImageMimeType: retainedImageMimeType,
            sourceImageWasSubmitted: sourceImageData != nil,
            messages: messages.map { ConversationMessage($0) })
        submissionCoordinator.replaceMessages(messages)
        runStream(hasImage: messages.contains { $0.imageData != nil })
    }

    // MARK: - 追问

    func sendFollowUp() {
        let q = followUp.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty, !isGenerating else { return }
        let assistantText = completeText
        guard let prepared = submissionCoordinator.prepare(text: q,
                                                           action: action,
                                                           messageBuilder: { [self] text in
            conversationFollowUpMessages(assistantText: assistantText, userText: text)
        },
                                                           using: prepareFollowUpSubmission) else { return }
        // #5 追问历史
        followUpHistory.record(q)
        let messages = prepared.messages ?? conversationFollowUpMessages(assistantText: assistantText, userText: prepared.text)
        if conversationSession?.messages.last?.role != .assistant, !assistantText.isEmpty {
            conversationSession?.messages.append(ConversationMessage(ChatMessage(role: .assistant, content: assistantText),
                providerName: activeProviderName, modelName: activeModelName, isComplete: incompleteResultReason == nil))
        }
        if let user = messages.last {
            conversationSession?.messages.append(ConversationMessage(user))
        }
        submissionCoordinator.replaceMessages(messages)
        submissionPrivacy = prepared.diagnostic
        followUp = ""
        thinkingText = ""
        resetOutput()
        runStream(hasImage: false)
    }

    func regenerate() {
        retry()
    }

    func retry() {
        guard !isGenerating else { return }
        let messages = submissionCoordinator.currentMessages()
        guard let userIndex = messages.lastIndex(where: { $0.role == .user }),
              let prepared = submissionCoordinator.prepare(text: messages[userIndex].content,
                                                           action: action,
                                                           messageBuilder: { text in
            var messages = messages
            messages[userIndex].content = text
            return messages
        }, using: prepareSourceSubmission) else { return }
        let approved = prepared.messages ?? messages
        if conversationSession?.messages.last?.role == .assistant {
            if conversationSession?.activeCompression?.throughMessageID == conversationSession?.messages.last?.id {
                try? conversationSession?.activateCompression(id: nil)
            }
            conversationSession?.messages.removeLast()
        }
        if let lastUser = approved.last(where: { $0.role == .user }),
           let index = conversationSession?.messages.lastIndex(where: { $0.role == .user }) {
            conversationSession?.messages[index].content = lastUser.content
            conversationSession?.messages[index].imageData = lastUser.imageData
        }
        submissionCoordinator.replaceMessages(approved)
        submissionPrivacy = prepared.diagnostic
        thinkingText = ""
        resetOutput()
        runStream(hasImage: false)
    }

    func cancel() {
        guard isStreaming else { return }
        if !isGenerating {
            output = streamingCoordinator.revealImmediately()
            finishPresentation(allowAutomaticWriteBack: false)
            return
        }
        finishRequestUsage?()
        finishRequestUsage = nil
        requestID = UUID()
        client.cancel()
        streamingCoordinator.stopAndDiscardPendingPresentation()
        outputState.flush()
        thinkingState.flush()
        output = completeText
        isStreaming = false
        isGenerating = false
        if !completeText.isEmpty { incompleteResultReason = .cancelled }
        recordConversationOutput(isComplete: false)
        // 取消不计成功、不自动写回，但部分结果会保存到历史并打上“部分结果”标签。
        finishMetrics(recordUsage: false,
                      saveHistory: true,
                      additionalHistoryTags: completeText.isEmpty ? [] : [PrivacyHistoryTag.partialResult])
    }

    func revealFullOutput() {
        guard isStreaming else { return }
        output = streamingCoordinator.revealImmediately()
        if !isGenerating { finishPresentation() }
    }

    func markMarkdownReady() {
        guard !isStreaming, requestStartedAt != nil, markdownReadyAt == nil else { return }
        markdownReadyAt = Date()
    }

    private var timingDiagnosticText: String {
        guard let start = requestStartedAt else { return "" }
        let points: [(String, Date?)] = [("request-start", start), ("first-token", firstTokenAt),
            ("network-end", networkCompletedAt), ("presentation-end", presentationCompletedAt),
            ("markdown-ready", markdownReadyAt)]
        return "\nTimeline (ms since request start):\n" + points.map { name, time in
            name + "=" + (time.map { String(Int(max(0, $0.timeIntervalSince(start)) * 1_000)) } ?? "pending")
        }.joined(separator: "\n")
    }

    private func finishPresentation(allowAutomaticWriteBack: Bool = true) {
        if presentationCompletedAt == nil { presentationCompletedAt = Date() }
        outputState.flush()
        thinkingState.flush()
        isStreaming = false
        let shouldReplace = awaitsAutomaticWriteBack && allowAutomaticWriteBack
        awaitsAutomaticWriteBack = false
        if shouldReplace {
            autoReplaceEnabled = false
            ResultWriteBackCoordinator.replace(original: replacementOriginalText,
                                               replacement: completeText, handler: onReplace)
        }
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
        guard !restoredConversation else {
            showTransientNotice("恢复的会话未绑定文档，请复制结果或重新取词后写回。")
            return
        }
        operationCoordinator.replace(original: replacementOriginalText,
                                     replacement: completeText, handler: onReplace)
    }

    func appendToDocument() {
        guard !restoredConversation else {
            showTransientNotice("恢复的会话未绑定文档，请复制结果或重新取词后写回。")
            return
        }
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

    func resetOutput() {
        finishRequestUsage?()
        finishRequestUsage = nil
        requestID = UUID()
        client.cancel()
        isStreaming = false
        isGenerating = false
        awaitsAutomaticWriteBack = false
        requestStartedAt = nil
        firstTokenAt = nil
        networkCompletedAt = nil
        presentationCompletedAt = nil
        markdownReadyAt = nil
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
            streamingCoordinator.stopAndDiscardPendingPresentation()
            isStreaming = false
            isGenerating = false
            submissionPrivacy = privacy
            errorMessage = message
            updateRequestDiagnostics(diagnostics)
            finishMetrics(recordUsage: false, saveHistory: false)
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
            streamingCoordinator.stopAndDiscardPendingPresentation()
            isStreaming = false
            isGenerating = false
            updateRequestDiagnostics(diagnostics)
            errorMessage = message
            finishMetrics(recordUsage: false, saveHistory: false)
            return
        case .ready(let attempt):
            updateRequestDiagnostics(attempt.diagnostics)
            executeRoute(attempt, routes: routes)
        }
    }

    private func executeRoute(_ attempt: ResultRunnableRouteAttempt,
                              routes: [AIRequestRoute]) {
        client.cancel()
        let requestID = UUID()
        self.requestID = requestID
        let route = attempt.route
        client = AIClient(settings: attempt.scopedSettings, session: session)
        activeProviderName = route.providerName
        activeModelName = route.modelName
        routeNote = attempt.routeNote

        isStreaming = true
        isGenerating = true
        if requestStartedAt == nil { requestStartedAt = Date() }
        let routeStartedAt = completionCoordinator.markRouteStarted()
        var firstTokenMilliseconds: Int?
        let thinkingEnabled = action.thinkingMode
        let pricing = ModelCapabilityRegistry.pricing(providerID: route.providerID, modelName: route.modelName, settings: attempt.scopedSettings)
        finishRequestUsage = { [weak self] in
            guard let self else { return }
            RoutingMetricsStore.shared.recordUsage(route: route, usage: self.client.latestUsage, pricing: pricing,
                firstTokenMilliseconds: firstTokenMilliseconds,
                networkMilliseconds: AIRequestAttemptDiagnostic.elapsedMilliseconds(since: routeStartedAt))
        }

        streamingCoordinator.begin(
            speed: settings.typewriterSpeed,
            onOutputChunk: { [weak self] chunk in
                guard let self, self.requestID == requestID else { return }
                self.outputState.append(chunk)
            },
            onDrained: { [weak self] in
                guard let self, self.requestID == requestID else { return }
                self.finishPresentation()
            }
        )

        client.stream(messages: submissionCoordinator.messages, action: action) { [weak self] token in
            guard let self, self.requestID == requestID else { return }
            if firstTokenMilliseconds == nil {
                firstTokenMilliseconds = AIRequestAttemptDiagnostic.elapsedMilliseconds(since: routeStartedAt)
            }
            if self.firstTokenAt == nil { self.firstTokenAt = Date() }
            let immediateOutputDelta = self.streamingCoordinator.appendContentToken(
                token,
                extractsThinkTags: thinkingEnabled)
            _ = self.thinkingState.replaceCoalesced(with: self.streamingCoordinator.thinkingText)
            if let immediateOutputDelta {
                self.outputState.append(immediateOutputDelta)
            }
        } onThinking: { [weak self] thinking in
            // Anthropic extended thinking 块
            guard let self, self.requestID == requestID else { return }
            if firstTokenMilliseconds == nil {
                firstTokenMilliseconds = AIRequestAttemptDiagnostic.elapsedMilliseconds(since: routeStartedAt)
            }
            if self.firstTokenAt == nil { self.firstTokenAt = Date() }
            let next = self.streamingCoordinator.appendExternalThinking(thinking)
            _ = self.thinkingState.replaceCoalesced(with: next)
        } onComplete: { [weak self] error in
            guard let self, self.requestID == requestID else { return }
            self.networkCompletedAt = Date()
            self.finishRequestUsage?()
            self.finishRequestUsage = nil
            let immediateOutputDelta = self.streamingCoordinator.finish()
            // 结束态立即落定,不再合并延迟。
            self.thinkingState.replace(with: self.streamingCoordinator.thinkingText)
            if let immediateOutputDelta {
                self.outputState.append(immediateOutputDelta)
            }
            self.outputState.flush()
            let error = error ?? (self.completeText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? AIStreamDecodingError.emptyResponse : nil)
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
                    self.networkCompletedAt = nil
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
                self.isGenerating = false
                if !self.completeText.isEmpty { self.incompleteResultReason = .interrupted }
                self.recordConversationOutput(isComplete: false)
                self.finishMetrics(recordUsage: false, saveHistory: false)
            } else {
                let completedDiagnostics = self.routeAttemptCoordinator.recordSuccess(
                    attempt: attempt,
                    routeStartedAt: routeStartedAt,
                    firstTokenMilliseconds: firstTokenMilliseconds,
                    outputCharacterCount: self.completeText.count
                )
                self.updateRequestDiagnostics(completedDiagnostics)
                self.isGenerating = false
                self.recordConversationOutput(isComplete: true)
                self.finishMetrics(recordUsage: true, saveHistory: true,
                                   deferAutomaticWriteBack: self.streamingCoordinator.usesTypewriter)
                if !self.streamingCoordinator.usesTypewriter { self.finishPresentation() }
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

    private func finishMetrics(recordUsage: Bool, saveHistory: Bool, additionalHistoryTags: [String] = [],
                               deferAutomaticWriteBack: Bool = false) {
        awaitsAutomaticWriteBack = deferAutomaticWriteBack && ResultWriteBackCoordinator.shouldAutoReplace(
            recordUsage: recordUsage, autoReplaceEnabled: autoReplaceEnabled,
            replaceByDefault: action.replaceByDefault, outputText: completeText, errorMessage: errorMessage)
        let context = ResultCompletionContext(
            recordUsage: recordUsage,
            saveHistory: saveHistory,
            additionalHistoryTags: additionalHistoryTags,
            action: action,
            sourceText: sourceText,
            outputText: completeText,
            errorMessage: errorMessage,
            providerName: activeProviderName,
            modelName: activeModelName,
            historyTags: submissionPrivacy?.historyTags ?? [],
            contentStorage: submissionPrivacy?.effectiveHistoryContentStorage,
            autoReplaceEnabled: autoReplaceEnabled && !deferAutomaticWriteBack,
            replacementOriginalText: replacementOriginalText
        )
        guard let outcome = completionCoordinator.finish(context: context,
                                                         onReplace: onReplace) else {
            return
        }
        if outcome.didAutoReplace {
            autoReplaceEnabled = false
        }
        if outcome.historySaveFailed {
            operationCoordinator.showError("结果已生成，但历史保存失败。请先复制或导出结果。")
        }
    }

}
