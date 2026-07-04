import AppKit

@MainActor
extension AppDelegate {
    func installAutomationURLHandler() {
        NSAppleEventManager.shared().setEventHandler(
            self,
            andSelector: #selector(handleAutomationURL(_:withReplyEvent:)),
            forEventClass: AEEventClass(kInternetEventClass),
            andEventID: AEEventID(kAEGetURL)
        )
    }

    @objc func handleAutomationURL(_ event: NSAppleEventDescriptor,
                                           withReplyEvent replyEvent: NSAppleEventDescriptor) {
        guard let rawURL = event.paramDescriptor(forKeyword: keyDirectObject)?.stringValue,
              let command = AutomationRouter.command(from: rawURL) else {
            return
        }
        runAutomationCommand(command)
    }

    func runAutomationCommand(_ command: AutomationURLCommand) {
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
            previousCaptureMethod = nil
            runQuickInput(text: text,
                          action: action.applyingAutomationOptions(options, settings: settings),
                          autoReplaceEnabled: AutomationWriteBackPolicy.urlRun(options: options).autoReplaceEnabled)
        case let .openQuickInput(text, actionQuery):
            previousApp = currentCaptureTargetApp()
            previousSelectionSnapshot = nil
            previousCaptureMethod = nil
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

    func switchModelFromAutomation(providerQuery: String?, modelQuery: String?) {
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

    func switchContextFromAutomation(profileQuery: String?) {
        guard let selection = AutomationContextSelection.resolve(profileQuery: profileQuery,
                                                                 settings: settings) else {
            showSettings(section: .general)
            return
        }
        settings.activeContextProfileID = selection.profileID
        settings.save()
        iCloudSync.shared.scheduleUpload(settings)
    }

    func clearContextFromAutomation() {
        settings.activeContextProfileID = ""
        settings.save()
        iCloudSync.shared.scheduleUpload(settings)
    }

    func copyContextFromAutomation(profileQuery: String?) {
        guard let profile = contextProfileForCopy(profileQuery: profileQuery) else {
            showSettings(section: .general)
            return
        }
        copyContext(profile)
    }

    func contextProfileForCopy(profileQuery: String?) -> ContextProfile? {
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

    func copyContext(_ profile: ContextProfile) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(
            profile.markdownExport(isActive: profile.id == settings.activeContextProfileID),
            forType: .string
        )
    }

    func copyEffectiveSystemPrompt() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(settings.effectiveSystemPromptMarkdownExport,
                                       forType: .string)
    }

    func copyContextStatus() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(settings.contextStatusMarkdownExport,
                                       forType: .string)
    }

    func clearHistoryFromAutomation() {
        settings.clearHistory()
        buildMenu()
        installMainMenu()
    }

    func copyHistoryMarkdownFromAutomation(criteria: HistoryFilterCriteria) {
        copyHistoryMarkdown(criteria: criteria)
    }

    func createHistoryContextProfileFromAutomation(criteria: HistoryFilterCriteria,
                                                           options: AutomationHistoryContextOptions) {
        createHistoryContextProfile(criteria: criteria,
                                    requiresConfirmation: false,
                                    options: options)
    }

    func copyHistoryMarkdown(criteria: HistoryFilterCriteria) {
        let export = HistoryCollectionExport(entries: filteredHistoryEntries(criteria: criteria),
                                             criteria: criteria)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(export.markdown, forType: .string)
    }

    func createHistoryContextProfile(criteria: HistoryFilterCriteria,
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

    func filteredHistoryEntries(criteria: HistoryFilterCriteria) -> [HistoryEntry] {
        HistorySearch.filteredEntries(criteria: criteria,
                                      memoryEntries: settings.history,
                                      limit: settings.historyLimit,
                                      searchStore: HistoryStore.shared.search)
    }

    func setToggleFromAutomation(commandQuery: String?, enabled: Bool?) {
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

    func setRoutingPreferenceFromAutomation(_ preference: AIRoutingPreference?) {
        guard let preference else {
            showSettings(section: .ai)
            return
        }
        settings.routingPreference = preference
        settings.save()
        iCloudSync.shared.scheduleUpload(settings)
    }

    func setWorkModeFromAutomation(_ mode: WorkModePreset?) {
        guard let mode else {
            showSettings(section: .general)
            return
        }
        applyWorkMode(mode)
    }

    func setDockIconFromAutomation(_ enabled: Bool?) {
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

    func setLoginItemFromAutomation(_ enabled: Bool?) {
        guard let enabled else {
            showSettings(section: .permission)
            return
        }
        if !LoginItem.setEnabled(enabled) {
            showSettings(section: .permission)
        }
    }

    func setTypewriterSpeedFromAutomation(_ speed: TypewriterSpeed?) {
        guard let speed else {
            showSettings(section: .general)
            return
        }
        settings.typewriterSpeed = speed
        settings.save()
        iCloudSync.shared.scheduleUpload(settings)
    }

    func actionForAutomation(query: String?) -> AIAction? {
        AutomationActionSelection.resolve(query: query, actions: settings.enabledActions)
    }

    func settingsSection(for raw: String?) -> SettingsSection {
        AutomationRouter.settingsSection(for: raw,
                                         fallback: windowCoordinator.selectedSettingsSection)
    }
}
