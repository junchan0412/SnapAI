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
    var onReplace: ((String, String) -> Void)?
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

    func start(text: String,
               action: AIAction,
               imageData: Data? = nil,
               imageMimeType: String = "image/png",
               autoReplaceEnabled: Bool = false) {
        self.action = action
        self.targetLanguage = action.targetLanguage
        self.sourceText = text
        self.pendingImageData = imageData
        self.pendingImageMimeType = imageMimeType
        self.autoReplaceEnabled = autoReplaceEnabled
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
        runStream(hasImage: false)
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

    /// #3 替换原文
    func replaceOriginal() {
        guard !fullText.isEmpty else { return }
        onReplace?(sourceText, fullText)
    }

    /// #8 追加到文档
    func appendToDocument() {
        guard !fullText.isEmpty else { return }
        onAppend?(fullText)
    }

    func exportConversation() {
        var md = "# \(action.name) - \(DateFormatter.localizedString(from: Date(), dateStyle: .short, timeStyle: .short))\n\n"
        md += "**原文:**\n\n\(sourceText)\n\n---\n\n"
        md += completeText
        let modelText = [activeProviderName, activeModelName].filter { !$0.isEmpty }.joined(separator: " / ")
        md += "\n\n---\n*模型: \(modelText.isEmpty ? settings.activeModel : modelText) | 耗时: \(String(format: "%.1f", elapsed))s*"

        let panel = NSSavePanel()
        panel.nameFieldStringValue = "\(action.name)-\(Int(Date().timeIntervalSince1970)).md"
        panel.allowedContentTypes = [.init(filenameExtension: "md") ?? .text]
        if panel.runModal() == .OK, let url = panel.url {
            try? md.write(to: url, atomically: true, encoding: .utf8)
        }
    }

    // MARK: - 内部

    private func resetOutput() {
        stopTypewriter()
        fullText = ""
        output = ""
        streamDone = false
        errorMessage = nil
        routeNote = nil
        elapsed = 0
        charCount = 0
        savedToHistory = false
        metricsFinished = false
        startTime = Date()
    }

    private func runStream(hasImage: Bool) {
        let routes = AIRequestRouter.candidates(settings: settings,
                                                action: action,
                                                sourceText: sourceText,
                                                hasImage: hasImage)
        guard !routes.isEmpty else {
            errorMessage = "没有可用的 AI 供应商或模型,请在设置中启用至少一个模型。"
            return
        }
        runRoute(at: 0, routes: routes)
    }

    private func runRoute(at index: Int, routes: [AIRequestRoute]) {
        let route = routes[index]
        guard let scoped = AIRequestRouter.scopedSettings(from: settings, route: route) else {
            if routes.indices.contains(index + 1) {
                runRoute(at: index + 1, routes: routes)
            } else {
                errorMessage = "路由到的模型不可用,请检查供应商和模型设置。"
            }
            return
        }

        client = AIClient(settings: scoped)
        activeProviderName = route.providerName
        activeModelName = route.modelName
        routeNote = route.reason

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
                if self.fullText.isEmpty,
                   self.settings.fallbackEnabled,
                   routes.indices.contains(index + 1) {
                    self.stopTypewriter()
                    self.output = ""
                    self.errorMessage = nil
                    self.routeNote = "\(route.providerName) / \(route.modelName) 失败,正在切换备用模型"
                    self.runRoute(at: index + 1, routes: routes)
                    return
                }
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
            onReplace?(sourceText, fullText)
        }
    }

    private func saveToHistoryIfNeeded() {
        guard !savedToHistory, !fullText.isEmpty, errorMessage == nil else { return }
        savedToHistory = true
        settings.addHistory(action: action.name, source: sourceText, output: fullText,
                            provider: activeProviderName.isEmpty ? (settings.activeProvider?.name ?? "") : activeProviderName,
                            model: activeModelName.isEmpty ? settings.activeModel : activeModelName)
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
