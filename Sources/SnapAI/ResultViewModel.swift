import SwiftUI
import Combine

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
    /// #2 Thinking/推理文本(Anthropic 或 DeepSeek R1 的 <think> 内容)
    @Published var thinkingText: String = ""
    @Published var showThinking: Bool = false

    let settings: AppSettings
    private var client: AIClient
    private var history: [ChatMessage] = []
    private var startTime: Date?
    private var savedToHistory = false
    private var metricsFinished = false

    // 打字机
    private var fullText: String = ""
    private var streamDone: Bool = false
    private var typewriterTimer: Timer?
    private var charsPerTick: Int { settings.typewriterSpeed.charsPerTick }
    private var tickInterval: TimeInterval { settings.typewriterSpeed.tickInterval }

    // #5 追问历史(↑/↓ 浏览)
    private var followUpHistory: [String] = []
    var followUpHistoryCount: Int { followUpHistory.count }

    /// #3 替换原文回调
    var onReplace: ((String) -> Void)?
    /// #8 追加回调
    var onAppend: ((String) -> Void)?

    init(settings: AppSettings) {
        self.settings = settings
        self.client = AIClient(settings: settings)
    }

    // #3 图片(来自截图/粘贴)
    private var pendingImageData: Data? = nil
    private var pendingImageMimeType: String = "image/png"

    var completeText: String { fullText }
    var isTranslation: Bool { action.isTranslation }

    // MARK: - 启动

    func start(text: String, action: AIAction, imageData: Data? = nil, imageMimeType: String = "image/png") {
        self.action = action
        self.targetLanguage = action.targetLanguage
        self.sourceText = text
        self.pendingImageData = imageData
        self.pendingImageMimeType = imageMimeType
        thinkingText = ""
        showThinking = false
        resetOutput()
        history = []
        sendInitial()
    }

    func resendEdited() {
        guard !isStreaming, !sourceText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        history = []
        thinkingText = ""
        resetOutput()
        sendInitial()
    }

    func changeLanguage(_ lang: TargetLanguage) {
        targetLanguage = lang
        action.targetLanguage = lang
        history = []
        thinkingText = ""
        resetOutput()
        sendInitial()
    }

    /// #4 切换到另一个动作,对相同原文重新发起
    func switchAction(_ newAction: AIAction) {
        action = newAction
        targetLanguage = newAction.targetLanguage
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

        var messages: [ChatMessage] = []
        if !settings.systemPrompt.isEmpty {
            messages.append(ChatMessage(role: .system, content: settings.systemPrompt))
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
        runStream()
    }

    // MARK: - 追问

    func sendFollowUp() {
        let q = followUp.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty, !isStreaming else { return }
        // #5 追问历史
        if !followUpHistory.contains(q) { followUpHistory.append(q) }
        if !fullText.isEmpty {
            history.append(ChatMessage(role: .assistant, content: fullText))
        }
        history.append(ChatMessage(role: .user, content: q))
        followUp = ""
        thinkingText = ""
        resetOutput()
        runStream()
    }

    /// #5 浏览追问历史
    func followUpHistoryUp() {
        guard !followUpHistory.isEmpty else { return }
        let last = followUpHistory.last ?? ""
        followUp = last
    }

    func followUpHistoryDown() {
        followUp = ""
    }

    func regenerate() {
        guard !isStreaming else { return }
        thinkingText = ""
        resetOutput()
        runStream()
    }

    /// #12 错误后重试
    func retry() {
        guard !isStreaming else { return }
        thinkingText = ""
        resetOutput()
        runStream()
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

    /// #3 替换原文
    func replaceOriginal() {
        guard !fullText.isEmpty else { return }
        onReplace?(fullText)
    }

    /// #8 追加到文档
    func appendToDocument() {
        guard !fullText.isEmpty else { return }
        onAppend?(fullText)
    }

    // MARK: - 内部

    private func resetOutput() {
        stopTypewriter()
        fullText = ""
        output = ""
        streamDone = false
        errorMessage = nil
        elapsed = 0
        charCount = 0
        savedToHistory = false
        metricsFinished = false
        startTime = Date()
    }

    private func runStream() {
        // #1 per-action 供应商:动作指定了供应商则用临时 client
        if let pid = action.providerID,
           let overrideProvider = settings.providers.first(where: { $0.id == pid && $0.isEnabled }) {
            let probe = AppSettings()
            probe.providers = [overrideProvider]
            probe.activeProviderID = overrideProvider.id
            // 模型优先级:动作显式指定 → 供应商首个启用。不要自动回退到禁用模型或其他供应商模型。
            let modelNames = Set(overrideProvider.models.map { $0.name })
            if let modelOverride = action.modelOverride, modelNames.contains(modelOverride) {
                probe.activeModel = modelOverride
            } else {
                probe.activeModel = overrideProvider.enabledModelNames.first ?? ""
            }
            probe.temperature = settings.temperature
            probe.systemPrompt = settings.systemPrompt
            client = AIClient(settings: probe)
        } else {
            client = AIClient(settings: settings)
        }

        isStreaming = true
        streamDone = false
        startTime = Date()
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
                self.errorMessage = error.localizedDescription
                self.stopTypewriter()
                self.output = self.fullText
                self.isStreaming = false
                self.finishMetrics(recordUsage: false, saveHistory: false)
            } else if !typewriterOn {
                self.output = self.fullText
                self.isStreaming = false
                self.finishMetrics(recordUsage: true, saveHistory: true)
            }
        }
    }

    private func finishMetrics(recordUsage: Bool, saveHistory: Bool) {
        guard !metricsFinished else { return }
        metricsFinished = true
        if let start = startTime { elapsed = Date().timeIntervalSince(start) }
        charCount = fullText.count
        if recordUsage {
            // #11 使用统计
            settings.actionUsageCounts[action.name, default: 0] += 1
        }
        if saveHistory {
            saveToHistoryIfNeeded()
        } else if recordUsage {
            settings.save()
        }
    }

    private func saveToHistoryIfNeeded() {
        guard !savedToHistory, !fullText.isEmpty, errorMessage == nil else { return }
        savedToHistory = true
        settings.addHistory(action: action.name, source: sourceText, output: fullText,
                            provider: settings.activeProvider?.name ?? "",
                            model: settings.activeModel)
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
