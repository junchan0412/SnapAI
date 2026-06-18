import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let settings = AppSettings.shared
    private var statusItem: NSStatusItem!
    private var resultVM: ResultViewModel!
    private var panelController: FloatingPanelController!
    private var quickInput: QuickInputController!
    private var quickInputModel: QuickInputModel!
    private var settingsWindow: NSWindow?
    private var onboardingWindow: NSWindow?
    private var appearanceObserver: NSObjectProtocol?
    private var hotKeyRegistrationFailures: [String] = []
    /// 触发前的前台 App,用于「替换原文」时把焦点交还
    private var previousApp: NSRunningApplication?

    /// nonisolated 以便在 main.swift 顶层(非 main-actor 上下文)构造
    nonisolated override init() {
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        applyActivationPolicy()
        applyAppIcon()
        installAppearanceObserver()
        iCloudSync.shared.pullIfNeeded(into: settings)

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = statusBarImage()
        }

        resultVM = ResultViewModel(settings: settings)
        resultVM.onReplace = { [weak self] text in self?.replaceSelection(with: text) }
        resultVM.onAppend = { [weak self] text in self?.appendSelection(with: text) }   // #8
        panelController = FloatingPanelController(vm: resultVM)

        quickInputModel = QuickInputModel(settings: settings)
        quickInputModel.actionID = settings.enabledActions.first?.id ?? ""
        quickInputModel.onSubmit = { [weak self] text, action, imageData in   // #3 imageData
            self?.runQuickInput(text: text, action: action, imageData: imageData)
        }
        quickInput = QuickInputController(model: quickInputModel)

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
        let grouped = Dictionary(grouping: allActions) { $0.group }
        func addActionItem(_ action: AIAction) {
            let suffix = action.hotKey.map { " (\($0.displayString))" } ?? ""
            let item = NSMenuItem(title: "\(action.name)\(suffix)",
                                  action: #selector(triggerActionFromMenu(_:)),
                                  keyEquivalent: "")
            item.target = self
            item.representedObject = action.id
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

        // 快捷提问面板
        let quickItem = menu.addItem(withTitle: "快捷提问 (\(settings.quickPanelHotKey.displayString))",
                                     action: #selector(toggleQuickInput), keyEquivalent: "")
        quickItem.target = self
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
        if let p = settings.activeProvider, !settings.activeModel.isEmpty {
            currentTitle = "当前:\(p.name) / \(settings.activeModel)"
        } else {
            currentTitle = "当前:未选择模型"
        }
        let currentItem = NSMenuItem(title: currentTitle, action: nil, keyEquivalent: "")
        currentItem.isEnabled = false
        menu.addItem(currentItem)

        let switchItem = NSMenuItem(title: "切换模型", action: nil, keyEquivalent: "")
        switchItem.submenu = buildModelSwitchMenu()
        menu.addItem(switchItem)

        // 历史
        let historyItem = NSMenuItem(title: "历史记录", action: nil, keyEquivalent: "")
        historyItem.submenu = buildHistoryMenu()
        menu.addItem(historyItem)

        menu.addItem(.separator())
        menu.addItem(withTitle: "设置…", action: #selector(openSettings), keyEquivalent: ",").target = self
        menu.addItem(withTitle: "检查更新…", action: #selector(checkForUpdates), keyEquivalent: "").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "退出 SnapAI", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        statusItem.menu = menu
    }

    private func buildModelSwitchMenu() -> NSMenu {
        let sub = NSMenu()
        let enabledProviders = settings.providers.filter { $0.isEnabled }
        if enabledProviders.isEmpty {
            let item = NSMenuItem(title: "无可用配置,请到设置添加", action: nil, keyEquivalent: "")
            item.isEnabled = false
            sub.addItem(item)
            return sub
        }
        for provider in enabledProviders {
            let names = provider.enabledModelNames
            if names.isEmpty { continue }
            let header = NSMenuItem(title: provider.name, action: nil, keyEquivalent: "")
            header.isEnabled = false
            sub.addItem(header)
            for model in names {
                let item = NSMenuItem(title: "  \(model)",
                                      action: #selector(switchModel(_:)),
                                      keyEquivalent: "")
                item.target = self
                item.representedObject = ["provider": provider.id, "model": model]
                if provider.id == settings.activeProviderID && model == settings.activeModel {
                    item.state = .on
                }
                sub.addItem(item)
            }
            sub.addItem(.separator())
        }
        return sub
    }

    private func buildHistoryMenu() -> NSMenu {
        let sub = NSMenu()
        if settings.history.isEmpty {
            let item = NSMenuItem(title: "(暂无记录)", action: nil, keyEquivalent: "")
            item.isEnabled = false
            sub.addItem(item)
            return sub
        }
        for entry in settings.history.prefix(15) {
            let item = NSMenuItem(title: "[\(entry.actionName)] \(entry.preview)",
                                  action: #selector(reopenHistory(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = entry.id
            sub.addItem(item)
        }
        sub.addItem(.separator())
        let clear = sub.addItem(withTitle: "清空历史", action: #selector(clearHistory), keyEquivalent: "")
        clear.target = self
        return sub
    }

    @objc private func switchModel(_ sender: NSMenuItem) {
        guard let info = sender.representedObject as? [String: String],
              let pid = info["provider"], let model = info["model"] else { return }
        settings.activate(providerID: pid, model: model)
        buildMenu()
    }

    @objc private func reopenHistory(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String,
              let entry = settings.history.first(where: { $0.id == id }) else { return }
        // 用历史里的原文 + 同名动作重新发起
        let action = settings.enabledActions.first(where: { $0.name == entry.actionName })
            ?? settings.enabledActions.first
        guard let action = action else { return }
        previousApp = NSWorkspace.shared.frontmostApplication
        resultVM.start(text: entry.source, action: action)
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
                                       action: #selector(openSettings),
                                       keyEquivalent: ",")
        prefItem.target = self
        let updateItem = appMenu.addItem(withTitle: "检查更新…",
                                         action: #selector(checkForUpdates),
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

    // MARK: - 快捷键

    private func registerHotKeys() {
        HotKeyManager.shared.unregisterAll()
        hotKeyRegistrationFailures = []
        var used: [HotKeyCombo: String] = [:]

        func register(_ combo: HotKeyCombo, label: String, handler: @escaping () -> Void) {
            guard combo.modifiers != 0 else { return }
            if let existing = used[combo] {
                hotKeyRegistrationFailures.append("\(label) 与 \(existing) 冲突: \(combo.displayString)")
                return
            }
            used[combo] = label
            if HotKeyManager.shared.register(combo, handler: handler) == nil {
                hotKeyRegistrationFailures.append("\(label) 注册失败: \(combo.displayString)")
            }
        }

        // 各动作的快捷键
        for action in settings.enabledActions {
            guard let hk = action.hotKey else { continue }
            let actionID = action.id
            register(hk, label: "动作「\(action.name)」") { [weak self] in
                self?.triggerAction(id: actionID)
            }
        }
        // 快捷提问面板
        register(settings.quickPanelHotKey, label: "快捷提问面板") { [weak self] in
            self?.toggleQuickInput()
        }
        if !hotKeyRegistrationFailures.isEmpty {
            NSLog("SnapAI: 快捷键注册异常 - \(hotKeyRegistrationFailures.joined(separator: "; "))")
        }
    }

    private func reloadAfterSettingsChange() {
        registerHotKeys()
        quickInputModel.actionID = settings.enabledActions.first(where: { $0.id == quickInputModel.actionID })?.id
            ?? settings.enabledActions.first?.id ?? ""
        buildMenu()
        applyActivationPolicy()
    }

    // MARK: - 触发流程

    @objc private func triggerActionFromMenu(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String else { return }
        triggerAction(id: id)
    }

    private func triggerAction(id: String) {
        guard let action = settings.enabledActions.first(where: { $0.id == id }) else { return }
        previousApp = NSWorkspace.shared.frontmostApplication
        TextCapture.capture(preferAX: settings.useAXFirst) { [weak self] text in
            guard let self = self else { return }
            guard let text = text, !text.isEmpty else {
                self.notifyNoSelection()
                return
            }
            self.resultVM.start(text: text, action: action)
            self.panelController.show()
        }
    }

    @objc private func toggleQuickInput() {
        previousApp = NSWorkspace.shared.frontmostApplication
        quickInput.toggle()
    }

    private func runQuickInput(text: String, action: AIAction, imageData: Data? = nil) {
        quickInput.hide()
        resultVM.start(text: text, action: action, imageData: imageData)
        panelController.show()
    }

    /// 把结果替换回原文位置(#3)
    private func replaceSelection(with text: String) {
        panelController.hide()
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)
        previousApp?.activate()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
            TextCapture.sendCmdV()
        }
    }

    /// 把结果追加到光标后(#8):先发 → 键移到选区末尾,再粘贴 "\n" + result
    private func appendSelection(with text: String) {
        let appended = "\n" + text
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(appended, forType: .string)
        previousApp?.activate()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
            // 先右箭头取消选中(光标移到选区末尾)
            if let src = CGEventSource(stateID: .combinedSessionState) {
                let right = CGEvent(keyboardEventSource: src, virtualKey: 124, keyDown: true)
                right?.post(tap: .cghidEventTap)
                CGEvent(keyboardEventSource: src, virtualKey: 124, keyDown: false)?.post(tap: .cghidEventTap)
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                TextCapture.sendCmdV()
            }
        }
    }

    private func notifyNoSelection() {
        let alert = NSAlert()
        alert.messageText = "未检测到选中的文字"
        alert.informativeText = "请先在任意应用中选中一段文字,再触发 SnapAI。\n或用「快捷提问」直接输入问题。\n若反复失败,请到「设置 → 权限」确认已授予辅助功能权限。"
        alert.alertStyle = .informational
        alert.addButton(withTitle: "好")
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }

    // MARK: - 设置窗口

    @objc private func openSettings() {
        if let w = settingsWindow {
            w.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let view = SettingsView(settings: settings) { [weak self] in
            self?.reloadAfterSettingsChange()
        }
        let hosting = NSHostingController(rootView: view)
        let window = NSWindow(contentViewController: hosting)
        window.title = "SnapAI 设置"
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.isReleasedWhenClosed = false
        window.center()
        settingsWindow = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func checkForUpdates() {
        UpdateChecker.check()
    }

    // MARK: - 引导页(#14)

    private func showOnboarding() {
        if let w = onboardingWindow {
            w.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let view = OnboardingView(settings: settings) { [weak self] in
            self?.settings.onboardingDone = true
            self?.settings.save()
            self?.onboardingWindow?.close()
            self?.onboardingWindow = nil
            self?.reloadAfterSettingsChange()
        } openSettings: { [weak self] in
            self?.openSettings()
        }
        let hosting = NSHostingController(rootView: view)
        let window = NSWindow(contentViewController: hosting)
        window.title = "欢迎使用 SnapAI"
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        window.center()
        onboardingWindow = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
