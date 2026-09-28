import AppKit
import SnapAILogic

/// 主菜单装配(应用菜单/操作/编辑/窗口):从 AppDelegate 抽出。
/// 与 StatusMenuBuilder 同一约束:selector 全部指向 AppDelegate,不新增行为。
@MainActor
enum MainMenuBuilder {
    static func install(for host: AppDelegate) {
        let mainMenu = NSMenu()

        let appMenuItem = NSMenuItem()
        mainMenu.addItem(appMenuItem)
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "关于 SnapAI",
                        action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)),
                        keyEquivalent: "")
        appMenu.addItem(.separator())
        let prefItem = appMenu.addItem(withTitle: "设置…",
                                       action: #selector(AppDelegate.openSettingsFromMenu(_:)),
                                       keyEquivalent: ",")
        prefItem.target = host
        let updateItem = appMenu.addItem(withTitle: "检查更新…",
                                         action: #selector(AppDelegate.checkForUpdatesFromMenu(_:)),
                                         keyEquivalent: "")
        updateItem.target = host
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
                                            action: #selector(AppDelegate.openCommandPaletteFromMenu(_:)),
                                            keyEquivalent: "k")
        palette.target = host
        palette.keyEquivalentModifierMask = [.command]
        let quick = operationMenu.addItem(withTitle: "快捷提问",
                                          action: #selector(AppDelegate.toggleQuickInputFromMenu(_:)),
                                          keyEquivalent: "")
        quick.target = host
        MenuCoordinator.configureShortcut(quick, combo: host.settings.quickPanelHotKey)
        let workMode = NSMenuItem(title: "工作模式", action: nil, keyEquivalent: "")
        workMode.submenu = StatusMenuBuilder.workModeMenu(for: host)
        operationMenu.addItem(workMode)
        operationMenu.addItem(.separator())
        for action in host.settings.enabledActions {
            let item = NSMenuItem(title: action.name,
                                  action: #selector(AppDelegate.triggerActionFromMenu(_:)),
                                  keyEquivalent: "")
            item.target = host
            item.representedObject = action.id
            MenuCoordinator.configureShortcut(item, combo: action.hotKey)
            operationMenu.addItem(item)
        }
        operationMenu.addItem(.separator())
        host.addResultCommandItems(to: operationMenu)
        let undoWriteBack = operationMenu.addItem(withTitle: host.undoWriteBackMenuTitle(),
                                                  action: #selector(AppDelegate.undoLastWriteBackFromMenu(_:)),
                                                  keyEquivalent: "z")
        undoWriteBack.target = host
        undoWriteBack.keyEquivalentModifierMask = [.command, .option]
        operationMenu.addItem(.separator())
        operationMenu.addItem(withTitle: "打开历史记录…", action: #selector(AppDelegate.openHistoryWindowFromMenu(_:)), keyEquivalent: "").target = host
        operationMenu.addItem(withTitle: "权限健康中心…", action: #selector(AppDelegate.openPermissionHealthFromMenu(_:)), keyEquivalent: "").target = host
        operationMenu.addItem(withTitle: PermissionRecoveryCommand.title,
                              action: #selector(AppDelegate.copyPermissionRecoverySuggestionsFromMenu(_:)),
                              keyEquivalent: "").target = host
        operationMenu.addItem(withTitle: "检查更新…", action: #selector(AppDelegate.checkForUpdatesFromMenu(_:)), keyEquivalent: "").target = host
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

}
