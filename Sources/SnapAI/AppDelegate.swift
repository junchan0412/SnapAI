import AppKit
import SwiftUI
import Carbon
import SnapAILogic

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuItemValidation {
    let settings = AppSettings.shared
    var statusItem: NSStatusItem!
    var resultVM: ResultViewModel!
    var panelController: FloatingPanelController!
    var quickInput: QuickInputController!
    var quickInputModel: QuickInputModel!
    var commandPalette: CommandPaletteController!
    var historyWindow: HistoryWindowController!
    var permissionHealth: PermissionHealthController!
    var windowCoordinator: WindowCoordinator!
    var appearanceObserver: NSObjectProtocol?
    var frontmostAppObserver: NSObjectProtocol?
    let hotKeyCoordinator = HotKeyCoordinator()
    var hotKeyRegistrationFailures: [String] = []
    /// 触发前的前台 App,用于「替换原文」时把焦点交还
    var previousApp: NSRunningApplication?
    var lastExternalFrontmostApp: NSRunningApplication?
    var previousSelectionSnapshot: TextSelectionSnapshot?
    var previousCaptureMethod: TextCaptureMethod?
    var lastTextCaptureStatusSummary: String?
    var lastWriteBackRecord: TextWriteBackRecord?
    var lastWriteBackStatusSummary: String?

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

    func buildMenu() {
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

    func menuActionTitle(for name: String) -> String {
        MarkdownExportSafety.metadata(name, fallback: "未命名动作", maxLength: 80)
    }

    func menuGroupTitle(for group: String) -> String {
        MarkdownExportSafety.metadata(group, fallback: "", maxLength: 80)
    }

    func buildWorkModeMenu() -> NSMenu {
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

    func buildHistoryMenu() -> NSMenu {
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

    func addResultCommandItems(to menu: NSMenu) {
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

    func selector(for action: ResultCommandAction) -> Selector {
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

    func nsModifierFlags(for modifiers: [ResultMenuModifier]) -> NSEvent.ModifierFlags {
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

    @objc func switchModel(_ sender: NSMenuItem) {
        guard let info = sender.representedObject as? [String: String],
              let pid = info["provider"], let model = info["model"] else { return }
        settings.activate(providerID: pid, model: model, recordManualPreference: true)
        buildMenu()
        installMainMenu()
    }

    @objc func selectWorkModeFromMenu(_ sender: NSMenuItem) {
        guard let rawValue = sender.representedObject as? String,
              let mode = WorkModePreset(rawValue: rawValue) else {
            showSettings(section: .general)
            return
        }
        applyWorkMode(mode)
    }

    @objc func reopenHistory(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String,
              let entry = settings.history.first(where: { $0.id == id }) else { return }
        reopenHistoryEntry(entry)
    }

    func reopenHistoryEntry(_ entry: HistoryEntry) {
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

    @objc func clearHistory() {
        settings.clearHistory()
        buildMenu()
    }

    func installMainMenu() {
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

    func applyAppIcon() {
        let name = isDarkAppearance ? "AppIconDark" : "AppIconLight"
        NSApp.applicationIconImage = NSImage(named: name)
    }

    func installAppearanceObserver() {
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

    var isDarkAppearance: Bool {
        NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
    }

    func installFrontmostAppObserver() {
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

    func rememberExternalFrontmostApp(_ app: NSRunningApplication?) {
        guard CaptureTargetResolver.isUsableExternalApp(pid: app?.processIdentifier,
                                                        isTerminated: app?.isTerminated ?? true,
                                                        bundleIdentifier: app?.bundleIdentifier) else {
            return
        }
        lastExternalFrontmostApp = app
    }

    func currentCaptureTargetApp() -> NSRunningApplication? {
        let frontmost = NSWorkspace.shared.frontmostApplication
        rememberExternalFrontmostApp(frontmost)
        return CaptureTargetResolver.resolve(frontmost: frontmost,
                                             lastExternal: lastExternalFrontmostApp)
    }

    func statusBarImage() -> NSImage? {
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

    // MARK: - 快捷键

    func registerHotKeys() {
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

    func reloadAfterSettingsChange() {
        registerHotKeys()
        quickInputModel.actionID = settings.enabledActions.first(where: { $0.id == quickInputModel.actionID })?.id
            ?? settings.enabledActions.first?.id ?? ""
        buildMenu()
        installMainMenu()
        applyActivationPolicy()
    }

    // MARK: - 触发流程

    @objc func triggerActionFromMenu(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String else { return }
        triggerAction(id: id)
    }

    func triggerAction(id: String) {
        guard let action = settings.enabledActions.first(where: { $0.id == id }) else { return }
        triggerCapturedSelection(action: action)
    }

    func triggerCapturedSelection(action: AIAction,
                                          preferredTarget: NSRunningApplication? = nil,
                                          forceDismissTransientUIBeforeCopy: Bool = false) {
        previousApp = captureTargetApp(preferredTarget: preferredTarget)
        previousSelectionSnapshot = nil
        previousCaptureMethod = nil
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
            self.previousCaptureMethod = outcome.method
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

    func captureTargetApp(preferredTarget: NSRunningApplication?) -> NSRunningApplication? {
        guard preferredTarget != nil else {
            return currentCaptureTargetApp()
        }
        let frontmost = NSWorkspace.shared.frontmostApplication
        rememberExternalFrontmostApp(frontmost)
        return CaptureTargetResolver.resolveDeferred(serviceInvocation: preferredTarget,
                                                     frontmost: frontmost,
                                                     lastExternal: lastExternalFrontmostApp)
    }

    @objc func toggleQuickInputFromMenu(_ sender: Any?) {
        toggleQuickInput()
    }

    func toggleQuickInput() {
        previousApp = currentCaptureTargetApp()
        previousSelectionSnapshot = nil
        previousCaptureMethod = nil
        quickInput.toggle()
    }

    func runQuickInput(text: String,
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

    func prepareTextForSubmission(_ text: String,
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

    func confirmPrivacyPreview(_ preview: PrivacySubmissionPreview,
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

    func notifyNoSelection(action: AIAction? = nil) {
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

    // MARK: - 设置窗口

    @objc func openSettingsFromMenu(_ sender: Any?) {
        openSettings()
    }

    func openSettings() {
        windowCoordinator.openSettings()
    }

    func showSettings(section: SettingsSection) {
        windowCoordinator.showSettings(section: section)
    }

    @objc func checkForUpdatesFromMenu(_ sender: Any?) {
        checkForUpdates()
    }

    func checkForUpdates() {
        UpdateCheckerApp.check()
    }

    // MARK: - 引导页(#14)

    func showOnboarding() {
        windowCoordinator.showOnboarding()
    }
}
