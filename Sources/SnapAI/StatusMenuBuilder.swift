import AppKit
import SnapAILogic

/// 状态栏菜单装配：带原生 SF Symbols 图标与清晰分组层级。
@MainActor
enum StatusMenuBuilder {
    static func build(for host: AppDelegate) {
        let menu = NSMenu()

        // 快捷提问与命令面板置顶，最常用操作一键直达
        let quickItem = menu.addItem(withTitle: "快捷提问",
                                     action: #selector(AppDelegate.toggleQuickInputFromMenu(_:)),
                                     keyEquivalent: "")
        quickItem.target = host
        quickItem.image = symbol("sparkles")
        MenuCoordinator.configureShortcut(quickItem, combo: host.settings.quickPanelHotKey)

        let paletteItem = menu.addItem(withTitle: "命令面板…",
                                       action: #selector(AppDelegate.openCommandPaletteFromMenu(_:)),
                                       keyEquivalent: "k")
        paletteItem.target = host
        paletteItem.keyEquivalentModifierMask = [.command]
        paletteItem.image = symbol("command")

        menu.addItem(.separator())

        // 选区动作（按分组排列）
        let allActions = host.settings.enabledActions
        let grouped = Dictionary(grouping: allActions) { groupTitle(for: $0.group) }
        func addActionItem(_ action: AIAction) {
            let item = NSMenuItem(title: actionTitle(for: action.name),
                                  action: #selector(AppDelegate.triggerActionFromMenu(_:)),
                                  keyEquivalent: "")
            item.target = host
            item.representedObject = action.id
            item.image = symbol(action.icon.isEmpty ? "wand.and.stars" : action.icon)
            MenuCoordinator.configureShortcut(item, combo: action.hotKey)
            menu.addItem(item)
        }
        (grouped[""] ?? []).forEach { addActionItem($0) }
        for key in grouped.keys.sorted() where !key.isEmpty {
            menu.addItem(.separator())
            let header = NSMenuItem(title: key, action: nil, keyEquivalent: "")
            header.isEnabled = false
            menu.addItem(header)
            (grouped[key] ?? []).forEach { addActionItem($0) }
        }
        menu.addItem(.separator())

        if !host.hotKeyRegistrationFailures.isEmpty {
            let warning = NSMenuItem(title: "快捷键冲突或未生效", action: nil, keyEquivalent: "")
            warning.image = symbol("exclamationmark.triangle")
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

        // 模型与工作模式
        let currentTitle: String
        if let p = host.settings.activeProvider, !host.settings.model.isEmpty {
            let providerName = MarkdownExportSafety.metadata(p.name, fallback: "未命名供应商", maxLength: 80)
            let modelName = MarkdownExportSafety.metadata(host.settings.model, fallback: "未命名模型", maxLength: 120)
            currentTitle = "\(providerName) · \(modelName)"
        } else {
            currentTitle = "尚未配置模型"
        }
        let switchItem = NSMenuItem(title: "模型：\(currentTitle)", action: nil, keyEquivalent: "")
        switchItem.image = symbol("cpu")
        switchItem.submenu = MenuCoordinator.modelSwitchMenu(settings: host.settings,
                                                             target: host,
                                                             action: #selector(AppDelegate.switchModel(_:)),
                                                             settingsTarget: host,
                                                             settingsAction: #selector(AppDelegate.openSettingsFromMenu(_:)))
        menu.addItem(switchItem)

        let workModeItem = NSMenuItem(title: "模式：\(host.settings.workModeStatusTitle)", action: nil, keyEquivalent: "")
        workModeItem.image = symbol("slider.horizontal.2.square")
        workModeItem.submenu = workModeMenu(for: host)
        menu.addItem(workModeItem)

        let historyItem = NSMenuItem(title: "历史与会话", action: nil, keyEquivalent: "")
        historyItem.image = symbol("clock.arrow.circlepath")
        historyItem.submenu = historyMenu(for: host)
        menu.addItem(historyItem)

        menu.addItem(.separator())

        let undoWriteBack = menu.addItem(withTitle: host.undoWriteBackMenuTitle(),
                                         action: #selector(AppDelegate.undoLastWriteBackFromMenu(_:)),
                                         keyEquivalent: "")
        undoWriteBack.target = host
        undoWriteBack.image = symbol("arrow.uturn.backward")

        menu.addItem(.separator())

        let settingsItem = menu.addItem(withTitle: "设置…", action: #selector(AppDelegate.openSettingsFromMenu(_:)), keyEquivalent: ",")
        settingsItem.target = host
        settingsItem.image = symbol("gearshape")

        let healthItem = menu.addItem(withTitle: "权限与诊断…", action: #selector(AppDelegate.openPermissionHealthFromMenu(_:)), keyEquivalent: "")
        healthItem.target = host
        healthItem.image = symbol("checkmark.shield")

        let updateItem = menu.addItem(withTitle: "检查更新…", action: #selector(AppDelegate.checkForUpdatesFromMenu(_:)), keyEquivalent: "")
        updateItem.target = host
        updateItem.image = symbol("arrow.down.circle")

        menu.addItem(.separator())

        let quitItem = menu.addItem(withTitle: "退出 SnapAI", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        quitItem.image = symbol("power")

        host.statusItem.menu = menu
    }

    private static func symbol(_ name: String) -> NSImage? {
        let img = NSImage(systemSymbolName: name, accessibilityDescription: nil)
        img?.isTemplate = true
        return img
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
        let open = sub.addItem(withTitle: "浏览全部历史与会话…", action: #selector(AppDelegate.openHistoryWindowFromMenu(_:)), keyEquivalent: "")
        open.target = host
        sub.addItem(.separator())
        if host.settings.history.isEmpty {
            let item = NSMenuItem(title: "暂无记录", action: nil, keyEquivalent: "")
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
        let clear = sub.addItem(withTitle: "清空全部历史", action: #selector(AppDelegate.clearHistory), keyEquivalent: "")
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
