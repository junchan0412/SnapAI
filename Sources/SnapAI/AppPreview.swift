#if DEBUG || SNAPAI_PREVIEW
import AppKit
import SwiftUI
import SnapAILogic

@MainActor
final class AppPreviewDelegate: NSObject, NSApplicationDelegate {
    private let settings = AppSettings()
    private let defaultsSuite = "com.snapai.preview.session.\(UUID().uuidString)"
    private var windows: WindowCoordinator?
    private var result: FloatingPanelController?
    private var history: HistoryWindowController?
    private var quickInput: QuickInputController?
    private var commands: CommandPaletteController?
    private var health: PermissionHealthController?
    private let previewDirectory = FileManager.default.temporaryDirectory.appendingPathComponent("SnapAI-Preview-\(UUID().uuidString)")
    private let previewStartedAt = ProcessInfo.processInfo.systemUptime

    nonisolated override init() { super.init() }

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard let defaults = UserDefaults(suiteName: defaultsSuite) else {
            NSApp.terminate(nil)
            return
        }
        settings.persistenceDefaults = defaults
        settings.persistenceHistoryStore = HistoryStore(url: previewDirectory.appendingPathComponent("history.sqlite"))
        settings.persistenceConversationStore = ConversationStore(url: previewDirectory.appendingPathComponent("conversations.sqlite"))
        NSApp.setActivationPolicy(.regular)
        installPreviewMenu()
        let arguments = ProcessInfo.processInfo.arguments
        let dark = arguments.contains("dark")
        NSApp.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        let surface = arguments.drop(while: { $0 != "--preview" }).dropFirst().first ?? "settings"
        settings.providers = [AIProvider(id: "preview-provider", name: "OpenAI", baseURL: "http://127.0.0.1:9/v1",
                                         apiKey: "preview-only", models: [AIModelEntry(name: "gpt-4.1")])]
        settings.secretStoreCache = ["preview-provider": "preview-only"]
        settings.activeProviderID = "preview-provider"
        settings.activeModel = "gpt-4.1"
        settings.typewriterSpeed = .off
        settings.iCloudSyncEnabled = false
        settings.onboardingDone = true
        settings.history = Self.historyEntries
        settings.actionUsageCounts = ["提问": 42, "翻译": 26, "润色": 18, "总结": 12]
        if surface == "empty-history" { settings.history = [] }
        if surface == "empty-settings" { settings.providers = [] }
        windows = WindowCoordinator(settings: settings, onSettingsChange: {}, onTryQuickInput: { [weak self] in self?.showQuickInput() })
        switch surface {
        case "result": showResult()
        case "result-stream": showResult(streaming: true)
        case "result-long-10000", "result-long-40000", "result-long-100000":
            showResult(characterCount: Int(surface.split(separator: "-").last ?? "10000"))
        case "quick": showQuickInput()
        case "history", "empty-history": showHistory()
        case "commands": showCommands()
        case "welcome": windows?.showOnboarding()
        case "actions": windows?.showSettings(section: .actions)
        case "provider": windows?.showSettings(section: .provider)
        case "model": windows?.showSettings(section: .model)
        case "history-settings": windows?.showSettings(section: .history)
        case "general": windows?.showSettings(section: .general)
        case "permission": windows?.showSettings(section: .permission)
        case "health":
            health = PermissionHealthController(settings: settings, hotKeyFailures: { [] },
                                                textCaptureStatus: { "就绪" }, writeBackStatus: { "就绪" },
                                                recentAIRequestStatus: { "none" })
            health?.show()
        case "diff":
            _ = DiffPreviewWindowController.present(original: "我们想让这个功能用起来更简单一点。", revised: "我们希望让这个功能更易于使用。", actionName: "润色")
        default: windows?.openSettings()
        }
        if arguments.contains("--compact"), let window = NSApp.keyWindow {
            let size: NSSize
            switch surface {
            case "result", "result-stream", "result-long-10000", "result-long-40000", "result-long-100000":
                size = NSSize(width: 480, height: 480)
            case "quick": size = NSSize(width: 480, height: 300)
            case "commands": size = NSSize(width: 520, height: 360)
            case "history", "empty-history": size = NSSize(width: 800, height: 540)
            case "health": size = NSSize(width: 620, height: 520)
            default: size = NSSize(width: 840, height: 620)
            }
            window.setContentSize(size)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        UserDefaults.standard.removePersistentDomain(forName: defaultsSuite)
        try? FileManager.default.removeItem(at: previewDirectory)
    }

