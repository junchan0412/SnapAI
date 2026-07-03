import AppKit
import SwiftUI
import Carbon

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuItemValidation {
    private let settings = AppSettings.shared
    private var statusItem: NSStatusItem!
    private var resultVM: ResultViewModel!
    private var panelController: FloatingPanelController!
    private var quickInput: QuickInputController!
    private var quickInputModel: QuickInputModel!
    private var commandPalette: CommandPaletteController!
    private var historyWindow: HistoryWindowController!
    private var permissionHealth: PermissionHealthController!
    private var windowCoordinator: WindowCoordinator!
    private var appearanceObserver: NSObjectProtocol?
    private var frontmostAppObserver: NSObjectProtocol?
    private let hotKeyCoordinator = HotKeyCoordinator()
    private var hotKeyRegistrationFailures: [String] = []
    /// 触发前的前台 App,用于「替换原文」时把焦点交还
    private var previousApp: NSRunningApplication?
    private var lastExternalFrontmostApp: NSRunningApplication?
    private var previousSelectionSnapshot: TextSelectionSnapshot?
    private var lastTextCaptureStatusSummary: String?
    private var lastWriteBackRecord: TextWriteBackRecord?
    private var lastWriteBackStatusSummary: String?

    /// nonisolated 以便在 main.swift 顶层(非 main-actor 上下文)构造
    nonisolated override init() {
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        applyActivationPolicy()
        applyAppIcon()
        installAppearanceObserver()
        installFrontmostAppObserver()
        installAutomationURLHandler()
        iCloudSync.shared.pullIfNeeded(into: settings)
        windowCoordinator = WindowCoordinator(
            settings: settings,
            onSettingsChange: { [weak self] in
                self?.reloadAfterSettingsChange()
            },
            onPinStateChange: { [weak self] in
                self?.installMainMenu()
            }
        )

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = statusBarImage()
        }

        resultVM = ResultViewModel(settings: settings)
        resultVM.onReplace = { [weak self] original, replacement in
            self?.replaceSelection(original: original, with: replacement)
        }
        resultVM.onAppend = { [weak self] text in self?.appendSelection(with: text) }   // #8
        resultVM.prepareFollowUpSubmission = { [weak self] text, action in
            self?.prepareTextForSubmission(text,
                                           action: action,
                                           imageData: nil,
                                           userPromptOverride: text)
        }
        resultVM.prepareSourceSubmission = { [weak self] text, action in
            self?.prepareTextForSubmission(text,
                                           action: action,
                                           imageData: nil)
        }
        panelController = FloatingPanelController(vm: resultVM) { [weak self] in
            self?.showSettings(section: .ai)
        }

        quickInputModel = QuickInputModel(settings: settings)
        quickInputModel.actionID = settings.enabledActions.first?.id ?? ""
        quickInputModel.onSubmit = { [weak self] text, action, imageData, imageMimeType in   // #3 imageData
            self?.runQuickInput(text: text, action: action, imageData: imageData, imageMimeType: imageMimeType)
        }
        quickInput = QuickInputController(model: quickInputModel)
        commandPalette = CommandPaletteController { [weak self] in
            self?.commandPaletteItems() ?? []
        }
        historyWindow = HistoryWindowController(settings: settings) { [weak self] entry in
            self?.reopenHistoryEntry(entry)
        }
        permissionHealth = PermissionHealthController(
            settings: settings,
            hotKeyFailures: { [weak self] in
                self?.hotKeyRegistrationFailures ?? []
            },
            textCaptureStatus: { [weak self] in
                self?.currentTextCaptureStatusSummary() ?? "none"
            },
            writeBackStatus: { [weak self] in
                self?.currentWriteBackStatusSummary() ?? "none"
            },
            recentAIRequestStatus: { [weak self] in
                self?.resultVM.requestHealthStatusText ?? "none"
            }
        )
        installServicesProvider()

        registerHotKeys()
        buildMenu()
        installMainMenu()

        // iCloud 同步监听(#9)。远端配置变化后刷新菜单与快捷键。
        iCloudSync.shared.startListening(into: settings) { [weak self] in
            self?.reloadAfterSettingsChange()
        }

        // 首次启动:显示引导;否则按需提示权限
        if !settings.onboardingDone {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                self?.showOnboarding()
            }
        } else if !TextCapture.hasAccessibilityPermission() {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                _ = TextCapture.hasAccessibilityPermission(prompt: true)
            }
        }
    }

    // MARK: - 菜单

    private func buildMenu() {
        let menu = NSMenu()

        // 动作 — 按 group 分组(#10)
        let allActions = settings.enabledActions
        let grouped = Dictionary(grouping: allActions) { menuGroupTitle(for: $0.group) }
        func addActionItem(_ action: AIAction) {
            let item = NSMenuItem(title: menuActionTitle(for: action.name),
                                  action: #selector(triggerActionFromMenu(_:)),
                                  keyEquivalent: "")
            item.target = self
            item.representedObject = action.id
            MenuCoordinator.configureShortcut(item, combo: action.hotKey)
            menu.addItem(item)
        }
        // 无分组的动作先列
        (grouped[""] ?? []).forEach { addActionItem($0) }
        // 按分组名排序
        for key in grouped.keys.sorted() where !key.isEmpty {
            menu.addItem(.separator())
            let header = NSMenuItem(title: key, action: nil, keyEquivalent: "")
            header.isEnabled = false
            menu.addItem(header)
            (grouped[key] ?? []).forEach { addActionItem($0) }
        }
        menu.addItem(.separator())

        let paletteItem = menu.addItem(withTitle: "命令面板",
                                       action: #selector(openCommandPaletteFromMenu(_:)),
                                       keyEquivalent: "k")
        paletteItem.target = self
        paletteItem.keyEquivalentModifierMask = [.command]

        // 快捷提问面板
        let quickItem = menu.addItem(withTitle: "快捷提问 (\(settings.quickPanelHotKey.displayString))",
                                     action: #selector(toggleQuickInputFromMenu(_:)), keyEquivalent: "")
        quickItem.target = self
        MenuCoordinator.configureShortcut(quickItem, combo: settings.quickPanelHotKey)
        menu.addItem(.separator())

        if !hotKeyRegistrationFailures.isEmpty {
            let warning = NSMenuItem(title: "快捷键注册异常", action: nil, keyEquivalent: "")
            let sub = NSMenu()
            for message in hotKeyRegistrationFailures.prefix(8) {
                let item = NSMenuItem(title: message, action: nil, keyEquivalent: "")
                item.isEnabled = false
                sub.addItem(item)
            }
            warning.submenu = sub
            menu.addItem(warning)
            menu.addItem(.separator())
        }

        // 当前模型 + 快速切换
        let currentTitle: String
        if let p = settings.activeProvider, !settings.model.isEmpty {
            let providerName = MarkdownExportSafety.metadata(p.name,
                                                              fallback: "未命名供应商",
                                                              maxLength: 80)
            let modelName = MarkdownExportSafety.metadata(settings.model,
                                                           fallback: "未命名模型",
                                                           maxLength: 120)
            currentTitle = "当前:\(providerName) / \(modelName)"
        } else {
            currentTitle = "当前:未选择模型"
        }
        let currentItem = NSMenuItem(title: currentTitle, action: nil, keyEquivalent: "")
        currentItem.isEnabled = false
        menu.addItem(currentItem)

        let workModeItem = NSMenuItem(title: "工作模式", action: nil, keyEquivalent: "")
        workModeItem.submenu = buildWorkModeMenu()
        menu.addItem(workModeItem)

        let switchItem = NSMenuItem(title: "切换模型", action: nil, keyEquivalent: "")
        switchItem.submenu = MenuCoordinator.modelSwitchMenu(settings: settings,
                                                             target: self,
                                                             action: #selector(switchModel(_:)))
        menu.addItem(switchItem)

        // 历史
        let historyItem = NSMenuItem(title: "历史记录", action: nil, keyEquivalent: "")
        historyItem.submenu = buildHistoryMenu()
        menu.addItem(historyItem)

        menu.addItem(.separator())
        let undoWriteBack = menu.addItem(withTitle: undoWriteBackMenuTitle(),
                                         action: #selector(undoLastWriteBackFromMenu(_:)),
                                         keyEquivalent: "")
        undoWriteBack.target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "设置…", action: #selector(openSettingsFromMenu(_:)), keyEquivalent: ",").target = self
        menu.addItem(withTitle: "权限健康中心…", action: #selector(openPermissionHealthFromMenu(_:)), keyEquivalent: "").target = self
        menu.addItem(withTitle: PermissionRecoveryCommand.title,
                     action: #selector(copyPermissionRecoverySuggestionsFromMenu(_:)),
                     keyEquivalent: "").target = self
        menu.addItem(withTitle: "检查更新…", action: #selector(checkForUpdatesFromMenu(_:)), keyEquivalent: "").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "退出 SnapAI", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        statusItem.menu = menu
    }

    private func menuActionTitle(for name: String) -> String {
        MarkdownExportSafety.metadata(name, fallback: "未命名动作", maxLength: 80)
    }

    private func menuGroupTitle(for group: String) -> String {
        MarkdownExportSafety.metadata(group, fallback: "", maxLength: 80)
    }

    private func buildWorkModeMenu() -> NSMenu {
        let sub = NSMenu()
        let currentMode = settings.matchingWorkModePreset
        let currentTitle = NSMenuItem(title: "当前:\(settings.workModeStatusTitle)",
                                      action: nil,
                                      keyEquivalent: "")
        currentTitle.isEnabled = false
        sub.addItem(currentTitle)
        sub.addItem(.separator())
        for mode in WorkModePreset.allCases {
            let item = NSMenuItem(title: mode.title,
                                  action: #selector(selectWorkModeFromMenu(_:)),
                                  keyEquivalent: "")
            item.target = self
            item.representedObject = mode.rawValue
            item.state = currentMode == mode ? .on : .off
            item.toolTip = mode.summary
            sub.addItem(item)
        }
        return sub
    }

    private func buildHistoryMenu() -> NSMenu {
        let sub = NSMenu()
        let open = sub.addItem(withTitle: "打开历史记录…", action: #selector(openHistoryWindowFromMenu(_:)), keyEquivalent: "")
        open.target = self
        sub.addItem(.separator())
        if settings.history.isEmpty {
            let item = NSMenuItem(title: "(暂无记录)", action: nil, keyEquivalent: "")
            item.isEnabled = false
            sub.addItem(item)
            return sub
        }
        for entry in settings.history.prefix(5) {
            let item = NSMenuItem(title: entry.menuTitle,
                                  action: #selector(reopenHistory(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = entry.id
            item.isEnabled = entry.canReopen
            item.toolTip = entry.reopenHelpText
            sub.addItem(item)
        }
        sub.addItem(.separator())
        let clear = sub.addItem(withTitle: "清空历史", action: #selector(clearHistory), keyEquivalent: "")
        clear.target = self
        return sub
    }

    private func addResultCommandItems(to menu: NSMenu) {
        for descriptor in ResultCommandFactory.menuDescriptors() {
            let item = menu.addItem(withTitle: descriptor.title,
                                    action: selector(for: descriptor.action),
                                    keyEquivalent: descriptor.keyEquivalent)
            item.target = self
            item.keyEquivalentModifierMask = nsModifierFlags(for: descriptor.modifiers)
        }

        let pin = menu.addItem(withTitle: ResultPinCommand.title(isPinned: resultVM.isPinned),
                               action: #selector(togglePinResultFromMenu(_:)),
                               keyEquivalent: ResultPinCommand.keyEquivalent)
        pin.target = self
        pin.keyEquivalentModifierMask = nsModifierFlags(for: ResultPinCommand.modifiers)
    }

    private func selector(for action: ResultCommandAction) -> Selector {
        switch action {
        case .copyOutput:
            return #selector(copyResultFromMenu(_:))
        case .copyMarkdown:
            return #selector(copyConversationMarkdownFromMenu(_:))
        case .exportConversation:
            return #selector(exportResultFromMenu(_:))
        case .copyBriefDiagnostics:
            return #selector(copyBriefRequestDiagnosticsFromMenu(_:))
        case .copyDiagnostics:
            return #selector(copyRequestDiagnosticsFromMenu(_:))
        case .openAISettings:
            return #selector(openAISettingsFromResultMenu(_:))
        case .replaceOriginal:
            return #selector(replaceResultFromMenu(_:))
        case .appendToDocument:
            return #selector(appendResultFromMenu(_:))
        case .stop:
            return #selector(stopResultFromMenu(_:))
        case .regenerate:
            return #selector(regenerateResultFromMenu(_:))
        }
    }

    private func nsModifierFlags(for modifiers: [ResultMenuModifier]) -> NSEvent.ModifierFlags {
        modifiers.reduce(into: NSEvent.ModifierFlags()) { flags, modifier in
            switch modifier {
            case .command:
                flags.insert(.command)
            case .option:
                flags.insert(.option)
            case .shift:
                flags.insert(.shift)
            }
        }
    }

    @objc private func switchModel(_ sender: NSMenuItem) {
        guard let info = sender.representedObject as? [String: String],
              let pid = info["provider"], let model = info["model"] else { return }
        settings.activate(providerID: pid, model: model, recordManualPreference: true)
        buildMenu()
        installMainMenu()
    }

    @objc private func selectWorkModeFromMenu(_ sender: NSMenuItem) {
        guard let rawValue = sender.representedObject as? String,
              let mode = WorkModePreset(rawValue: rawValue) else {
            showSettings(section: .general)
            return
        }
        applyWorkMode(mode)
    }

    @objc private func reopenHistory(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String,
              let entry = settings.history.first(where: { $0.id == id }) else { return }
        reopenHistoryEntry(entry)
    }

    private func reopenHistoryEntry(_ entry: HistoryEntry) {
        // 用历史里的原文 + 同名动作重新发起
        guard let sourceText = entry.reopenSourceText else { return }
        let historyActionName = HistoryFilterCriteria.normalizedFacetValue(entry.actionName)
        let action = settings.enabledActions.first {
            HistoryFilterCriteria.normalizedFacetValue($0.name) == historyActionName
        }
            ?? settings.enabledActions.first
        guard let action = action else { return }
        previousApp = currentCaptureTargetApp()
        resultVM.start(text: sourceText, action: action, autoReplaceEnabled: false)
        panelController.show()
    }

    @objc private func clearHistory() {
        settings.clearHistory()
        buildMenu()
    }

    private func installMainMenu() {
        let mainMenu = NSMenu()

        let appMenuItem = NSMenuItem()
        mainMenu.addItem(appMenuItem)
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "关于 SnapAI",
                        action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)),
                        keyEquivalent: "")
        appMenu.addItem(.separator())
        let prefItem = appMenu.addItem(withTitle: "设置…",
                                       action: #selector(openSettingsFromMenu(_:)),
                                       keyEquivalent: ",")
        prefItem.target = self
        let updateItem = appMenu.addItem(withTitle: "检查更新…",
                                         action: #selector(checkForUpdatesFromMenu(_:)),
                                         keyEquivalent: "")
        updateItem.target = self
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "隐藏 SnapAI",
                        action: #selector(NSApplication.hide(_:)),
                        keyEquivalent: "h")
        let hideOthers = appMenu.addItem(withTitle: "隐藏其他",
                                         action: #selector(NSApplication.hideOtherApplications(_:)),
                                         keyEquivalent: "h")
        hideOthers.keyEquivalentModifierMask = [.command, .option]
        appMenu.addItem(withTitle: "显示全部",
                        action: #selector(NSApplication.unhideAllApplications(_:)),
                        keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "退出 SnapAI",
                        action: #selector(NSApplication.terminate(_:)),
                        keyEquivalent: "q")
        appMenuItem.submenu = appMenu

        let operationMenuItem = NSMenuItem()
        mainMenu.addItem(operationMenuItem)
        let operationMenu = NSMenu(title: "操作")
        let palette = operationMenu.addItem(withTitle: "命令面板",
                                            action: #selector(openCommandPaletteFromMenu(_:)),
                                            keyEquivalent: "k")
        palette.target = self
        palette.keyEquivalentModifierMask = [.command]
        let quick = operationMenu.addItem(withTitle: "快捷提问",
                                          action: #selector(toggleQuickInputFromMenu(_:)),
                                          keyEquivalent: "")
        quick.target = self
        MenuCoordinator.configureShortcut(quick, combo: settings.quickPanelHotKey)
        let workMode = NSMenuItem(title: "工作模式", action: nil, keyEquivalent: "")
        workMode.submenu = buildWorkModeMenu()
        operationMenu.addItem(workMode)
        operationMenu.addItem(.separator())
        for action in settings.enabledActions {
            let item = NSMenuItem(title: action.name,
                                  action: #selector(triggerActionFromMenu(_:)),
                                  keyEquivalent: "")
            item.target = self
            item.representedObject = action.id
            MenuCoordinator.configureShortcut(item, combo: action.hotKey)
            operationMenu.addItem(item)
        }
        operationMenu.addItem(.separator())
        addResultCommandItems(to: operationMenu)
        let undoWriteBack = operationMenu.addItem(withTitle: undoWriteBackMenuTitle(),
                                                  action: #selector(undoLastWriteBackFromMenu(_:)),
                                                  keyEquivalent: "z")
        undoWriteBack.target = self
        undoWriteBack.keyEquivalentModifierMask = [.command, .option]
        operationMenu.addItem(.separator())
        operationMenu.addItem(withTitle: "打开历史记录…", action: #selector(openHistoryWindowFromMenu(_:)), keyEquivalent: "").target = self
        operationMenu.addItem(withTitle: "权限健康中心…", action: #selector(openPermissionHealthFromMenu(_:)), keyEquivalent: "").target = self
        operationMenu.addItem(withTitle: PermissionRecoveryCommand.title,
                              action: #selector(copyPermissionRecoverySuggestionsFromMenu(_:)),
                              keyEquivalent: "").target = self
        operationMenu.addItem(withTitle: "检查更新…", action: #selector(checkForUpdatesFromMenu(_:)), keyEquivalent: "").target = self
        operationMenuItem.submenu = operationMenu

        let editMenuItem = NSMenuItem()
        mainMenu.addItem(editMenuItem)
        let editMenu = NSMenu(title: "编辑")
        let undo = editMenu.addItem(withTitle: "撤销", action: Selector(("undo:")), keyEquivalent: "z")
        undo.keyEquivalentModifierMask = [.command]
        let redo = editMenu.addItem(withTitle: "重做", action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "剪切", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "复制", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "粘贴", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "全选", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editMenuItem.submenu = editMenu

        let windowMenuItem = NSMenuItem()
        mainMenu.addItem(windowMenuItem)
        let windowMenu = NSMenu(title: "窗口")
        windowMenu.addItem(withTitle: "最小化",
                           action: #selector(NSWindow.performMiniaturize(_:)),
                           keyEquivalent: "m")
        windowMenu.addItem(withTitle: "关闭",
                           action: #selector(NSWindow.performClose(_:)),
                           keyEquivalent: "w")
        windowMenuItem.submenu = windowMenu
        NSApp.windowsMenu = windowMenu

        NSApp.mainMenu = mainMenu
    }

    // MARK: - Dock / 激活策略

    func applyActivationPolicy() {
        NSApp.setActivationPolicy(settings.showDockIcon ? .regular : .accessory)
    }

    private func applyAppIcon() {
        let name = isDarkAppearance ? "AppIconDark" : "AppIconLight"
        NSApp.applicationIconImage = NSImage(named: name)
    }

    private func installAppearanceObserver() {
        appearanceObserver = DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name("AppleInterfaceThemeChangedNotification"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.applyAppIcon()
            }
        }
    }

    private var isDarkAppearance: Bool {
        NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
    }

    private func installFrontmostAppObserver() {
        rememberExternalFrontmostApp(NSWorkspace.shared.frontmostApplication)
        frontmostAppObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            Task { @MainActor [weak self] in
                self?.rememberExternalFrontmostApp(app)
            }
        }
    }

    private func rememberExternalFrontmostApp(_ app: NSRunningApplication?) {
        guard CaptureTargetResolver.isUsableExternalApp(pid: app?.processIdentifier,
                                                        isTerminated: app?.isTerminated ?? true,
                                                        bundleIdentifier: app?.bundleIdentifier) else {
            return
        }
        lastExternalFrontmostApp = app
    }

    private func currentCaptureTargetApp() -> NSRunningApplication? {
        let frontmost = NSWorkspace.shared.frontmostApplication
        rememberExternalFrontmostApp(frontmost)
        return CaptureTargetResolver.resolve(frontmost: frontmost,
                                             lastExternal: lastExternalFrontmostApp)
    }

    private func statusBarImage() -> NSImage? {
        let image = NSImage(systemSymbolName: "sparkles", accessibilityDescription: "SnapAI")
        image?.isTemplate = true
        return image
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            openSettings()
        }
        return true
    }

    // MARK: - 自动化 URL

    private func installAutomationURLHandler() {
        NSAppleEventManager.shared().setEventHandler(
            self,
            andSelector: #selector(handleAutomationURL(_:withReplyEvent:)),
            forEventClass: AEEventClass(kInternetEventClass),
            andEventID: AEEventID(kAEGetURL)
        )
    }

    @objc private func handleAutomationURL(_ event: NSAppleEventDescriptor,
                                           withReplyEvent replyEvent: NSAppleEventDescriptor) {
        guard let rawURL = event.paramDescriptor(forKeyword: keyDirectObject)?.stringValue,
              let command = AutomationRouter.command(from: rawURL) else {
            return
        }
        runAutomationCommand(command)
    }

    private func runAutomationCommand(_ command: AutomationURLCommand) {
        NSApp.activate(ignoringOtherApps: true)
        switch command {
        case let .run(actionQuery, text, options):
            let action = actionForAutomation(query: actionQuery) ?? settings.enabledActions.first
            guard let action else {
                openSettings()
                return
            }
            previousApp = nil
            previousSelectionSnapshot = nil
            runQuickInput(text: text,
                          action: action.applyingAutomationOptions(options, settings: settings),
                          autoReplaceEnabled: AutomationWriteBackPolicy.urlRun(options: options).autoReplaceEnabled)
        case let .openQuickInput(text, actionQuery):
            previousApp = currentCaptureTargetApp()
            previousSelectionSnapshot = nil
            if let action = actionForAutomation(query: actionQuery) {
                quickInputModel.actionID = action.id
            }
            if let text {
                quickInputModel.text = text
            }
            quickInput.show()
        case let .openSettings(section):
            showSettings(section: settingsSection(for: section))
        case .openHistory:
            openHistoryWindow()
        case .clearHistory:
            clearHistoryFromAutomation()
        case let .copyHistoryMarkdown(criteria):
            copyHistoryMarkdownFromAutomation(criteria: criteria)
        case let .createHistoryContext(criteria, options):
            createHistoryContextProfileFromAutomation(criteria: criteria, options: options)
        case .openCommandPalette:
            openCommandPalette()
        case .openPermissionHealth:
            openPermissionHealth()
        case .copyBriefPermissionDiagnostics:
            copyBriefPermissionDiagnostics()
        case .copyPermissionDiagnostics:
            copyPermissionDiagnostics()
        case .copyPermissionRecoverySuggestions:
            copyPermissionRecoverySuggestions()
        case .revealInstallLog:
            revealLatestInstallLog()
        case .copyInstallLogPath:
            copyLatestInstallLogPath()
        case let .switchModel(providerQuery, modelQuery):
            switchModelFromAutomation(providerQuery: providerQuery, modelQuery: modelQuery)
        case let .switchContext(profileQuery):
            switchContextFromAutomation(profileQuery: profileQuery)
        case let .copyContext(profileQuery):
            copyContextFromAutomation(profileQuery: profileQuery)
        case .copyEffectiveSystemPrompt:
            copyEffectiveSystemPrompt()
        case .copyContextStatus:
            copyContextStatus()
        case .clearContext:
            clearContextFromAutomation()
        case let .setToggle(commandQuery, enabled):
            setToggleFromAutomation(commandQuery: commandQuery, enabled: enabled)
        case let .setRoutingPreference(preference):
            setRoutingPreferenceFromAutomation(preference)
        case let .setWorkMode(mode):
            setWorkModeFromAutomation(mode)
        case let .setDockIcon(enabled):
            setDockIconFromAutomation(enabled)
        case let .setLoginItem(enabled):
            setLoginItemFromAutomation(enabled)
        case let .setTypewriterSpeed(speed):
            setTypewriterSpeedFromAutomation(speed)
        case .checkUpdates:
            checkForUpdates()
        }
    }

    private func switchModelFromAutomation(providerQuery: String?, modelQuery: String?) {
        guard let selection = AutomationModelSelection.resolve(providerQuery: providerQuery,
                                                               modelQuery: modelQuery,
                                                               settings: settings) else {
            showSettings(section: .ai)
            return
        }
        settings.activate(providerID: selection.providerID,
                          model: selection.modelName,
                          recordManualPreference: true)
        buildMenu()
        installMainMenu()
    }

    private func switchContextFromAutomation(profileQuery: String?) {
        guard let selection = AutomationContextSelection.resolve(profileQuery: profileQuery,
                                                                 settings: settings) else {
            showSettings(section: .general)
            return
        }
        settings.activeContextProfileID = selection.profileID
        settings.save()
        iCloudSync.shared.scheduleUpload(settings)
    }

    private func clearContextFromAutomation() {
        settings.activeContextProfileID = ""
        settings.save()
        iCloudSync.shared.scheduleUpload(settings)
    }

    private func copyContextFromAutomation(profileQuery: String?) {
        guard let profile = contextProfileForCopy(profileQuery: profileQuery) else {
            showSettings(section: .general)
            return
        }
        copyContext(profile)
    }

    private func contextProfileForCopy(profileQuery: String?) -> ContextProfile? {
        if let profileQuery = profileQuery?.trimmingCharacters(in: .whitespacesAndNewlines),
           !profileQuery.isEmpty {
            guard let selection = AutomationContextSelection.resolve(profileQuery: profileQuery,
                                                                     settings: settings) else {
                return nil
            }
            return settings.contextProfiles.first { $0.id == selection.profileID }
        }
        return settings.activeContextProfile
    }

    private func copyContext(_ profile: ContextProfile) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(
            profile.markdownExport(isActive: profile.id == settings.activeContextProfileID),
            forType: .string
        )
    }

    private func copyEffectiveSystemPrompt() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(settings.effectiveSystemPromptMarkdownExport,
                                       forType: .string)
    }

    private func copyContextStatus() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(settings.contextStatusMarkdownExport,
                                       forType: .string)
    }

    private func clearHistoryFromAutomation() {
        settings.clearHistory()
        buildMenu()
        installMainMenu()
    }

    private func copyHistoryMarkdownFromAutomation(criteria: HistoryFilterCriteria) {
        copyHistoryMarkdown(criteria: criteria)
    }

    private func createHistoryContextProfileFromAutomation(criteria: HistoryFilterCriteria,
                                                           options: AutomationHistoryContextOptions) {
        createHistoryContextProfile(criteria: criteria,
                                    requiresConfirmation: false,
                                    options: options)
    }

    private func copyHistoryMarkdown(criteria: HistoryFilterCriteria) {
        let export = HistoryCollectionExport(entries: filteredHistoryEntries(criteria: criteria),
                                             criteria: criteria)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(export.markdown, forType: .string)
    }

    private func createHistoryContextProfile(criteria: HistoryFilterCriteria,
                                             requiresConfirmation: Bool = true,
                                             options: AutomationHistoryContextOptions = .empty) {
        let entries = filteredHistoryEntries(criteria: criteria)
        guard var draft = HistoryContextProfileBuilder.draft(entries: entries,
                                                             criteria: criteria,
                                                             maxEntries: options.maxEntries ?? HistoryContextProfileBuilder.defaultMaxEntries,
                                                             maxFieldCharacters: options.maxFieldCharacters ?? HistoryContextProfileBuilder.defaultMaxFieldCharacters) else {
            openHistoryWindow()
            return
        }
        if let name = options.name?.trimmingCharacters(in: .whitespacesAndNewlines),
           !name.isEmpty {
            draft.name = name
        }
        let willUpdate = settings.hasContextProfile(named: draft.name)

        if requiresConfirmation {
            let alert = NSAlert()
            alert.messageText = willUpdate ? "更新上下文包?" : "创建上下文包?"
            alert.informativeText = """
            将 \(draft.includedCount) 条历史写入「\(draft.name)」并设为使用中。

            已跳过 \(draft.skippedCount) 条空内容、仅元信息或超出上限的记录。
            """
            alert.alertStyle = .informational
            alert.addButton(withTitle: willUpdate ? "更新并启用" : "创建并启用")
            alert.addButton(withTitle: "取消")

            guard alert.runModal() == .alertFirstButtonReturn else { return }
        }
        settings.upsertContextProfile(from: draft)
        iCloudSync.shared.scheduleUpload(settings)
        buildMenu()
        installMainMenu()
    }

    private func filteredHistoryEntries(criteria: HistoryFilterCriteria) -> [HistoryEntry] {
        HistorySearch.filteredEntries(criteria: criteria,
                                      memoryEntries: settings.history,
                                      limit: settings.historyLimit,
                                      searchStore: HistoryStore.shared.search)
    }

    private func setToggleFromAutomation(commandQuery: String?, enabled: Bool?) {
        guard let command = SettingsToggleCommand.resolve(commandQuery) else {
            showSettings(section: .general)
            return
        }
        let target = enabled ?? !command.isEnabled(in: settings)
        command.setEnabled(target, in: settings)
        settings.save()
        iCloudSync.shared.scheduleUpload(settings)
        buildMenu()
        installMainMenu()
    }

    private func setRoutingPreferenceFromAutomation(_ preference: AIRoutingPreference?) {
        guard let preference else {
            showSettings(section: .ai)
            return
        }
        settings.routingPreference = preference
        settings.save()
        iCloudSync.shared.scheduleUpload(settings)
    }

    private func setWorkModeFromAutomation(_ mode: WorkModePreset?) {
        guard let mode else {
            showSettings(section: .general)
            return
        }
        applyWorkMode(mode)
    }

    private func setDockIconFromAutomation(_ enabled: Bool?) {
        guard let enabled else {
            showSettings(section: .general)
            return
        }
        settings.showDockIcon = enabled
        settings.save()
        iCloudSync.shared.scheduleUpload(settings)
        applyActivationPolicy()
        buildMenu()
        installMainMenu()
    }

    private func setLoginItemFromAutomation(_ enabled: Bool?) {
        guard let enabled else {
            showSettings(section: .permission)
            return
        }
        if !LoginItem.setEnabled(enabled) {
            showSettings(section: .permission)
        }
    }

    private func setTypewriterSpeedFromAutomation(_ speed: TypewriterSpeed?) {
        guard let speed else {
            showSettings(section: .general)
            return
        }
        settings.typewriterSpeed = speed
        settings.save()
        iCloudSync.shared.scheduleUpload(settings)
    }

    private func actionForAutomation(query: String?) -> AIAction? {
        AutomationActionSelection.resolve(query: query, actions: settings.enabledActions)
    }

    private func settingsSection(for raw: String?) -> SettingsSection {
        AutomationRouter.settingsSection(for: raw,
                                         fallback: windowCoordinator.selectedSettingsSection)
    }

    // MARK: - macOS Services

    private func installServicesProvider() {
        NSApp.servicesProvider = self
        NSUpdateDynamicServices()
    }

    @objc(handleSnapAIService:userData:error:)
    func handleSnapAIService(_ pasteboard: NSPasteboard,
                             userData: String?,
                             error: AutoreleasingUnsafeMutablePointer<NSString?>) {
        let serviceInvocationTarget = currentCaptureTargetApp()
        let action = actionForAutomation(query: userData) ?? settings.enabledActions.first
        guard let action else {
            error.pointee = "SnapAI 还没有可用动作,请先打开设置完成配置。" as NSString
            openSettings()
            return
        }
        guard let text = serviceText(from: pasteboard) else {
            triggerCapturedSelection(action: action,
                                     preferredTarget: serviceInvocationTarget,
                                     forceDismissTransientUIBeforeCopy: true)
            return
        }
        previousApp = serviceInvocationTarget
        previousSelectionSnapshot = nil
        recordTextCaptureOutcome(TextCaptureOutcome(text: text,
                                                    method: .service,
                                                    accessibilityAttempted: false,
                                                    clipboardAttempted: false,
                                                    failureReason: nil,
                                                    pasteboardReasonCode: nil,
                                                    clipboardWaitAttempts: 0))
        runQuickInput(text: text,
                      action: action,
                      originalText: text,
                      autoReplaceEnabled: AutomationWriteBackPolicy.capturedSelection(action: action).autoReplaceEnabled,
                      captureMethod: .service,
                      sourceContext: SelectionSourceContext.make(appName: previousApp?.localizedName))
    }

    private func serviceText(from pasteboard: NSPasteboard) -> String? {
        ServicePasteboardText.text(from: pasteboard)
    }

    // MARK: - 快捷键

    private func registerHotKeys() {
        hotKeyRegistrationFailures = hotKeyCoordinator.registerAll(
            settings: settings,
            actionHandler: { [weak self] actionID in
                self?.triggerAction(id: actionID)
            },
            quickPanelHandler: { [weak self] in
                self?.toggleQuickInput()
            }
        )
    }

    private func reloadAfterSettingsChange() {
        registerHotKeys()
        quickInputModel.actionID = settings.enabledActions.first(where: { $0.id == quickInputModel.actionID })?.id
            ?? settings.enabledActions.first?.id ?? ""
        buildMenu()
        installMainMenu()
        applyActivationPolicy()
    }

    // MARK: - 触发流程

    @objc private func triggerActionFromMenu(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String else { return }
        triggerAction(id: id)
    }

    private func triggerAction(id: String) {
        guard let action = settings.enabledActions.first(where: { $0.id == id }) else { return }
        triggerCapturedSelection(action: action)
    }

    private func triggerCapturedSelection(action: AIAction,
                                          preferredTarget: NSRunningApplication? = nil,
                                          forceDismissTransientUIBeforeCopy: Bool = false) {
        previousApp = captureTargetApp(preferredTarget: preferredTarget)
        previousSelectionSnapshot = nil
        TextCapture.captureDetailed(preferAX: settings.useAXFirst,
                                    targetApp: previousApp,
                                    forceDismissTransientUIBeforeCopy: forceDismissTransientUIBeforeCopy) { [weak self] outcome in
            guard let self = self else { return }
            let text = outcome.usableText
            guard let text = text, !text.isEmpty else {
                self.recordTextCaptureOutcome(outcome)
                self.notifyNoSelection(action: action)
                return
            }
            self.recordTextCaptureOutcome(outcome)
            self.previousSelectionSnapshot = TextCapture.recentSelectionSnapshot(matching: text)
            guard let prepared = self.prepareTextForSubmission(text,
                                                               action: action,
                                                               imageData: nil) else { return }
            self.resultVM.start(text: prepared.text,
                                originalText: text,
                                action: action,
                                submissionPrivacy: prepared.diagnostic,
                                autoReplaceEnabled: AutomationWriteBackPolicy.capturedSelection(action: action).autoReplaceEnabled,
                                captureMethod: outcome.method,
                                sourceContext: SelectionSourceContext.make(appName: self.previousApp?.localizedName))
            self.panelController.show()
        }
    }

    private func captureTargetApp(preferredTarget: NSRunningApplication?) -> NSRunningApplication? {
        guard preferredTarget != nil else {
            return currentCaptureTargetApp()
        }
        let frontmost = NSWorkspace.shared.frontmostApplication
        rememberExternalFrontmostApp(frontmost)
        return CaptureTargetResolver.resolveDeferred(serviceInvocation: preferredTarget,
                                                     frontmost: frontmost,
                                                     lastExternal: lastExternalFrontmostApp)
    }

    @objc private func toggleQuickInputFromMenu(_ sender: Any?) {
        toggleQuickInput()
    }

    private func toggleQuickInput() {
        previousApp = currentCaptureTargetApp()
        previousSelectionSnapshot = nil
        quickInput.toggle()
    }

    private func runQuickInput(text: String,
                               action: AIAction,
                               originalText: String? = nil,
                               imageData: Data? = nil,
                               imageMimeType: String = "image/png",
                               autoReplaceEnabled: Bool = false,
                               captureMethod: TextCaptureMethod? = nil,
                               sourceContext: SelectionSourceContext? = nil) {
        quickInput.hide()
        guard let prepared = prepareTextForSubmission(text,
                                                      action: action,
                                                      imageData: imageData) else { return }
        resultVM.start(text: prepared.text,
                       originalText: originalText,
                       action: action,
                       imageData: imageData,
                       imageMimeType: imageMimeType,
                       submissionPrivacy: prepared.diagnostic,
                       autoReplaceEnabled: autoReplaceEnabled,
                       captureMethod: captureMethod,
                       sourceContext: sourceContext)
        panelController.show()
    }

    private func prepareTextForSubmission(_ text: String,
                                          action: AIAction,
                                          imageData: Data?,
                                          userPromptOverride: String? = nil) -> PrivacyPreparedSubmission? {
        let redactionPreview = settings.redactionEnabled
            ? PrivacyFilter.preview(text: text, rules: settings.redactionRules)
            : PrivacyRedactionPreview(output: text, reports: [])
        let processedOverride = userPromptOverride.map { _ in redactionPreview.output }
        let preview = PrivacySubmissionPreview(action: action,
                                               originalText: text,
                                               redactionPreview: redactionPreview,
                                               systemPrompt: settings.effectiveSystemPrompt,
                                               redactionEnabled: settings.redactionEnabled,
                                               hasImage: imageData != nil,
                                               historyContentStorage: settings.historyContentStorage,
                                               userPromptOverride: processedOverride)
        let previewRequirement = preview.previewRequirement(userPreferenceEnabled: settings.privacyPreviewEnabled)
        let prepared = PrivacyPreparedSubmission(
            text: preview.processedText,
            diagnostic: preview.diagnostic(previewRequirement: previewRequirement)
        )
        guard previewRequirement.isRequired else { return prepared }
        return confirmPrivacyPreview(preview, requirement: previewRequirement) ? prepared : nil
    }

    private func confirmPrivacyPreview(_ preview: PrivacySubmissionPreview,
                                       requirement: PrivacyPreviewRequirement) -> Bool {
        let alert = NSAlert()
        alert.messageText = "发送给 AI 前确认"
        alert.informativeText = requirement.confirmationMessage(redactionEnabled: preview.redactionEnabled)
        alert.alertStyle = .informational
        alert.addButton(withTitle: "发送")
        alert.addButton(withTitle: "取消")

        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 560, height: 240))
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder
        let textView = NSTextView(frame: scroll.bounds)
        textView.isEditable = false
        textView.isSelectable = true
        textView.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        textView.string = preview.contentText(previewRequirement: requirement)
        textView.textContainerInset = NSSize(width: 8, height: 8)
        scroll.documentView = textView
        alert.accessoryView = scroll
        NSApp.activate(ignoringOtherApps: true)
        return alert.runModal() == .alertFirstButtonReturn
    }

    /// 把结果替换回原文位置(#3)
    private func replaceSelection(original: String, with replacement: String) {
        defer {
            previousSelectionSnapshot = nil
            TextCapture.clearRecentSelectionSnapshot()
        }
        let decision = DiffPreviewWindowController.present(original: original,
                                                           revised: replacement,
                                                           actionName: resultVM.action.name)
        switch decision {
        case .replace:
            guard let writeBackTarget = validatedWriteBackTarget() else {
                copyWriteBackFallback(text: replacement,
                                      operation: .replace,
                                      originalCharacterCount: original.count,
                                      title: "无法自动替换",
                                      reason: writeBackTargetUnavailableReason())
                return
            }
            panelController.hide()
            TextEditTransaction(targetApp: writeBackTarget,
                                selectionSnapshot: previousSelectionSnapshot)
                .replace(original: original, with: replacement) { [weak self] in
                    self?.recordWriteBack(targetApp: writeBackTarget,
                                          original: original,
                                          replacement: replacement)
                } failure: { [weak self] snapshot in
                    self?.handleUnsafePasteboardWriteBack(operation: .replace,
                                                         originalCharacterCount: original.count,
                                                         payloadCharacterCount: replacement.count,
                                                         snapshot: snapshot)
                }
        case .copy:
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(replacement, forType: .string)
        case .cancel:
            break
        }
    }

    /// 把结果追加到光标后(#8):先发 → 键移到选区末尾,再粘贴 "\n" + result
    private func appendSelection(with text: String) {
        guard let writeBackTarget = validatedWriteBackTarget() else {
            copyWriteBackFallback(text: text,
                                  operation: .append,
                                  originalCharacterCount: 0,
                                  title: "无法自动追加",
                                  reason: writeBackTargetUnavailableReason())
            return
        }
        let insertedText = TextWriteBackPayload.appendPayload(for: text)
        TextEditTransaction(targetApp: writeBackTarget).append(text) { [weak self] in
            self?.recordWriteBack(targetApp: writeBackTarget,
                                  operation: .append,
                                  original: "",
                                  replacement: insertedText)
        } failure: { [weak self] snapshot in
            self?.handleUnsafePasteboardWriteBack(operation: .append,
                                                 originalCharacterCount: 0,
                                                 payloadCharacterCount: insertedText.count,
                                                 snapshot: snapshot)
        }
    }

    private func validatedWriteBackTarget() -> NSRunningApplication? {
        guard let target = previousApp,
              !target.isTerminated,
              target.processIdentifier != ProcessInfo.processInfo.processIdentifier else {
            return nil
        }
        return target
    }

    private func writeBackTargetUnavailableReason() -> String {
        guard let target = previousApp else {
            return "没有可信的原应用目标。"
        }
        let appName = MarkdownExportSafety.metadata(target.localizedName,
                                                    fallback: "原应用",
                                                    maxLength: 80)
        if target.isTerminated {
            return "\(appName) 已退出。"
        }
        if target.processIdentifier == ProcessInfo.processInfo.processIdentifier {
            return "当前目标是 SnapAI 自身。"
        }
        return "\(appName) 暂不可用。"
    }

    private func copyWriteBackFallback(text: String,
                                       operation: TextWriteBackOperation,
                                       originalCharacterCount: Int,
                                       title: String,
                                       reason: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        let diagnostic = TextWriteBackFallbackDiagnostic(operation: operation,
                                                         targetApp: previousApp,
                                                         reason: reason,
                                                         copiedToPasteboard: true,
                                                         originalCharacterCount: originalCharacterCount,
                                                         payloadCharacterCount: text.count)
        lastWriteBackStatusSummary = diagnostic.diagnosticSummary
        presentWriteBackNotice(title: title,
                               message: diagnostic.noticeMessage,
                               showsDiagnosticsButton: true)
    }

    private func handleUnsafePasteboardWriteBack(operation: TextWriteBackOperation,
                                                 originalCharacterCount: Int,
                                                 payloadCharacterCount: Int,
                                                 snapshot: PasteboardSnapshot) {
        let diagnostic = TextWriteBackFallbackDiagnostic(operation: operation,
                                                         targetApp: previousApp,
                                                         reason: "\(snapshot.recoveryMessage) reason=\(snapshot.reasonCode), bytes=\(snapshot.totalByteCount), items=\(snapshot.itemCount), types=\(snapshot.typeCount)",
                                                         copiedToPasteboard: false,
                                                         originalCharacterCount: originalCharacterCount,
                                                         payloadCharacterCount: payloadCharacterCount,
                                                         recoveryOverride: snapshot.recoveryMessage)
        lastWriteBackStatusSummary = diagnostic.diagnosticSummary
        presentWriteBackNotice(title: "已取消自动写回",
                               message: diagnostic.noticeMessage,
                               showsDiagnosticsButton: true)
    }

    private func presentWriteBackNotice(title: String,
                                        message: String,
                                        showsDiagnosticsButton: Bool = false) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .informational
        alert.addButton(withTitle: "好")
        if showsDiagnosticsButton {
            alert.addButton(withTitle: "打开权限健康中心")
        }
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertSecondButtonReturn,
           showsDiagnosticsButton {
            openPermissionHealth()
        }
    }

    private func recordWriteBack(targetApp: NSRunningApplication?,
                                 operation: TextWriteBackOperation = .replace,
                                 original: String,
                                 replacement: String) {
        lastWriteBackRecord = TextWriteBackRecord(targetApp: targetApp,
                                                  operation: operation,
                                                  originalText: original,
                                                  replacementText: replacement)
        lastWriteBackStatusSummary = lastWriteBackRecord?.diagnosticSummary
        buildMenu()
        installMainMenu()
    }

    private func currentWriteBackStatusSummary() -> String? {
        WriteBackCommandFactory.statusSummary(for: lastWriteBackRecord,
                                              fallback: lastWriteBackStatusSummary)
    }

    private func recordTextCaptureOutcome(_ outcome: TextCaptureOutcome) {
        let characterCount = outcome.usableText?.count ?? 0
        let diagnostic = characterCount > 0
            ? TextCaptureDiagnostic.captured(accessibilityGranted: TextCapture.hasAccessibilityPermission(),
                                             preferAX: settings.useAXFirst,
                                             frontmostAppName: previousApp?.localizedName,
                                             characterCount: characterCount,
                                             method: outcome.method,
                                             clipboardWaitAttempts: outcome.clipboardWaitAttempts)
            : TextCaptureDiagnostic.noSelection(accessibilityGranted: TextCapture.hasAccessibilityPermission(),
                                                preferAX: settings.useAXFirst,
                                                frontmostAppName: previousApp?.localizedName,
                                                failureReason: outcome.failureReason,
                                                pasteboardReasonCode: outcome.pasteboardReasonCode,
                                                clipboardWaitAttempts: outcome.clipboardWaitAttempts)
        lastTextCaptureStatusSummary = diagnostic.diagnosticSummary
    }

    private func currentTextCaptureStatusSummary() -> String? {
        lastTextCaptureStatusSummary
    }

    private func undoWriteBackMenuTitle() -> String {
        WriteBackCommandFactory.undoMenuTitle(for: lastWriteBackRecord)
    }

    @objc private func undoLastWriteBackFromMenu(_ sender: Any?) {
        undoLastWriteBack()
    }

    private func undoLastWriteBack() {
        guard let record = lastWriteBackRecord else {
            lastWriteBackRecord = nil
            buildMenu()
            installMainMenu()
            return
        }
        guard record.isUndoAvailable else {
            lastWriteBackStatusSummary = record.diagnosticSummary
            lastWriteBackRecord = nil
            buildMenu()
            installMainMenu()
            return
        }
        lastWriteBackRecord = nil
        buildMenu()
        installMainMenu()
        guard let target = validatedUndoTarget(for: record) else {
            let reason = undoTargetUnavailableReason(for: record)
            let copiedOriginal = record.operation == .replace && !record.originalText.isEmpty
            if copiedOriginal {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(record.originalText, forType: .string)
            }
            let diagnostic = TextWriteBackUndoFallbackDiagnostic(record: record,
                                                                 reason: reason,
                                                                 copiedOriginalToPasteboard: copiedOriginal)
            lastWriteBackStatusSummary = diagnostic.diagnosticSummary
            presentWriteBackNotice(title: "无法自动撤销写回",
                                   message: diagnostic.noticeMessage)
            return
        }
        TextEditTransaction(targetApp: target)
            .replace(original: record.replacementText, with: record.originalText) { [weak self] in
                self?.lastWriteBackStatusSummary = "state=undo-completed, operation=\(record.operation.diagnosticName)"
            } failure: { [weak self] snapshot in
                self?.handleUnsafePasteboardUndo(record: record,
                                                 snapshot: snapshot)
            }
    }

    private func handleUnsafePasteboardUndo(record: TextWriteBackRecord,
                                            snapshot: PasteboardSnapshot) {
        let diagnostic = TextWriteBackUndoFallbackDiagnostic(
            record: record,
            reason: "\(snapshot.undoRecoveryMessage) reason=\(snapshot.reasonCode), bytes=\(snapshot.totalByteCount), items=\(snapshot.itemCount), types=\(snapshot.typeCount)",
            copiedOriginalToPasteboard: false,
            recoveryOverride: snapshot.undoRecoveryMessage
        )
        lastWriteBackStatusSummary = diagnostic.diagnosticSummary
        presentWriteBackNotice(title: "已取消自动撤销写回",
                               message: diagnostic.noticeMessage,
                               showsDiagnosticsButton: true)
    }

    private func validatedUndoTarget(for record: TextWriteBackRecord) -> NSRunningApplication? {
        guard record.isUndoAvailable,
              let target = record.targetApp,
              !target.isTerminated,
              target.processIdentifier != ProcessInfo.processInfo.processIdentifier else {
            return nil
        }
        return target
    }

    private func undoTargetUnavailableReason(for record: TextWriteBackRecord) -> String {
        switch record.undoState() {
        case .expired:
            return "上次写回记录已过期。"
        case .missingOriginal:
            return "缺少可恢复的原文。"
        case .missingReplacement:
            return "缺少上次写回内容。"
        case .targetTerminated:
            return "原应用已退出。"
        case .targetIsCurrentApp:
            return "目标应用是 SnapAI 自身。"
        case .available:
            return "原应用目标不可用。"
        }
    }

    private func notifyNoSelection(action: AIAction? = nil) {
        let alert = NSAlert()
        alert.messageText = TextCaptureRecoveryGuide.title
        alert.informativeText = TextCaptureRecoveryGuide.message
        alert.alertStyle = .informational
        alert.addButton(withTitle: TextCaptureRecoveryGuide.defaultButtonTitle)
        alert.addButton(withTitle: TextCaptureRecoveryGuide.quickInputButtonTitle)
        alert.addButton(withTitle: TextCaptureRecoveryGuide.permissionHealthButtonTitle)
        alert.addButton(withTitle: TextCaptureRecoveryGuide.accessibilitySettingsButtonTitle)
        NSApp.activate(ignoringOtherApps: true)
        let response = alert.runModal()
        switch response {
        case .alertSecondButtonReturn:
            if let action,
               settings.enabledActions.contains(where: { $0.id == action.id }) {
                quickInputModel.actionID = action.id
            }
            quickInput.show()
        case .alertThirdButtonReturn:
            openPermissionHealth()
        case NSApplication.ModalResponse(rawValue: NSApplication.ModalResponse.alertFirstButtonReturn.rawValue + 3):
            NSWorkspace.shared.open(TextCaptureRecoveryGuide.accessibilitySettingsURL)
        default:
            break
        }
    }

    @objc private func openCommandPaletteFromMenu(_ sender: Any?) {
        openCommandPalette()
    }

    @objc private func openCommandPalette() {
        commandPalette.show()
    }

    @objc private func openHistoryWindowFromMenu(_ sender: Any?) {
        openHistoryWindow()
    }

    @objc private func openHistoryWindow() {
        historyWindow.show()
    }

    @objc private func openPermissionHealthFromMenu(_ sender: Any?) {
        openPermissionHealth()
    }

    @objc private func openPermissionHealth() {
        permissionHealth.show()
    }

    private func copyPermissionDiagnostics() {
        copyPermissionDiagnostics(full: true)
    }

    private func copyBriefPermissionDiagnostics() {
        copyPermissionDiagnostics(full: false)
    }

    private func currentPermissionHealthSnapshot() -> PermissionHealthSnapshot {
        currentPermissionHealthSnapshot(includeSigningSummary: true)
    }

    private func currentPermissionHealthSnapshot(includeSigningSummary: Bool) -> PermissionHealthSnapshot {
        PermissionHealthSnapshot.make(
            settings: settings,
            hotKeyFailures: hotKeyRegistrationFailures,
            textCaptureStatus: currentTextCaptureStatusSummary() ?? "none",
            writeBackStatus: currentWriteBackStatusSummary() ?? "none",
            recentAIRequestStatus: resultVM?.requestHealthStatusText ?? "none",
            includeSigningSummary: includeSigningSummary
        )
    }

    private func copyPermissionDiagnostics(full: Bool) {
        let snapshot = currentPermissionHealthSnapshot()
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(full ? snapshot.diagnosticText : snapshot.briefDiagnosticText, forType: .string)
    }

    @objc private func copyPermissionRecoverySuggestionsFromMenu(_ sender: Any?) {
        copyPermissionRecoverySuggestions()
    }

    private func copyPermissionRecoverySuggestions() {
        let snapshot = currentPermissionHealthSnapshot(includeSigningSummary: false)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(snapshot.recoverySuggestionClipboardText, forType: .string)
    }

    private func revealLatestInstallLog() {
        guard let url = UpdateChecker.latestInstallLogURL() else {
            openPermissionHealth()
            return
        }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    private func copyLatestInstallLogPath() {
        guard let url = UpdateChecker.latestInstallLogURL() else {
            openPermissionHealth()
            return
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(url.path, forType: .string)
    }

    private func toggleSettingsWindowPinnedFromCommandPalette() {
        windowCoordinator.toggleSettingsWindowPinnedAndShow()
    }

    @objc private func copyResultFromMenu(_ sender: Any?) {
        copyResult()
    }

    private func copyResult() {
        resultVM.copyOutput()
    }

    @objc private func copyConversationMarkdownFromMenu(_ sender: Any?) {
        copyConversationMarkdown()
    }

    private func copyConversationMarkdown() {
        resultVM.copyConversationMarkdown()
    }

    @objc private func copyRequestDiagnosticsFromMenu(_ sender: Any?) {
        copyRequestDiagnostics()
    }

    private func copyRequestDiagnostics() {
        resultVM.copyRequestDiagnostics()
    }

    @objc private func copyBriefRequestDiagnosticsFromMenu(_ sender: Any?) {
        copyBriefRequestDiagnostics()
    }

    private func copyBriefRequestDiagnostics() {
        resultVM.copyBriefRequestDiagnostics()
    }

    @objc private func openAISettingsFromResultMenu(_ sender: Any?) {
        openAISettingsFromResult()
    }

    private func openAISettingsFromResult() {
        showSettings(section: .ai)
    }

    @objc private func replaceResultFromMenu(_ sender: Any?) {
        replaceResult()
    }

    private func replaceResult() {
        resultVM.replaceOriginal()
    }

    @objc private func appendResultFromMenu(_ sender: Any?) {
        appendResult()
    }

    private func appendResult() {
        resultVM.appendToDocument()
    }

    @objc private func exportResultFromMenu(_ sender: Any?) {
        exportResult()
    }

    private func exportResult() {
        resultVM.exportConversation()
    }

    @objc private func regenerateResultFromMenu(_ sender: Any?) {
        regenerateResult()
    }

    private func regenerateResult() {
        resultVM.regenerate()
    }

    @objc private func stopResultFromMenu(_ sender: Any?) {
        stopResult()
    }

    private func stopResult() {
        resultVM.cancel()
    }

    @objc private func togglePinResultFromMenu(_ sender: Any?) {
        togglePinResult()
    }

    private func togglePinResult() {
        resultVM.isPinned.toggle()
        panelController.show()
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if let selector = menuItem.action,
           let action = resultCommandAction(for: selector) {
            let state = resultCommandState
            menuItem.title = ResultCommandFactory.menuTitle(for: action, in: state)
            menuItem.toolTip = ResultCommandFactory.menuToolTip(for: action, in: state)
            return ResultCommandFactory.isEnabled(action, in: state)
        }
        switch menuItem.action {
        case #selector(togglePinResultFromMenu(_:)):
            menuItem.title = ResultPinCommand.title(isPinned: resultVM.isPinned)
            return true
        case #selector(undoLastWriteBackFromMenu(_:)):
            return lastWriteBackRecord?.isUndoAvailable == true
        default:
            return true
        }
    }

    private var resultCommandState: ResultCommandState {
        ResultCommandState(resultText: resultVM.completeText,
                           diagnosticsText: resultVM.requestDiagnosticText,
                           isStreaming: resultVM.isStreaming,
                           sourceText: resultVM.sourceText,
                           protectsContentExport: resultVM.contentExportProtectionEnabled,
                           recoveryCode: resultVM.errorRecoveryCode)
    }

    private func resultCommandAction(for selector: Selector) -> ResultCommandAction? {
        ResultCommandFactory.menuDescriptors()
            .first { self.selector(for: $0.action) == selector }?
            .action
    }

    private func commandPaletteItems() -> [CommandPaletteItem] {
        var items: [CommandPaletteItem] = []
        items.append(CommandPaletteItem(
            id: "quick",
            title: "快捷提问",
            subtitle: "打开快捷提问面板",
            systemImage: "sparkles",
            keywords: "quick prompt ask",
            shortcutText: settings.quickPanelHotKey.displayString,
            perform: { [weak self] in self?.toggleQuickInput() }
        ))
        if let descriptor = WriteBackCommandFactory.undoDescriptor(for: lastWriteBackRecord) {
            items.append(CommandPaletteItem(
                id: descriptor.id,
                title: descriptor.title,
                subtitle: descriptor.subtitle,
                systemImage: descriptor.systemImage,
                keywords: descriptor.keywords,
                shortcutText: descriptor.shortcutText,
                perform: { [weak self] in
                    self?.performWriteBackCommand(descriptor.action)
                }
            ))
        }
        for descriptor in ActionCommandFactory.descriptors(for: settings.actions,
                                                           usageCounts: settings.actionUsageCounts,
                                                           hotKeyDisplay: { $0.hotKey?.displayString }) {
            items.append(CommandPaletteItem(
                id: descriptor.id,
                title: descriptor.title,
                subtitle: descriptor.subtitle,
                systemImage: descriptor.systemImage,
                keywords: descriptor.keywords,
                shortcutText: descriptor.shortcutText,
                perform: { [weak self] in self?.triggerAction(id: descriptor.actionID) }
            ))
        }
        appendResultCommandPaletteItems(to: &items)
        appendResultPinCommandPaletteItem(to: &items)
        for descriptor in ModelSwitchCommandFactory.descriptors(providers: settings.providers,
                                                                activeProviderID: settings.activeProvider?.id,
                                                                activeModel: settings.model) {
            items.append(CommandPaletteItem(
                id: descriptor.id,
                title: descriptor.title,
                subtitle: descriptor.subtitle,
                systemImage: descriptor.systemImage,
                keywords: descriptor.keywords,
                perform: { [weak self] in
                    self?.settings.activate(providerID: descriptor.providerID,
                                            model: descriptor.modelName,
                                            recordManualPreference: true)
                    self?.buildMenu()
                    self?.installMainMenu()
                }
            ))
        }
        appendRoutingPreferenceCommandPaletteItems(to: &items)
        appendContextProfileCommandPaletteItems(to: &items)
        for entry in settings.history.filter(\.canReopen).prefix(30) {
            items.append(CommandPaletteItem(
                id: "history-\(entry.id)",
                title: entry.preview,
                subtitle: entry.commandPaletteSubtitle,
                systemImage: entry.isFavorite ? "star.fill" : "clock.arrow.circlepath",
                keywords: entry.commandPaletteKeywords,
                perform: { [weak self] in self?.reopenHistoryEntry(entry) }
            ))
        }
        appendWorkModeCommandPaletteItems(to: &items)
        appendSettingsToggleCommandPaletteItems(to: &items)
        appendDisplayBehaviorCommandPaletteItems(to: &items)
        appendActionTemplateCommandPaletteItems(to: &items)
        appendHistoryExportCommandPaletteItems(to: &items)
        appendHistoryContextCommandPaletteItems(to: &items)
        items.append(contentsOf: [
            CommandPaletteItem(
                id: "history-window",
                title: "打开历史记录",
                subtitle: "搜索、收藏、删除历史",
                systemImage: "clock",
                keywords: "history",
                perform: { [weak self] in self?.openHistoryWindow() }
            ),
            CommandPaletteItem(
                id: "settings",
                title: "打开设置",
                subtitle: "供应商、动作、隐私、快捷键",
                systemImage: "gearshape",
                keywords: "settings preferences",
                perform: { [weak self] in self?.openSettings() }
            ),
            CommandPaletteItem(
                id: "settings-ai",
                title: "打开 AI 模型设置",
                subtitle: "供应商、模型、自动路由、fallback",
                systemImage: "cpu",
                keywords: "settings preferences ai model provider route fallback 模型 供应商 路由",
                perform: { [weak self] in self?.showSettings(section: .ai) }
            ),
            CommandPaletteItem(
                id: "settings-actions",
                title: "打开动作设置",
                subtitle: "动作、Prompt、快捷键、默认替换",
                systemImage: "wand.and.stars",
                keywords: "settings preferences action prompt hotkey replace 动作 快捷键",
                perform: { [weak self] in self?.showSettings(section: .actions) }
            ),
            CommandPaletteItem(
                id: "settings-history",
                title: "打开历史设置",
                subtitle: "历史保留、统计、清理",
                systemImage: "clock.arrow.circlepath",
                keywords: "settings preferences history favorite export 历史 统计",
                perform: { [weak self] in self?.showSettings(section: .history) }
            ),
            CommandPaletteItem(
                id: "settings-general",
                title: "打开通用设置",
                subtitle: "隐私、上下文、iCloud、显示",
                systemImage: "slider.horizontal.3",
                keywords: "settings preferences general privacy redaction context icloud dock 通用 隐私 脱敏 上下文",
                perform: { [weak self] in self?.showSettings(section: .general) }
            ),
            CommandPaletteItem(
                id: "settings-window-pin",
                title: SettingsWindowPinCommand.title(isPinned: windowCoordinator.isSettingsWindowPinned),
                subtitle: SettingsWindowPinCommand.subtitle(isPinned: windowCoordinator.isSettingsWindowPinned),
                systemImage: SettingsWindowPinCommand.systemImage(isPinned: windowCoordinator.isSettingsWindowPinned),
                keywords: SettingsWindowPinCommand.keywords,
                perform: { [weak self] in self?.toggleSettingsWindowPinnedFromCommandPalette() }
            ),
            CommandPaletteItem(
                id: "settings-permission",
                title: "打开权限设置",
                subtitle: "辅助功能、屏幕录制、开机启动",
                systemImage: "checkmark.shield",
                keywords: "settings preferences permission accessibility screen login 权限 辅助功能 屏幕录制",
                perform: { [weak self] in self?.showSettings(section: .permission) }
            ),
            CommandPaletteItem(
                id: "health",
                title: "权限健康中心",
                subtitle: "权限、签名、快捷键诊断",
                systemImage: "lock.shield",
                keywords: "permission diagnostics signing hotkey",
                perform: { [weak self] in self?.openPermissionHealth() }
            ),
            CommandPaletteItem(
                id: "copy-health-diagnostics-summary",
                title: "复制精简权限诊断",
                subtitle: "权限、AI 请求、隐私和签名摘要",
                systemImage: "doc.on.clipboard",
                keywords: "permission diagnostics summary brief signing hotkey update copy 权限 诊断 摘要 精简 复制",
                perform: { [weak self] in self?.copyBriefPermissionDiagnostics() }
            ),
            CommandPaletteItem(
                id: "copy-health-diagnostics",
                title: "复制完整权限诊断",
                subtitle: "完整权限、签名、更新日志和写回状态",
                systemImage: "doc.text",
                keywords: "permission diagnostics full signing hotkey update log copy 权限 诊断 完整 复制",
                perform: { [weak self] in self?.copyPermissionDiagnostics() }
            ),
            CommandPaletteItem(
                id: "copy-health-recovery-suggestions",
                title: PermissionRecoveryCommand.title,
                subtitle: PermissionRecoveryCommand.subtitle(
                    statusLine: currentPermissionHealthSnapshot(includeSigningSummary: false).recoverySuggestionStatusLine
                ),
                systemImage: PermissionRecoveryCommand.systemImage,
                keywords: PermissionRecoveryCommand.keywords,
                perform: { [weak self] in self?.copyPermissionRecoverySuggestions() }
            ),
            CommandPaletteItem(
                id: "reveal-install-log",
                title: "显示安装日志",
                subtitle: InstallLogCommand.subtitle(for: UpdateChecker.latestInstallLogStatus()),
                systemImage: "doc.text.magnifyingglass",
                keywords: "update install log reveal finder xattr quarantine 更新 安装 日志 显示",
                perform: { [weak self] in self?.revealLatestInstallLog() }
            ),
            CommandPaletteItem(
                id: "copy-install-log-path",
                title: "复制安装日志路径",
                subtitle: InstallLogCommand.subtitle(for: UpdateChecker.latestInstallLogStatus()),
                systemImage: "link",
                keywords: "update install log path copy xattr quarantine 更新 安装 日志 路径 复制",
                perform: { [weak self] in self?.copyLatestInstallLogPath() }
            ),
            CommandPaletteItem(
                id: "updates",
                title: "检查更新",
                subtitle: "GitHub Release",
                systemImage: "arrow.down.circle",
                keywords: "update release",
                perform: { [weak self] in self?.checkForUpdates() }
            )
        ])
        return items
    }

    private func performWriteBackCommand(_ action: WriteBackCommandAction) {
        switch action {
        case .undoLastWriteBack:
            undoLastWriteBack()
        }
    }

    private func appendActionTemplateCommandPaletteItems(to items: inout [CommandPaletteItem]) {
        for template in ActionTemplateLibrary.builtIns {
            items.append(CommandPaletteItem(
                id: "action-template-\(template.id)",
                title: "添加动作模板: \(template.title)",
                subtitle: "\(template.category) · \(template.summary)",
                systemImage: template.action.icon.isEmpty ? "wand.and.stars" : template.action.icon,
                keywords: MarkdownExportSafety.keywords([
                    "action template library market import share prompt add 动作 模板 动作库 市场 分享 添加",
                    template.title,
                    template.category,
                    template.summary,
                    template.action.prompt
                ]),
                perform: { [weak self] in
                    self?.installActionTemplate(template)
                }
            ))
        }
    }

    private func installActionTemplate(_ template: ActionTemplate) {
        let action = ActionTemplateLibrary.installedAction(from: template,
                                                           existingActions: settings.actions)
        settings.actions.append(action)
        settings.save()
        registerHotKeys()
        buildMenu()
        installMainMenu()
    }

    private func appendDisplayBehaviorCommandPaletteItems(to items: inout [CommandPaletteItem]) {
        for descriptor in DisplayBehaviorCommandFactory.descriptors(showDockIcon: settings.showDockIcon,
                                                                    loginItemEnabled: LoginItem.isEnabled,
                                                                    typewriterSpeed: settings.typewriterSpeed) {
            items.append(CommandPaletteItem(
                id: descriptor.id,
                title: descriptor.title,
                subtitle: descriptor.subtitle,
                systemImage: descriptor.systemImage,
                keywords: descriptor.keywords,
                perform: { [weak self] in
                    self?.performDisplayBehaviorCommand(descriptor.action)
                }
            ))
        }
    }

    private func performDisplayBehaviorCommand(_ action: DisplayBehaviorCommandAction) {
        switch action {
        case .setDockIcon(let enabled):
            setDockIconFromAutomation(enabled)
        case .setLoginItem(let enabled):
            setLoginItemFromAutomation(enabled)
        case .setTypewriterSpeed(let speed):
            setTypewriterSpeedFromAutomation(speed)
        }
    }

    private func appendHistoryExportCommandPaletteItems(to items: inout [CommandPaletteItem]) {
        for descriptor in HistoryExportCommandFactory.descriptors(for: settings.history) {
            items.append(CommandPaletteItem(
                id: descriptor.id,
                title: descriptor.title,
                subtitle: descriptor.subtitle,
                systemImage: descriptor.systemImage,
                keywords: descriptor.keywords,
                perform: { [weak self] in
                    self?.copyHistoryMarkdown(criteria: descriptor.criteria)
                }
            ))
        }
    }

    private func appendHistoryContextCommandPaletteItems(to items: inout [CommandPaletteItem]) {
        for descriptor in HistoryContextCommandFactory.descriptors(for: settings.history) {
            items.append(CommandPaletteItem(
                id: descriptor.id,
                title: descriptor.title,
                subtitle: descriptor.subtitle,
                systemImage: descriptor.systemImage,
                keywords: descriptor.keywords,
                perform: { [weak self] in
                    self?.createHistoryContextProfile(criteria: descriptor.criteria)
                }
            ))
        }
    }

    private func appendRoutingPreferenceCommandPaletteItems(to items: inout [CommandPaletteItem]) {
        for descriptor in RoutingContextCommandFactory.routingDescriptors(current: settings.routingPreference) {
            items.append(CommandPaletteItem(
                id: descriptor.id,
                title: descriptor.title,
                subtitle: descriptor.subtitle,
                systemImage: descriptor.systemImage,
                keywords: descriptor.keywords,
                perform: { [weak self] in
                    self?.performRoutingContextCommand(descriptor.action)
                }
            ))
        }
    }

    private func appendContextProfileCommandPaletteItems(to items: inout [CommandPaletteItem]) {
        for descriptor in RoutingContextCommandFactory.contextDescriptors(profiles: settings.contextProfiles,
                                                                         activeProfileID: settings.activeContextProfileID) {
            items.append(CommandPaletteItem(
                id: descriptor.id,
                title: descriptor.title,
                subtitle: descriptor.subtitle,
                systemImage: descriptor.systemImage,
                keywords: descriptor.keywords,
                perform: { [weak self] in
                    self?.performRoutingContextCommand(descriptor.action)
                }
            ))
        }
    }

    private func performRoutingContextCommand(_ action: RoutingContextCommandAction) {
        switch action {
        case .setRoutingPreference(let preference):
            setRoutingPreferenceFromAutomation(preference)
        case .clearContext:
            clearContextFromAutomation()
        case .copyActiveContext:
            copyContextFromAutomation(profileQuery: nil)
        case .copyEffectiveSystemPrompt:
            copyEffectiveSystemPrompt()
        case .copyContextStatus:
            copyContextStatus()
        case .setContextProfile(let profileID):
            switchContextFromAutomation(profileQuery: profileID)
        }
    }

    private func appendSettingsToggleCommandPaletteItems(to items: inout [CommandPaletteItem]) {
        for command in SettingsToggleCommand.allCases {
            let enabled = command.isEnabled(in: settings)
            items.append(CommandPaletteItem(
                id: command.id,
                title: command.title(isEnabled: enabled),
                subtitle: command.subtitle(isEnabled: enabled),
                systemImage: command.systemImage,
                keywords: command.keywords,
                perform: { [weak self] in
                    self?.toggleSetting(command)
                }
            ))
        }
    }

    private func toggleSetting(_ command: SettingsToggleCommand) {
        command.setEnabled(!command.isEnabled(in: settings), in: settings)
        settings.save()
        iCloudSync.shared.scheduleUpload(settings)
        buildMenu()
        installMainMenu()
    }

    private func appendWorkModeCommandPaletteItems(to items: inout [CommandPaletteItem]) {
        for descriptor in WorkModeCommandFactory.descriptors(current: settings.matchingWorkModePreset) {
            items.append(CommandPaletteItem(
                id: descriptor.id,
                title: descriptor.title,
                subtitle: descriptor.subtitle,
                systemImage: descriptor.systemImage,
                keywords: descriptor.keywords,
                perform: { [weak self] in
                    self?.performWorkModeCommand(descriptor.action)
                }
            ))
        }
    }

    private func performWorkModeCommand(_ action: WorkModeCommandAction) {
        switch action {
        case .apply(let mode):
            applyWorkMode(mode)
        }
    }

    private func applyWorkMode(_ mode: WorkModePreset) {
        settings.applyWorkMode(mode)
        settings.save()
        iCloudSync.shared.scheduleUpload(settings)
        buildMenu()
        installMainMenu()
    }

    private func appendResultCommandPaletteItems(to items: inout [CommandPaletteItem]) {
        guard resultVM != nil else { return }
        for descriptor in ResultCommandFactory.descriptors(state: resultCommandState) {
            items.append(CommandPaletteItem(
                id: descriptor.id,
                title: descriptor.title,
                subtitle: descriptor.subtitle,
                systemImage: descriptor.systemImage,
                keywords: descriptor.keywords,
                shortcutText: ResultCommandFactory.shortcutText(for: descriptor.action),
                perform: { [weak self] in
                    self?.performResultCommand(descriptor.action)
                }
            ))
        }
    }

    private func appendResultPinCommandPaletteItem(to items: inout [CommandPaletteItem]) {
        items.append(CommandPaletteItem(
            id: "result-pin-toggle",
            title: ResultPinCommand.title(isPinned: resultVM.isPinned),
            subtitle: ResultPinCommand.subtitle(isPinned: resultVM.isPinned),
            systemImage: ResultPinCommand.systemImage(isPinned: resultVM.isPinned),
            keywords: ResultPinCommand.keywords,
            shortcutText: ResultPinCommand.shortcutText,
            perform: { [weak self] in
                self?.togglePinResult()
            }
        ))
    }

    private func performResultCommand(_ action: ResultCommandAction) {
        switch action {
        case .copyOutput:
            copyResult()
        case .copyMarkdown:
            copyConversationMarkdown()
        case .exportConversation:
            exportResult()
        case .copyBriefDiagnostics:
            copyBriefRequestDiagnostics()
        case .copyDiagnostics:
            copyRequestDiagnostics()
        case .openAISettings:
            openAISettingsFromResult()
        case .replaceOriginal:
            replaceResult()
        case .appendToDocument:
            appendResult()
        case .stop:
            stopResult()
        case .regenerate:
            regenerateResult()
        }
    }

    // MARK: - 设置窗口

    @objc private func openSettingsFromMenu(_ sender: Any?) {
        openSettings()
    }

    private func openSettings() {
        windowCoordinator.openSettings()
    }

    private func showSettings(section: SettingsSection) {
        windowCoordinator.showSettings(section: section)
    }

    @objc private func checkForUpdatesFromMenu(_ sender: Any?) {
        checkForUpdates()
    }

    private func checkForUpdates() {
        UpdateChecker.check()
    }

    // MARK: - 引导页(#14)

    private func showOnboarding() {
        windowCoordinator.showOnboarding()
    }
}
