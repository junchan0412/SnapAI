import SwiftUI
import Combine

/// 浮动结果窗口的状态机
@MainActor
final class ResultViewModel: ObservableObject {
    enum Mode {
        case ask, translate
        var title: String { self == .ask ? "AI 提问" : "翻译" }
    }

    @Published var sourceText: String = ""
    /// 打字机已揭示的文本(UI 绑定这个)
    @Published var output: String = ""
    @Published var isStreaming: Bool = false
    @Published var errorMessage: String?
    @Published var followUp: String = ""
    /// 是否固定/置顶窗口(固定后点击外部不自动关闭)
    @Published var isPinned: Bool = false

    private let settings: AppSettings
    private let client: AIClient
    private var mode: Mode = .ask
    private var history: [ChatMessage] = []

    // 打字机:fullText 为已接收的完整文本,output 逐步追上它
    private var fullText: String = ""
    private var streamDone: Bool = false   // 网络流是否已结束(打字机可能仍在追赶)
    private var typewriterTimer: Timer?
    // 速度参数从 settings.typewriterSpeed 实时读取
    private var charsPerTick: Int { settings.typewriterSpeed.charsPerTick }
    private var tickInterval: TimeInterval { settings.typewriterSpeed.tickInterval }

    init(settings: AppSettings) {
        self.settings = settings
        self.client = AIClient(settings: settings)
    }

    /// 完整文本(供复制用,不受打字机进度影响)
    var completeText: String { fullText }

    /// 用选中文字开始一轮新对话
    func start(text: String, mode: Mode) {
        self.mode = mode
        self.sourceText = text
        resetOutput()
        self.history = []

        let template = mode == .ask ? settings.askPrompt : settings.translatePrompt
        let userContent = template.replacingOccurrences(of: "{{text}}", with: text)

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
        // 把上一轮回答存入历史
        if !fullText.isEmpty {
            history.append(ChatMessage(role: .assistant, content: fullText))
        }
        history.append(ChatMessage(role: .user, content: q))
        followUp = ""
        resetOutput()
        runStream()
    }

    /// 重新生成
    func regenerate() {
        guard !isStreaming else { return }
        resetOutput()
        runStream()
    }

    func cancel() {
        client.cancel()
        stopTypewriter()
        // 取消时把剩余文本立即补全显示
        output = fullText
        isStreaming = false
    }

    func copyOutput() {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(fullText, forType: .string)
    }

    // MARK: - 内部

    private func resetOutput() {
        stopTypewriter()
        fullText = ""
        output = ""
        streamDone = false
        errorMessage = nil
    }

    private func runStream() {
        isStreaming = true
        streamDone = false
        let typewriterOn = settings.typewriterSpeed != .off
        if typewriterOn { startTypewriter() }
        client.stream(messages: history) { [weak self] token in
            guard let self = self else { return }
            self.fullText += token
            // 关闭打字机时直接同步显示
            if !typewriterOn { self.output = self.fullText }
        } onComplete: { [weak self] error in
            guard let self = self else { return }
            self.streamDone = true
            if let error = error {
                self.errorMessage = error.localizedDescription
                self.stopTypewriter()
                self.output = self.fullText
                self.isStreaming = false
            } else if !typewriterOn {
                // 关闭打字机时直接收尾
                self.output = self.fullText
                self.isStreaming = false
            }
            // 开启打字机时:让其把剩余文本吐完后,在 tick 里收尾
        }
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
        // 还有未揭示的字符 -> 逐步揭示
        if output.count < fullText.count {
            let target = min(output.count + charsPerTick, fullText.count)
            let endIdx = fullText.index(fullText.startIndex, offsetBy: target)
            output = String(fullText[fullText.startIndex..<endIdx])
        } else if streamDone {
            // 流已结束且全部揭示完 -> 收尾
            isStreaming = false
            typewriterTimer?.invalidate()
            typewriterTimer = nil
        }
    }

    private func stopTypewriter() {
        typewriterTimer?.invalidate()
        typewriterTimer = nil
    }
}