    private func installPreviewMenu() {
        let menu = NSMenu()
        let applicationItem = NSMenuItem()
        let applicationMenu = NSMenu(title: "SnapAI Preview")
        applicationMenu.addItem(withTitle: "退出预览", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        applicationItem.submenu = applicationMenu
        menu.addItem(applicationItem)
        let editItem = NSMenuItem()
        let editMenu = NSMenu(title: "编辑")
        editMenu.addItem(withTitle: "撤销", action: Selector(("undo:")), keyEquivalent: "z")
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "剪切", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "复制", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "粘贴", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "全选", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = editMenu
        menu.addItem(editItem)
        NSApp.mainMenu = menu
    }

    private func showResult(streaming: Bool = false, characterCount: Int? = nil) {
        let document = characterCount.map(Self.longOutput) ?? Self.output
        let vm = ResultViewModel(settings: settings)
        vm.action = settings.enabledActions.first { $0.name == AIAction.summarizeName } ?? AIAction()
        vm.sourceText = Self.source
        vm.activeProviderName = "OpenAI"
        vm.activeModelName = "gpt-4.1"
        result = FloatingPanelController(vm: vm, onOpenAISettings: { [weak self] in self?.windows?.openSettings() })
        result?.show()
        logPreviewEvent("window-presented", characters: document.count)
        if streaming {
            startStreamingDemo(vm)
        } else {
            _ = vm.streamingCoordinator.appendContentToken(document, extractsThinkTags: false)
            vm.output = document
            vm.conversationSession = ConversationSession(action: vm.action, sourceText: Self.source,
                messages: [ConversationMessage(ChatMessage(role: .user, content: Self.source)),
                           ConversationMessage(ChatMessage(role: .assistant, content: document),
                                               providerName: vm.activeProviderName, modelName: vm.activeModelName)])
            vm.completionCoordinator.state.replace(with: ResultCompletionMetrics(elapsed: 0, characterCount: document.count))
            logPreviewEvent("fixture-published", characters: document.count)
        }
    }

    /// 流式采样面(`--preview result-stream`):按 token 分片把示例文档推进结果窗口,
    /// 供脚本在流式期间采样 footprint(见 docs/RUNTIME_MEMORY_BASELINE.md)。
    /// 直接向结果状态追加演示文本:流式期间显示纯文本,完成后才后台构建 Markdown。
    /// 此入口不经过 provider 网络请求或打字机调度,用于 UI 布局与内存采样。
    private func startStreamingDemo(_ vm: ResultViewModel) {
        let document = String(repeating: Self.output + "\n\n", count: 16)
        vm.setPreviewStreaming(true)
        logPreviewEvent("demo-stream-start", characters: document.count)
        Task { @MainActor in
            var index = document.startIndex
            while index < document.endIndex && vm.isGenerating && !Task.isCancelled {
                let end = document.index(index, offsetBy: 60, limitedBy: document.endIndex) ?? document.endIndex
                let chunk = String(document[index..<end])
                _ = vm.streamingCoordinator.appendContentToken(chunk, extractsThinkTags: false)
                vm.output += chunk
                if index == document.startIndex { logPreviewEvent("demo-first-chunk", characters: chunk.count) }
                index = end
                try? await Task.sleep(nanoseconds: 250_000_000)
            }
            guard index == document.endIndex else {
                logPreviewEvent("demo-stream-cancelled", characters: vm.output.count)
                return
            }
            _ = vm.streamingCoordinator.finish()
            vm.setPreviewStreaming(false)
            logPreviewEvent("demo-stream-finish", characters: document.count)
        }
    }

    private func logPreviewEvent(_ event: String, characters: Int) {
        let elapsed = ProcessInfo.processInfo.systemUptime - previewStartedAt
        let build = Bundle.main.object(forInfoDictionaryKey: "SnapAIBuildConfiguration") as? String ?? "preview"
        fputs("SnapAI Preview: event=\(event), elapsed=\(String(format: "%.3f", elapsed))s, characters=\(characters), build=\(build), source=fixture, network=no\n", stderr)
    }

    static func longOutput(characterCount: Int) -> String {
        let code = (0..<24).map { index in
            "let sample\(index) = [\"request_id\": \"fixture-\(index)\", \"status\": \"ready\", \"description\": \"" +
            String(repeating: "long_code_line_", count: 12) + "\"]"
        }.joined(separator: "\n")
        let block = """
        ## 固定阅读任务 · Markdown 混合内容

        这是一份固定文本 fixture，用于检查长文阅读、表格、代码滚动和最终布局。It does not send a model request or measure network latency.

        | 检查项 | 输入规模 | 预期行为 |
        | :--- | ---: | :--- |
        | 中文与 English | 10k / 40k / 100k 字符 | 格式与信息完整 |
        | 表格 | 三列 | 对齐可读 |
        | 长代码 | 24 行 | 横向滚动，不撑宽窗口 |

        - **阅读位置**：滚动到中段后保持当前段落。
        - **布局完成**：检查正文、表格和代码之间的间距。
        - [ ] 记录内存与主线程采样，不将一次采样解释为稳定帧率。

        > 所有文字来自本地 fixture，没有真实模型输出、token 用量或费用。

        ```swift
        \(code)
        ```

        """ + "\n\n"
        let target = max(0, characterCount)
        let copies = target / block.count
        let body = String(repeating: block, count: copies)
        return body + String(repeating: "文", count: target - body.count)
    }

    private func showHistory() {
        history = HistoryWindowController(settings: settings, reopen: { [weak self] _ in self?.showResult() })
        history?.show()
    }

    private func showQuickInput() {
        let model = QuickInputModel(settings: settings)
        model.actionID = settings.enabledActions.first?.id ?? ""
        let arguments = ProcessInfo.processInfo.arguments
        if let index = arguments.firstIndex(of: "--image-fixture"), arguments.indices.contains(index + 1),
           let image = NSImage(contentsOfFile: arguments[index + 1]),
           let payload = image.snapAIOptimizedData() {
            model.attachImage(payload)
        }
        model.onSubmit = { [weak self] _, _, _, _ in
            guard let self else { return false }
            self.quickInput?.hide()
            self.showResult()
            return true
        }
        quickInput = QuickInputController(model: model)
        quickInput?.show()
    }

    private func showCommands() {
        commands = CommandPaletteController { [weak self] in
            [CommandPaletteItem(id: "ask", title: "提问", subtitle: "理解选中的文字，获得简洁回答", systemImage: "text.bubble", keywords: "问答", shortcutText: "⌥ A", perform: { self?.showResult() }),
             CommandPaletteItem(id: "translate", title: "翻译", subtitle: "中英互译，保留原文语气", systemImage: "character.bubble", keywords: "语言", shortcutText: "⌥ T", perform: { self?.showResult() }),
             CommandPaletteItem(id: "polish", title: "润色", subtitle: "让表达清晰自然，确认后写回", systemImage: "pencil.line", keywords: "改写", shortcutText: "⌥ P", perform: { self?.showResult() }),
             CommandPaletteItem(id: "history", title: "历史记录", subtitle: "搜索、收藏与继续之前的工作", systemImage: "clock.arrow.circlepath", keywords: "记录", perform: { self?.showHistory() }),
             CommandPaletteItem(id: "settings", title: "AI 模型设置", subtitle: "管理供应商、模型和路由策略", systemImage: "cpu", keywords: "设置", perform: { self?.windows?.openSettings() })]
        }
        commands?.show()
    }

    static let source = "SnapAI 是一款 macOS 菜单栏 AI 助手。选中文字后，可以直接翻译、润色、总结或解释代码；也可以在快捷提问中输入文字、粘贴图片或截图。结果支持复制、继续追问，以及确认后写回原来的应用。"
    static let output = """
    ## 让思考留在当前窗口

    SnapAI 把 AI 放到文字选区旁边，让翻译、润色和提问自然融入你的工作。

    ### 三个日常用法

    - **阅读时**：选中陌生段落，快速翻译或提炼重点。
    - **写作时**：润色表达，查看差异后写回原文。
    - **思考时**：打开快捷提问，输入文字、粘贴图片，接着追问。

    你可以连接自己的 AI 服务，也可以使用本地模型。历史记录按隐私偏好保存，方便下次继续。
    """

    static var historyEntries: [HistoryEntry] {
        [HistoryEntry(id: "preview-1", date: Date(), actionName: "总结", source: source, output: output, provider: "OpenAI", model: "gpt-4.1", isFavorite: true, tags: ["产品", "灵感"]),
         HistoryEntry(id: "preview-2", date: Date().addingTimeInterval(-3600), actionName: "翻译", source: "Great tools help you stay focused on the work that matters.", output: "好的工具，让你专注于真正重要的工作。", provider: "OpenAI", model: "gpt-4.1", tags: ["阅读"]),
         HistoryEntry(id: "preview-3", date: Date().addingTimeInterval(-86400), actionName: "润色", source: "我们想让这个功能用起来更简单一点。", output: "我们希望让这个功能更易于使用。", provider: "OpenAI", model: "gpt-4.1"),
         HistoryEntry(id: "preview-4", date: Date().addingTimeInterval(-90000), actionName: "解释代码", source: "let names = users.map(\\.name)", output: "这行代码使用 `map` 取出每个用户的 `name`，得到一个名字数组。", provider: "OpenAI", model: "gpt-4.1")]
    }
}
#endif
