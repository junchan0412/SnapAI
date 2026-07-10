import AppKit
import SnapAILogic

@MainActor
extension AppDelegate {
    func commandPaletteItems() -> [CommandPaletteItem] {
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
        if let descriptor = WriteBackCommandFactory.undoDescriptor(
            for: lastWriteBackRecord?.writeBackCommandInput
        ) {
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
        let actionCommandInputs = settings.actions.map { action in
            ActionCommandInput(id: action.id,
                               name: action.name,
                               group: action.group,
                               icon: action.icon,
                               isEnabled: action.isEnabled,
                               shortcutText: action.hotKey?.displayString)
        }
        for descriptor in ActionCommandFactory.descriptors(for: actionCommandInputs,
                                                           usageCounts: settings.actionUsageCounts) {
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
        let modelSwitchProviders = settings.providers.map { provider in
            ModelSwitchProviderInput(id: provider.id,
                                     name: provider.name,
                                     isEnabled: provider.isEnabled,
                                     enabledModelNames: provider.enabledModelNames)
        }
        for descriptor in ModelSwitchCommandFactory.descriptors(providers: modelSwitchProviders,
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
                subtitle: InstallLogCommand.subtitle(for: UpdateChecker.latestInstallLogStatus().installLogCommandStatus),
                systemImage: "doc.text.magnifyingglass",
                keywords: "update install log reveal finder xattr quarantine 更新 安装 日志 显示",
                perform: { [weak self] in self?.revealLatestInstallLog() }
            ),
            CommandPaletteItem(
                id: "copy-install-log-path",
                title: "复制安装日志路径",
                subtitle: InstallLogCommand.subtitle(for: UpdateChecker.latestInstallLogStatus().installLogCommandStatus),
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

    func performWriteBackCommand(_ action: WriteBackCommandAction) {
        switch action {
        case .undoLastWriteBack:
            undoLastWriteBack()
        }
    }

    func appendActionTemplateCommandPaletteItems(to items: inout [CommandPaletteItem]) {
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

    func installActionTemplate(_ template: ActionTemplate) {
        let action = ActionTemplateLibrary.installedAction(from: template,
                                                           existingActions: settings.actions.actionTemplateActions).aiAction
        settings.actions.append(contentsOf: AppSettings.sanitizedImportedActions([action]))
        settings.save()
        registerHotKeys()
        buildMenu()
        installMainMenu()
    }

    func appendDisplayBehaviorCommandPaletteItems(to items: inout [CommandPaletteItem]) {
        let typewriterSpeeds = TypewriterSpeed.allCases.map { speed in
            TypewriterSpeedCommandInput(id: speed.id,
                                        title: speed.rawValue,
                                        isCurrent: settings.typewriterSpeed == speed)
        }
        for descriptor in DisplayBehaviorCommandFactory.descriptors(showDockIcon: settings.showDockIcon,
                                                                    loginItemEnabled: LoginItem.isEnabled,
                                                                    typewriterSpeeds: typewriterSpeeds) {
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

    func performDisplayBehaviorCommand(_ action: DisplayBehaviorCommandAction) {
        switch action {
        case .setDockIcon(let enabled):
            setDockIconFromAutomation(enabled)
        case .setLoginItem(let enabled):
            setLoginItemFromAutomation(enabled)
        case .setTypewriterSpeed(let speedID):
            let speed = TypewriterSpeed.allCases.first { $0.id == speedID }
            setTypewriterSpeedFromAutomation(speed)
        }
    }

    func appendHistoryExportCommandPaletteItems(to items: inout [CommandPaletteItem]) {
        let historyInputs = settings.history.map(\.historyExportCommandInput)
        for descriptor in HistoryExportCommandFactory.descriptors(for: historyInputs) {
            items.append(CommandPaletteItem(
                id: descriptor.id,
                title: descriptor.title,
                subtitle: descriptor.subtitle,
                systemImage: descriptor.systemImage,
                keywords: descriptor.keywords,
                perform: { [weak self] in
                    self?.copyHistoryMarkdown(criteria: descriptor.criteria.historyFilterCriteria)
                }
            ))
        }
    }

    func appendHistoryContextCommandPaletteItems(to items: inout [CommandPaletteItem]) {
        let historyInputs = settings.history.map(\.historyContextCommandInput)
        for descriptor in HistoryContextCommandFactory.descriptors(for: historyInputs) {
            items.append(CommandPaletteItem(
                id: descriptor.id,
                title: descriptor.title,
                subtitle: descriptor.subtitle,
                systemImage: descriptor.systemImage,
                keywords: descriptor.keywords,
                perform: { [weak self] in
                    self?.createHistoryContextProfile(criteria: descriptor.criteria.historyFilterCriteria)
                }
            ))
        }
    }

    func appendRoutingPreferenceCommandPaletteItems(to items: inout [CommandPaletteItem]) {
        let preferences = AIRoutingPreference.allCases.map { preference in
            RoutingPreferenceCommandInput(id: preference.id,
                                          title: preference.rawValue,
                                          detail: preference.description,
                                          isCurrent: preference == settings.routingPreference)
        }
        for descriptor in RoutingContextCommandFactory.routingDescriptors(preferences: preferences) {
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

    func appendContextProfileCommandPaletteItems(to items: inout [CommandPaletteItem]) {
        let profileInputs = settings.contextProfiles.map { profile in
            ContextProfileCommandInput(id: profile.id,
                                       name: profile.name,
                                       content: profile.content,
                                       isEnabled: profile.isEnabled)
        }
        for descriptor in RoutingContextCommandFactory.contextDescriptors(profiles: profileInputs,
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

    func performRoutingContextCommand(_ action: RoutingContextCommandAction) {
        switch action {
        case .setRoutingPreference(let preferenceID):
            guard let preference = AIRoutingPreference.allCases.first(where: { $0.id == preferenceID }) else { return }
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

    func appendSettingsToggleCommandPaletteItems(to items: inout [CommandPaletteItem]) {
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

    func toggleSetting(_ command: SettingsToggleCommand) {
        command.setEnabled(!command.isEnabled(in: settings), in: settings)
        settings.save()
        iCloudSync.shared.scheduleUpload(settings)
        buildMenu()
        installMainMenu()
    }

    func appendWorkModeCommandPaletteItems(to items: inout [CommandPaletteItem]) {
        let currentMode = settings.matchingWorkModePreset
        let modeInputs = WorkModePreset.allCases.map { mode in
            WorkModeCommandInput(id: mode.id,
                                 title: mode.title,
                                 shortTitle: mode.shortTitle,
                                 summary: mode.summary,
                                 systemImage: mode.systemImage,
                                 keywords: mode.keywords,
                                 isCurrent: currentMode == mode)
        }
        for descriptor in WorkModeCommandFactory.descriptors(modes: modeInputs) {
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

    func performWorkModeCommand(_ action: WorkModeCommandAction) {
        switch action {
        case .apply(let modeID):
            guard let mode = WorkModePreset(rawValue: modeID) else { return }
            applyWorkMode(mode)
        }
    }

    func applyWorkMode(_ mode: WorkModePreset) {
        settings.applyWorkMode(mode)
        settings.save()
        iCloudSync.shared.scheduleUpload(settings)
        buildMenu()
        installMainMenu()
    }

    func appendResultCommandPaletteItems(to items: inout [CommandPaletteItem]) {
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

    func appendResultPinCommandPaletteItem(to items: inout [CommandPaletteItem]) {
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

    func performResultCommand(_ action: ResultCommandAction) {
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
}
