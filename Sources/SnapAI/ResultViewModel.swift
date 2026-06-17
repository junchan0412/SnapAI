import SwiftUI
import Combine

/// 浮动结果窗口的状态机
@MainActor
final class ResultViewModel: ObservableObject {

    @Published var sourceText: String = ""        // 可编辑的原文(#5)
    /// 打字机已揭示的文本(UI 绑定这个)
    @Published var output: String = ""
    @Published var isStreaming: Bool = false
    @Published var errorMessage: String?
    @Published var followUp: String = ""
    /// 是否固定/置顶窗口(固定后点击外部不自动关闭)
    @Published var isPinned: Bool = false
    /// 当前动作
    @Published var action: AIAction = AIAction()
    /// 翻译类动作的目标语言(可在面板里切换重译)(#7)
    @Published var targetLanguage: TargetLanguage = .auto
    /// 本轮耗时与字数(#9)
    @Published var elapsed: TimeInterval = 0
    @Published var charCount: Int = 0
    /// 替换原文的回调由 AppDelegate 注入(#3)
    var onReplace: ((String) -> Void)?

    let settings: AppSettings
    private let client: AIClient
    private var history: [ChatMessage] = []
    private var startTime: Date?
    private var savedToHistory = false

    // 打字机:fullText 为已接收的完整文本,output 逐步追上它
    private var fullText: String = ""
    private var streamDone: Bool = false
    private var typewriterTimer: Timer?
    private var charsPerTick: Int { settings.typewriterSpeed.charsPerTick }
    private var tickInterval: TimeInterval { settings.typewriterSpeed.tickInterval }

    init(settings: AppSettings) {
        self.settings = settings
        self.client = AIClient(settings: settings)
    }

    /// 完整文本(供复制/替换用,不受打字机进度影响)
    var completeText: String { fullText }

    /// 是否为翻译类动作(决定是否显示语言切换)
    var isTranslation: Bool { action.isTranslation }

    // MARK: - 启动

    /// 用选中文字开始一轮新对话
    func start(text: String, action: AIAction) {
        self.action = action
        self.targetLanguage = action.targetLanguage
        self.sourceText = text
        resetOutput()
        self.history = []
        sendInitial()
    }

    /// 用编辑后的原文重新发起(#5)
    func resendEdited() {
        guard !isStreaming, !sourceText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        history = []
        resetOutput()
        sendInitial()
    }

    /// 切换翻译目标语言并重译(#7)
    func changeLanguage(_ lang: TargetLanguage) {
        targetLanguage = lang
        action.targetLanguage = lang
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
        messages.append(ChatMessage(role: .user, content: userContent))
        history = messages
        runStream()
    }

    /// 追问
    func sendFollowUp() {
        let q = followUp.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty, !isStreaming else { return }
        if !fullText.isEmpty {
            history.append(ChatMessage(role: .assistant, content: fullText))
        }
        history.append(ChatMessage(role: .user, content: q))
        followUp = ""
        resetOutput()
        runStream()
    }

    /// 重新生成(可能已通过菜单切换了模型)(#9)
    func regenerate() {
        guard !isStreaming else { return }
        resetOutput()
        runStream()
    }

    func cancel() {
        client.cancel()
        stopTypewriter()
        output = fullText
        isStreaming = false
        finishMetrics()
    }

    func copyOutput() {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(fullText, forType: .string)
    }

    /// 把结果替换回原文位置(#3)
    func replaceOriginal() {
        guard !fullText.isEmpty else { return }
        onReplace?(fullText)
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
        startTime = Date()
    }

    private func runStream() {
        isStreaming = true
        streamDone = false
        startTime = Date()
        let typewriterOn = settings.typewriterSpeed != .off
        if typewriterOn { startTypewriter() }
        client.stream(messages: history) { [weak self] token in
            guard let self = self else { return }
            self.fullText += token
            if !typewriterOn { self.output = self.fullText }
        } onComplete: { [weak self] error in
            guard let self = self else { return }
            self.streamDone = true
            if let error = error {
                self.errorMessage = error.localizedDescription
                self.stopTypewriter()
                self.output = self.fullText
                self.isStreaming = false
                self.finishMetrics()
            } else if !typewriterOn {
                self.output = self.fullText
                self.isStreaming = false
                self.finishMetrics()
            }
        }
    }

    private func finishMetrics() {
        if let start = startTime { elapsed = Date().timeIntervalSince(start) }
        charCount = fullText.count
        saveToHistoryIfNeeded()
    }

    private func saveToHistoryIfNeeded() {
        guard !savedToHistory, !fullText.isEmpty, errorMessage == nil else { return }
        savedToHistory = true
        settings.addHistory(action: action.name,
                            source: sourceText,
                            output: fullText,
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
            finishMetrics()
        }
    }

    private func stopTypewriter() {
        typewriterTimer?.invalidate()
        typewriterTimer = nil
    }
}
