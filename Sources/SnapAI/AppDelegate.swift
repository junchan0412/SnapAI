import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let settings = AppSettings.shared
    private var statusItem: NSStatusItem!
    private var resultVM: ResultViewModel!
    private var panelController: FloatingPanelController!
    private var settingsWindow: NSWindow?
    private var appearanceObserver: NSObjectProtocol?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // 按设置决定是否显示 Dock 图标
        applyActivationPolicy()
        applyAppIcon()
        installAppearanceObserver()

        // 菜单栏图标(始终常驻)
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = statusBarImage()
        }
        buildMenu()
        installMainMenu()   // 提供完整主菜单(含 Edit 菜单,使文本框 ⌘C/V/X/A/Z 生效)

        resultVM = ResultViewModel(settings: settings)
        panelController = FloatingPanelController(vm: resultVM)

        registerHotKeys()

        // 首次启动若无权限,提示授权
        if !TextCapture.hasAccessibilityPermission() {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                _ = TextCapture.hasAccessibilityPermission(prompt: true)
            }
        }
    }

    // MARK: - 菜单

    private func buildMenu() {
        let menu = NSMenu()
        menu.addItem(withTitle: "AI 提问 (\(settings.askHotKey.displayString))",
                     action: #selector(triggerAsk), keyEquivalent: "").target = self
        menu.addItem(withTitle: "翻译 (\(settings.translateHotKey.displayString))",
                     action: #selector(triggerTranslate), keyEquivalent: "").target = self
        menu.addItem(.separator())

        // 当前模型 + 快速切换子菜单
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

        menu.addItem(.separator())
        menu.addItem(withTitle: "设置…", action: #selector(openSettings), keyEquivalent: ",").target = self
        menu.addItem(withTitle: "检查更新…", action: #selector(checkForUpdates), keyEquivalent: "").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "退出 SnapAI", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        statusItem.menu = menu
    }

    /// 构建「切换模型」子菜单:按启用供应商分组,列出其启用的模型,勾选当前激活项
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
            // 供应商名作为分组标题(禁用项)
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

    @objc private func switchModel(_ sender: NSMenuItem) {
        guard let info = sender.representedObject as? [String: String],
              let pid = info["provider"], let model = info["model"] else { return }
        settings.activate(providerID: pid, model: model)
        buildMenu()   // 刷新勾选与「当前」标题
    }

    /// 安装完整主菜单(App / 编辑 / 窗口 / 帮助)。
    /// 含 Edit 菜单使文本框响应 ⌘C/V/X/A/Z;含 App 菜单使 Dock 图标右键、
    /// 顶部菜单栏拥有「设置/隐藏/退出」等标准项。
    private func installMainMenu() {
        let mainMenu = NSMenu()

        // ── App 菜单 ──
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

        // ── 编辑菜单 ──
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

        // ── 窗口菜单 ──
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

    /// 按设置应用激活策略:显示 Dock 图标用 .regular,否则 .accessory(仅菜单栏)
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
            self?.applyAppIcon()
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

    /// 点击 Dock 图标(无窗口时)→ 打开设置窗
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            openSettings()
        }
        return true
    }

    // MARK: - 快捷键

    private func registerHotKeys() {
        HotKeyManager.shared.unregisterAll()
        HotKeyManager.shared.register(settings.askHotKey) { [weak self] in
            self?.trigger(mode: .ask)
        }
        HotKeyManager.shared.register(settings.translateHotKey) { [weak self] in
            self?.trigger(mode: .translate)
        }
    }

    private func reloadAfterSettingsChange() {
        registerHotKeys()
        buildMenu()
        applyActivationPolicy()
    }

    // MARK: - 触发流程

    @objc private func triggerAsk() { trigger(mode: .ask) }
    @objc private func triggerTranslate() { trigger(mode: .translate) }

    private func trigger(mode: ResultViewModel.Mode) {
        TextCapture.capture(preferAX: settings.useAXFirst) { [weak self] text in
            guard let self = self else { return }
            guard let text = text, !text.isEmpty else {
                self.notifyNoSelection()
                return
            }
            self.resultVM.start(text: text, mode: mode)
            self.panelController.show()
        }
    }

    private func notifyNoSelection() {
        let alert = NSAlert()
        alert.messageText = "未检测到选中的文字"
        alert.informativeText = "请先在任意应用中选中一段文字,再触发 SnapAI。\n若反复失败,请到「设置 → 权限」确认已授予辅助功能权限。"
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
        UpdateChecker.check(presenting: settingsWindow)
    }
}
