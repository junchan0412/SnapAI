import AppKit
import SnapAILogic

/// 状态栏菜单装配:从 AppDelegate 抽出,纯装配函数,host 仍为 AppDelegate。
///
/// 约束:所有 #selector 指向 AppDelegate 的 @objc 方法,本类型不新增
/// selector —— 菜单点击行为归属不变,只是装配代码换了位置。
@MainActor
enum StatusMenuBuilder {
    static func build(for host: AppDelegate) {
        let menu = NSMenu()

        // 动作 — 按 group 分组(#10)
        let allActions = host.settings.enabledActions
        let grouped = Dictionary(grouping: allActions) { groupTitle(for: $0.group) }
        func addActionItem(_ action: AIAction) {
            let item = NSMenuItem(title: actionTitle(for: action.name),
                                  action: #selector(AppDelegate.triggerActionFromMenu(_:)),
                                  keyEquivalent: "")
            item.target = host
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
                                       action: #selector(AppDelegate.openCommandPaletteFromMenu(_:)),
                                       keyEquivalent: "k")
        paletteItem.target = host
        paletteItem.keyEquivalentModifierMask = [.command]

        // 快捷提问面板
        let quickItem = menu.addItem(withTitle: "快捷提问 (\(host.settings.quickPanelHotKey.displayString))",
                                     action: #selector(AppDelegate.toggleQuickInputFromMenu(_:)), keyEquivalent: "")
        quickItem.target = host
        MenuCoordinator.configureShortcut(quickItem, combo: host.settings.quickPanelHotKey)
        menu.addItem(.separator())

        if !host.hotKeyRegistrationFailures.isEmpty {
            let warning = NSMenuItem(title: "快捷键注册异常", action: nil, keyEquivalent: "")
            let sub = NSMenu()
            for message in host.hotKeyRegistrationFailures.prefix(8) {
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
        if let p = host.settings.activeProvider, !host.settings.model.isEmpty {
            let providerName = MarkdownExportSafety.metadata(p.name,
                                                              fallback: "未命名供应商",
                                                              maxLength: 80)
            let modelName = MarkdownExportSafety.metadata(host.settings.model,
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
        workModeItem.submenu = workModeMenu(for: host)
        menu.addItem(workModeItem)

        let switchItem = NSMenuItem(title: "切换模型", action: nil, keyEquivalent: "")
        switchItem.submenu = MenuCoordinator.modelSwitchMenu(settings: host.settings,
                                                             target: host,
                                                             action: #selector(AppDelegate.switchModel(_:)),
                                                             settingsTarget: host,
                                                             settingsAction: #selector(AppDelegate.openSettingsFromMenu(_:)))
        menu.addItem(switchItem)

        // 历史
        let historyItem = NSMenuItem(title: "历史记录", action: nil, keyEquivalent: "")
        historyItem.submenu = historyMenu(for: host)
        menu.addItem(historyItem)

        menu.addItem(.separator())
        let undoWriteBack = menu.addItem(withTitle: host.undoWriteBackMenuTitle(),
                                         action: #selector(AppDelegate.undoLastWriteBackFromMenu(_:)),
                                         keyEquivalent: "")
        undoWriteBack.target = host
        menu.addItem(.separator())
        menu.addItem(withTitle: "设置…", action: #selector(AppDelegate.openSettingsFromMenu(_:)), keyEquivalent: ",").target = host
        menu.addItem(withTitle: "权限健康中心…", action: #selector(AppDelegate.openPermissionHealthFromMenu(_:)), keyEquivalent: "").target = host
        menu.addItem(withTitle: PermissionRecoveryCommand.title,
                     action: #selector(AppDelegate.copyPermissionRecoverySuggestionsFromMenu(_:)),
                     keyEquivalent: "").target = host
        menu.addItem(withTitle: "检查更新…", action: #selector(AppDelegate.checkForUpdatesFromMenu(_:)), keyEquivalent: "").target = host
        menu.addItem(.separator())
        menu.addItem(withTitle: "退出 SnapAI", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        host.statusItem.menu = menu
    }

    static func actionTitle(for name: String) -> String {
        MarkdownExportSafety.metadata(name, fallback: "未命名动作", maxLength: 80)
    }

    static func groupTitle(for group: String) -> String {
        MarkdownExportSafety.metadata(group, fallback: "", maxLength: 80)
    }

    static func workModeMenu(for host: AppDelegate) -> NSMenu {
        let sub = NSMenu()
        let currentMode = host.settings.matchingWorkModePreset
        let currentTitle = NSMenuItem(title: "当前:\(host.settings.workModeStatusTitle)",
                                      action: nil,
                                      keyEquivalent: "")
        currentTitle.isEnabled = false
        sub.addItem(currentTitle)
        sub.addItem(.separator())
        for mode in WorkModePreset.allCases {
            let item = NSMenuItem(title: mode.title,
                                  action: #selector(AppDelegate.selectWorkModeFromMenu(_:)),
                                  keyEquivalent: "")
            item.target = host
            item.representedObject = mode.rawValue
            item.state = currentMode == mode ? .on : .off
            item.toolTip = mode.summary
            sub.addItem(item)
        }
        return sub
    }

    static func historyMenu(for host: AppDelegate) -> NSMenu {
        let sub = NSMenu()
        let open = sub.addItem(withTitle: "打开历史记录…", action: #selector(AppDelegate.openHistoryWindowFromMenu(_:)), keyEquivalent: "")
        open.target = host
        sub.addItem(.separator())
        if host.settings.history.isEmpty {
            let item = NSMenuItem(title: "(暂无记录)", action: nil, keyEquivalent: "")
            item.isEnabled = false
            sub.addItem(item)
            return sub
        }
        for entry in host.settings.history.prefix(5) {
            let item = NSMenuItem(title: entry.menuTitle,
                                  action: #selector(AppDelegate.reopenHistory(_:)), keyEquivalent: "")
            item.target = host
            item.representedObject = entry.id
            item.isEnabled = entry.canReopen
            item.toolTip = entry.reopenHelpText
            sub.addItem(item)
        }
        sub.addItem(.separator())
        let clear = sub.addItem(withTitle: "清空历史", action: #selector(AppDelegate.clearHistory), keyEquivalent: "")
        clear.target = host
        return sub
    }

    static func addResultCommands(to menu: NSMenu, for host: AppDelegate) {
        for descriptor in ResultCommandFactory.menuDescriptors() {
            let item = menu.addItem(withTitle: descriptor.title,
                                    action: host.selector(for: descriptor.action),
                                    keyEquivalent: descriptor.keyEquivalent)
            item.target = host
            item.keyEquivalentModifierMask = host.nsModifierFlags(for: descriptor.modifiers)
        }

        let pin = menu.addItem(withTitle: ResultPinCommand.title(isPinned: host.resultVM.isPinned),
                               action: #selector(AppDelegate.togglePinResultFromMenu(_:)),
                               keyEquivalent: ResultPinCommand.keyEquivalent)
        pin.target = host
        pin.keyEquivalentModifierMask = host.nsModifierFlags(for: ResultPinCommand.modifiers)
    }

    static func selector(for action: ResultCommandAction) -> Selector {
        switch action {
        case .copyOutput:
            return #selector(AppDelegate.copyResultFromMenu(_:))
        case .copyMarkdown:
            return #selector(AppDelegate.copyConversationMarkdownFromMenu(_:))
        case .exportConversation:
            return #selector(AppDelegate.exportResultFromMenu(_:))
        case .copyBriefDiagnostics:
            return #selector(AppDelegate.copyBriefRequestDiagnosticsFromMenu(_:))
        case .copyDiagnostics:
            return #selector(AppDelegate.copyRequestDiagnosticsFromMenu(_:))
        case .openAISettings:
            return #selector(AppDelegate.openAISettingsFromResultMenu(_:))
        case .replaceOriginal:
            return #selector(AppDelegate.replaceResultFromMenu(_:))
        case .appendToDocument:
            return #selector(AppDelegate.appendResultFromMenu(_:))
        case .stop:
            return #selector(AppDelegate.stopResultFromMenu(_:))
        case .regenerate:
            return #selector(AppDelegate.regenerateResultFromMenu(_:))
        }
    }

    static func modifierFlags(for modifiers: [ResultMenuModifier]) -> NSEvent.ModifierFlags {
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
}
