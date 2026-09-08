#if DEBUG
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

    nonisolated override init() { super.init() }

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard let defaults = UserDefaults(suiteName: defaultsSuite) else {
            NSApp.terminate(nil)
            return
        }
        settings.persistenceDefaults = defaults
        NSApp.setActivationPolicy(.regular)
        installPreviewMenu()
        let arguments = ProcessInfo.processInfo.arguments
        let dark = arguments.contains("dark")
        NSApp.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        let surface = arguments.drop(while: { $0 != "--preview" }).dropFirst().first ?? "settings"
        settings.providers = [AIProvider(id: "preview-provider", name: "OpenAI", baseURL: "http://127.0.0.1:9/v1",
                                         apiKey: "preview-only", models: [AIModelEntry(name: "gpt-4.1")])]
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
        case "quick": showQuickInput()
        case "history", "empty-history": showHistory()
        case "commands": showCommands()
        case "welcome": windows?.showOnboarding()
        case "actions": windows?.showSettings(section: .actions)
        case "history-settings": windows?.showSettings(section: .history)
        case "health":
            health = PermissionHealthController(settings: settings, hotKeyFailures: { [] },
                                                textCaptureStatus: { "就绪" }, writeBackStatus: { "就绪" },
                                                recentAIRequestStatus: { "none" })
            health?.show()
        case "diff":
            _ = DiffPreviewWindowController.present(original: "我们想让这个功能用起来更简单一点。", revised: "我们希望让这个功能更易于使用。", actionName: "润色")
        case "update", "update-progress":
            showUpdate(progress: surface == "update-progress")
        default: windows?.openSettings()
        }
        if arguments.contains("--compact"), let window = NSApp.keyWindow {
            let size: NSSize
            switch surface {
            case "result": size = NSSize(width: 480, height: 480)
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

    private func showResult() {
        let vm = ResultViewModel(settings: settings)
        vm.action = settings.enabledActions.first { $0.name == AIAction.summarizeName } ?? AIAction()
        vm.sourceText = Self.source
        vm.activeProviderName = "OpenAI"
        vm.activeModelName = "gpt-4.1"
        _ = vm.streamingCoordinator.appendContentToken(Self.output, extractsThinkTags: false)
        vm.output = Self.output
        vm.completionCoordinator.state.replace(with: ResultCompletionMetrics(elapsed: 1.84, characterCount: Self.output.count))
        result = FloatingPanelController(vm: vm, onOpenAISettings: { [weak self] in self?.windows?.openSettings() })
        result?.show()
    }

    private func showHistory() {
        history = HistoryWindowController(settings: settings, reopen: { [weak self] _ in self?.showResult() })
        history?.show()
    }

    private func showQuickInput() {
        let model = QuickInputModel(settings: settings)
        model.actionID = settings.enabledActions.first?.id ?? ""
        model.onSubmit = { [weak self] _, _, _, _ in
            guard let self else { return false }
            self.quickInput?.hide()
            self.showResult()
            return true
        }
        quickInput = QuickInputController(model: model)
        quickInput?.show()
    }

    private func showUpdate(progress: Bool) {
        let model = UpdateFlowModel(
            currentDisplay: "v2.0.1",
            latestDisplay: "v2.0.2",
            releaseTitle: "SnapAI 2.0.2",
            releaseNotes: """
            ## SnapAI 2.0.2

            - **视觉**：重构更新窗口为原生对话框样式，图标、发布说明卡片与操作按钮层次清晰。
            - **视觉**：删除主界面各区域之间的分割线，区域衔接更自然，无多余线条。
            - **修复**：供应商行的排序菜单不再显示重复的下拉箭头图标。
            - **验证**：Debug / Release 构建、代码签名与更新 manifest 签名均已核对。
            """,
            hasNotes: true,
            autoInstall: false
        )
        model.onInstall = { UpdateWindowController.shared.enterDownloading() }
        model.onSkip = { UpdateWindowController.shared.close() }
        model.onRemindLater = { UpdateWindowController.shared.close() }
        model.onCancel = { UpdateWindowController.shared.close() }
        UpdateWindowController.shared.present(model: model)
        if progress {
            model.totalBytes = 10_100_000
            model.receivedBytes = 4_100_000
            UpdateWindowController.shared.enterDownloading()
        }
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
