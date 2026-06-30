import Foundation

struct AutomationRunOptions: Equatable {
    var providerQuery: String? = nil
    var modelQuery: String? = nil
    var saveHistory: Bool? = nil
    var targetLanguage: TargetLanguage? = nil
    var replaceByDefault: Bool? = nil

    static let empty = AutomationRunOptions()

    var hasOverrides: Bool {
        providerQuery != nil ||
        modelQuery != nil ||
        saveHistory != nil ||
        targetLanguage != nil ||
        replaceByDefault != nil
    }
}

struct AutomationHistoryContextOptions: Equatable {
    var name: String? = nil
    var maxEntries: Int? = nil
    var maxFieldCharacters: Int? = nil

    static let empty = AutomationHistoryContextOptions()
}

struct AutomationModelSelection: Equatable {
    var providerID: String
    var modelName: String

    static func resolve(providerQuery: String?,
                        modelQuery: String?,
                        settings: AppSettings) -> AutomationModelSelection? {
        let enabledProviders = settings.providers.filter { $0.isEnabled }
        guard let modelQuery = modelQuery?.trimmedNonEmpty else { return nil }
        let explicitProviderQuery = providerQuery?.trimmedNonEmpty
        let provider = AutomationModelSelection.provider(matching: explicitProviderQuery,
                                                         in: enabledProviders)
            ?? (explicitProviderQuery == nil
                ? enabledProviders.first { $0.enabledModelNames.containsAutomationLookup(modelQuery) }
                : nil)
        guard let provider,
              let model = provider.enabledModelNames.first(where: {
                  $0.automationMatches(modelQuery)
              }) else {
            return nil
        }
        return AutomationModelSelection(providerID: provider.id, modelName: model)
    }

    private static func provider(matching providerQuery: String?,
                                 in providers: [AIProvider]) -> AIProvider? {
        guard let providerQuery else { return nil }
        return providers.first {
            $0.id.automationMatches(providerQuery) ||
            $0.name.automationMatches(providerQuery)
        }
    }
}

private struct AutomationModelPathSelection {
    var providerQuery: String?
    var modelQuery: String?
}

struct AutomationContextSelection: Equatable {
    var profileID: String

    static func resolve(profileQuery: String?, settings: AppSettings) -> AutomationContextSelection? {
        guard let profileQuery = profileQuery?.trimmedNonEmpty else { return nil }
        guard let profile = settings.contextProfiles.first(where: {
            $0.isEnabled &&
            !$0.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            ($0.id.automationMatches(profileQuery) ||
             $0.name.automationMatches(profileQuery))
        }) else {
            return nil
        }
        return AutomationContextSelection(profileID: profile.id)
    }
}

enum AutomationActionSelection {
    static func resolve(query: String?, actions: [AIAction]) -> AIAction? {
        guard let query = query?.trimmedNonEmpty else { return nil }
        return actions.first {
            $0.isEnabled &&
            ($0.id.automationMatches(query) ||
             $0.name.automationMatches(query))
        }
    }
}

enum AutomationSettingsSectionSelection {
    static func resolve(_ query: String?, fallback: SettingsSection) -> SettingsSection {
        guard let key = query?.trimmedNonEmpty?.automationLookupKey else { return fallback }
        switch key {
        case "ai", "model", "models", "provider", "providers", "llm", "api", "apikey", "keychain", "ai模型", "供应商", "模型":
            return .ai
        case "actions", "action", "prompt", "prompts", "hotkey", "hotkeys", "shortcut", "shortcuts", "keyboardshortcut", "keyboardshortcuts", "动作", "快捷键", "提示词":
            return .actions
        case "history", "histories", "historyrecords", "record", "records", "log", "logs", "历史", "历史记录":
            return .history
        case "general", "privacy", "context", "contexts", "icloud", "sync", "display", "dock", "typewriter", "redaction", "通用", "隐私", "上下文":
            return .general
        case "permission", "permissions", "permissionscreenrecording", "permissionscreencapture", "permissionaccessibility", "accessibility", "screen", "screenrecording", "screencapture", "launchatlogin", "loginitem", "startup", "权限", "辅助功能", "屏幕录制", "开机启动":
            return .permission
        default:
            return SettingsSection.allCases.first {
                $0.rawValue.automationLookupKey == key
            } ?? fallback
        }
    }
}

enum AutomationRoutingPreferenceSelection {
    static func resolve(_ query: String?) -> AIRoutingPreference? {
        guard let key = query?.trimmedNonEmpty?.automationLookupKey else { return nil }
        switch key {
        case "fast", "fastest", "speed", "speedfirst", "cheap", "cost", "最快", "速度":
            return .fastest
        case "balanced", "balance", "default", "normal", "均衡", "默认":
            return .balanced
        case "quality", "best", "bestquality", "smart", "reasoning", "最佳质量", "质量":
            return .quality
        default:
            return AIRoutingPreference.allCases.first {
                $0.rawValue.automationLookupKey == key
            }
        }
    }
}

enum AutomationWorkModeSelection {
    static func resolve(_ query: String?) -> WorkModePreset? {
        guard let key = query?.trimmedNonEmpty?.automationLookupKey else { return nil }
        switch key {
        case "standard", "default", "normal", "balanced", "daily", "常规", "标准", "默认", "日常":
            return .standard
        case "privacy", "private", "safe", "secure", "safety", "隐私", "安全":
            return .privacy
        case "speed", "fast", "fastest", "quick", "quickly", "performance", "极速", "快速", "最快", "性能":
            return .speed
        case "quality", "best", "bestquality", "smart", "reasoning", "质量", "最佳", "最佳质量", "推理":
            return .quality
        default:
            return WorkModePreset.allCases.first {
                $0.rawValue.automationLookupKey == key ||
                $0.shortTitle.automationLookupKey == key ||
                $0.title.automationLookupKey == key
            }
        }
    }
}

enum AutomationTypewriterSpeedSelection {
    static func resolve(_ query: String?) -> TypewriterSpeed? {
        guard let key = query?.trimmedNonEmpty?.automationLookupKey else { return nil }
        switch key {
        case "off", "none", "disable", "disabled", "0", "关闭", "关":
            return .off
        case "slow", "slower", "1", "慢":
            return .slow
        case "normal", "standard", "standardspeed", "default", "2", "标准", "默认":
            return .normal
        case "fast", "faster", "3", "快":
            return .fast
        default:
            return TypewriterSpeed.allCases.first {
                $0.rawValue.automationLookupKey == key
            }
        }
    }
}

enum AutomationWriteBackPolicy: Equatable {
    case disabled(reason: String)
    case capturedSelection

    var autoReplaceEnabled: Bool {
        switch self {
        case .disabled:
            return false
        case .capturedSelection:
            return true
        }
    }

    static func urlRun(options: AutomationRunOptions) -> AutomationWriteBackPolicy {
        if options.replaceByDefault == true {
            return .disabled(reason: "URL 调用没有可信原选区,不会自动写回。")
        }
        return .disabled(reason: "URL 调用仅打开结果窗。")
    }

    static func capturedSelection(action: AIAction) -> AutomationWriteBackPolicy {
        action.replaceByDefault ? .capturedSelection : .disabled(reason: "动作未开启完成后替换确认。")
    }
}

enum AutomationURLCommand: Equatable {
    case run(actionQuery: String?, text: String, options: AutomationRunOptions = .empty)
    case openQuickInput(text: String?, actionQuery: String? = nil)
    case openSettings(section: String?)
    case openHistory
    case clearHistory
    case copyHistoryMarkdown(criteria: HistoryFilterCriteria = HistoryFilterCriteria())
    case createHistoryContext(criteria: HistoryFilterCriteria = HistoryFilterCriteria(),
                              options: AutomationHistoryContextOptions = .empty)
    case openCommandPalette
    case openPermissionHealth
    case copyBriefPermissionDiagnostics
    case copyPermissionDiagnostics
    case copyPermissionRecoverySuggestions
    case revealInstallLog
    case copyInstallLogPath
    case switchModel(providerQuery: String?, modelQuery: String?)
    case switchContext(profileQuery: String?)
    case copyContext(profileQuery: String?)
    case copyEffectiveSystemPrompt
    case copyContextStatus
    case clearContext
    case setToggle(commandQuery: String?, enabled: Bool?)
    case setRoutingPreference(AIRoutingPreference?)
    case setWorkMode(WorkModePreset?)
    case setDockIcon(Bool?)
    case setLoginItem(Bool?)
    case setTypewriterSpeed(TypewriterSpeed?)
    case checkUpdates

    static func parse(_ url: URL) -> AutomationURLCommand? {
        guard url.scheme?.lowercased() == "snapai" else { return nil }
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }

        let command = commandName(from: components)
        let queryItems = components.queryItems ?? []
        let text = firstQueryValue(named: ["text", "q", "prompt"], in: queryItems)
        let actionQuery = firstNonEmptyQueryValue(named: ["action", "actionID", "id", "name"], in: queryItems)
        let pathActionQuery = pathArgument(in: components)
        let section = firstNonEmptyQueryValue(named: ["section", "tab"], in: queryItems)
        let options = AutomationRunOptions(
            providerQuery: firstNonEmptyQueryValue(named: ["provider", "providerID"], in: queryItems),
            modelQuery: firstNonEmptyQueryValue(named: ["model", "modelOverride"], in: queryItems),
            saveHistory: firstBoolValue(named: ["saveHistory", "history"], in: queryItems),
            targetLanguage: firstTargetLanguageValue(named: ["language", "lang", "targetLanguage"], in: queryItems),
            replaceByDefault: firstBoolValue(named: ["replace", "replaceByDefault", "writeBack"], in: queryItems)
        )

        switch command {
        case "", "run", "ask", "translate", "polish", "summarize", "explain":
            let resolvedActionQuery = actionQuery ?? pathActionQuery ?? defaultActionQuery(for: command)
            guard let text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return .openQuickInput(text: nil, actionQuery: resolvedActionQuery)
            }
            return .run(actionQuery: resolvedActionQuery,
                        text: text,
                        options: options)
        case "quick", "quick-input", "input", "prompt":
            if command == "prompt",
               firstBoolValue(named: ["copy", "export", "markdown"], in: queryItems) == true {
                return .copyEffectiveSystemPrompt
            }
            return .openQuickInput(text: text, actionQuery: actionQuery ?? pathActionQuery)
        case "settings", "preferences":
            return .openSettings(section: section ?? pathValue(in: components, labels: ["section", "tab"]))
        case "history":
            let pathCommand = pathArgument(in: components)?.automationLookupKey
            let isClearPathCommand = pathCommand.map { ["clear", "deleteall", "reset"].contains($0) } ?? false
            let isExportPathCommand = pathCommand.map { ["copy", "export", "markdown"].contains($0) } ?? false
            let isContextPathCommand = pathCommand.map {
                ["context", "contextprofile", "profile", "memory", "createcontext", "createcontextprofile"].contains($0)
            } ?? false
            let clearFlag = firstBoolValue(named: ["clear", "deleteAll", "reset"], in: queryItems)
            let exportFlag = firstBoolValue(named: ["copy", "export", "markdown"], in: queryItems)
            let contextFlag = firstBoolValue(named: ["context", "contextProfile", "createContext", "memory"], in: queryItems)
            if clearFlag == true ||
                (isClearPathCommand && clearFlag != false) {
                guard !hasHistoryFilterParameters(in: queryItems) else { return .openHistory }
                return .clearHistory
            }
            if exportFlag == true ||
                (isExportPathCommand && exportFlag != false) {
                return .copyHistoryMarkdown(criteria: historyFilterCriteria(from: queryItems))
            }
            if contextFlag == true ||
                (isContextPathCommand && contextFlag != false) {
                return .createHistoryContext(criteria: historyFilterCriteria(from: queryItems),
                                             options: historyContextOptions(from: queryItems))
            }
            return .openHistory
        case "palette", "command-palette", "command", "commands":
            return .openCommandPalette
        case "health", "permission-health":
            return permissionDiagnosticsCommand(from: components, queryItems: queryItems)
        case "diagnostics", "diagnostic":
            return permissionDiagnosticsCommand(from: components, queryItems: queryItems)
        case "install-log", "installlog", "update-log":
            let pathCommand = pathArgument(in: components)?.automationLookupKey
            let isCopyPathCommand = pathCommand.map { ["copy", "copypath", "path"].contains($0) } ?? false
            let copyFlag = firstBoolValue(named: ["copy", "copyPath"], in: queryItems)
            if copyFlag == true ||
                (isCopyPathCommand && copyFlag != false) {
                return .copyInstallLogPath
            }
            return .revealInstallLog
        case "model", "models", "switch-model":
            let pathSelection = modelPathSelection(in: components)
            return .switchModel(providerQuery: firstNonEmptyQueryValue(named: ["provider", "providerID"], in: queryItems)
                                ?? pathSelection.providerQuery,
                                modelQuery: firstNonEmptyQueryValue(named: ["model", "name"], in: queryItems)
                                ?? pathSelection.modelQuery)
        case "context", "contexts", "context-profile":
            let pathSegments = pathArgumentSegments(in: components)
            let firstPathKey = pathSegments.first?.automationLookupKey
            let clearFlag = firstBoolValue(named: ["clear", "off", "disable"], in: queryItems)
            if clearFlag == true {
                return .clearContext
            }
            let queryProfile = firstNonEmptyQueryValue(named: ["context", "profile", "id", "name"], in: queryItems)
            let isCopyPathCommand = firstPathKey.map { ["copy", "export", "markdown"].contains($0) } ?? false
            let isEffectivePromptPathCommand = firstPathKey.map { ["effective", "effectiveprompt", "systemprompt", "prompt"].contains($0) } ?? false
            let isStatusPathCommand = firstPathKey.map { ["status", "diagnostics", "diagnostic", "health"].contains($0) } ?? false
            let statusFlag = firstBoolValue(named: ["status", "diagnostics", "diagnostic", "health"], in: queryItems)
            let effectivePromptFlag = firstBoolValue(named: ["effective", "effectivePrompt", "systemPrompt"], in: queryItems)
            let copyFlag = firstBoolValue(named: ["copy", "export", "markdown"], in: queryItems)
            let copyAllowed = copyFlag != false
            if (copyAllowed && statusFlag == true) ||
                (copyAllowed && isStatusPathCommand && statusFlag != false) {
                return .copyContextStatus
            }
            if (copyAllowed && effectivePromptFlag == true) ||
                (copyAllowed && isEffectivePromptPathCommand && effectivePromptFlag != false) {
                return .copyEffectiveSystemPrompt
            }
            if copyFlag == true ||
                (isCopyPathCommand && copyFlag != false) {
                let pathProfile: String?
                if isCopyPathCommand {
                    pathProfile = pathSegments.dropFirst().joined(separator: "/").trimmedNonEmpty
                } else {
                    pathProfile = pathArgument(in: components)
                }
                return .copyContext(profileQuery: queryProfile ?? pathProfile)
            }
            if let queryProfile {
                return .switchContext(profileQuery: queryProfile)
            }
            let pathProfile = pathArgument(in: components)
            if pathProfile.map({ ["clear", "off", "disable"].contains($0.automationLookupKey) }) == true {
                return clearFlag == false ? .switchContext(profileQuery: pathProfile) : .clearContext
            }
            return .switchContext(profileQuery: pathProfile)
        case "system-prompt", "effective-prompt":
            if firstBoolValue(named: ["copy", "export", "markdown"], in: queryItems) == false {
                return .openSettings(section: "general")
            }
            return .copyEffectiveSystemPrompt
        case "toggle", "toggles", "setting":
            let pathSegments = pathArgumentSegments(in: components)
            return .setToggle(commandQuery: firstNonEmptyQueryValue(named: ["name", "toggle", "setting", "id"], in: queryItems)
                              ?? pathSegments.first,
                              enabled: firstBoolValue(named: ["enabled", "on", "value"], in: queryItems)
                              ?? pathSegments.dropFirst().first.flatMap(parseBoolValue))
        case "routing", "route-preference", "routing-preference":
            return .setRoutingPreference(
                AutomationRoutingPreferenceSelection.resolve(
                    firstNonEmptyQueryValue(named: ["preference", "mode", "value"], in: queryItems)
                    ?? pathValue(in: components, labels: ["preference", "mode", "value", "routing"])
                )
            )
        case "work-mode", "workmode", "workflow-mode", "workflow", "mode":
            return .setWorkMode(
                AutomationWorkModeSelection.resolve(
                    firstNonEmptyQueryValue(named: ["mode", "preset", "value", "workMode"], in: queryItems)
                    ?? pathValue(in: components, labels: ["mode", "preset", "value", "workmode"])
                )
            )
        case "dock", "dock-icon", "show-dock-icon":
            return .setDockIcon(firstBoolValue(named: ["enabled", "show", "on", "value"], in: queryItems)
                                ?? pathArgument(in: components).flatMap(parseBoolValue))
        case "login-item", "loginitem", "launch-at-login", "startup":
            return .setLoginItem(firstBoolValue(named: ["enabled", "on", "value"], in: queryItems)
                                 ?? pathArgument(in: components).flatMap(parseBoolValue))
        case "typewriter", "typewriter-speed", "animation":
            return .setTypewriterSpeed(
                AutomationTypewriterSpeedSelection.resolve(
                    firstNonEmptyQueryValue(named: ["speed", "mode", "value"], in: queryItems)
                    ?? pathValue(in: components, labels: ["speed", "mode", "value", "typewriter"])
                )
            )
        case "update", "updates", "check-update", "check-updates":
            return .checkUpdates
        default:
            return nil
        }
    }

    private static func commandName(from components: URLComponents) -> String {
        if let host = components.host, !host.isEmpty {
            return normalizedCommandName(host)
        }
        return firstPathComponent(in: components).map(normalizedCommandName) ?? ""
    }

    private static func permissionDiagnosticsCommand(from components: URLComponents,
                                                     queryItems: [URLQueryItem]) -> AutomationURLCommand {
        let pathCommand = pathArgument(in: components)?.automationLookupKey
        let isCopyPathCommand = pathCommand.map { ["copy", "copydiagnostics"].contains($0) } ?? false
        let isSummaryPathCommand = pathCommand.map {
            ["summary", "brief", "copysummary", "copybrief", "summarydiagnostics", "briefdiagnostics"].contains($0)
        } ?? false
        let isRecoveryPathCommand = pathCommand.map {
            ["recovery", "recoverysuggestions", "suggestion", "suggestions", "fix", "fixes", "copyrecovery", "copysuggestions"].contains($0)
        } ?? false
        let copyFlag = firstBoolValue(named: ["copy", "copyDiagnostics"], in: queryItems)
        let summaryFlag = firstBoolValue(named: ["summary", "brief", "copySummary", "copyBrief"], in: queryItems)
        let recoveryFlag = firstBoolValue(named: ["recovery", "suggestions", "fix", "copyRecovery", "copySuggestions"], in: queryItems)
        let copyAllowed = copyFlag != false
        if (copyAllowed && recoveryFlag == true) ||
            (copyAllowed && isRecoveryPathCommand && recoveryFlag != false) {
            return .copyPermissionRecoverySuggestions
        }
        if (copyAllowed && summaryFlag == true) ||
            (copyAllowed && isSummaryPathCommand && summaryFlag != false) {
            return .copyBriefPermissionDiagnostics
        }
        if copyFlag == true ||
            (isCopyPathCommand && copyFlag != false) {
            return .copyPermissionDiagnostics
        }
        return .openPermissionHealth
    }

    private static func normalizedCommandName(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "_", with: "-")
            .replacingOccurrences(of: " ", with: "-")
    }

    private static func firstPathComponent(in components: URLComponents) -> String? {
        components.path
            .split(separator: "/")
            .map(String.init)
            .first
    }

    private static func pathArgument(in components: URLComponents) -> String? {
        let decodedSegments = pathArgumentSegments(in: components)
        let decoded = decodedSegments.joined(separator: "/")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return decoded.isEmpty ? nil : decoded
    }

    private static func pathValue(in components: URLComponents, labels: Set<String>) -> String? {
        let segments = pathArgumentSegments(in: components)
        guard let first = segments.first else { return nil }
        if segments.count >= 2, labels.contains(first.automationLookupKey) {
            return segments.dropFirst().joined(separator: "/")
        }
        return pathArgument(in: components)
    }

    private static func modelPathSelection(in components: URLComponents) -> AutomationModelPathSelection {
        let segments = pathArgumentSegments(in: components)
        guard !segments.isEmpty else {
            return AutomationModelPathSelection(providerQuery: nil, modelQuery: nil)
        }
        let firstKey = segments[0].automationLookupKey
        if ["provider", "providerid"].contains(firstKey), segments.count >= 4 {
            let modelLabelIndex = segments[2].automationLookupKey
            if ["model", "modeloverride", "name"].contains(modelLabelIndex) {
                return AutomationModelPathSelection(providerQuery: segments[1],
                                                    modelQuery: segments.dropFirst(3).joined(separator: "/"))
            }
        }
        if ["model", "modeloverride", "name"].contains(firstKey), segments.count >= 2 {
            return AutomationModelPathSelection(providerQuery: nil,
                                                modelQuery: segments.dropFirst().joined(separator: "/"))
        }
        if segments.count >= 2 {
            return AutomationModelPathSelection(providerQuery: segments[0],
                                                modelQuery: segments.dropFirst().joined(separator: "/"))
        }
        return AutomationModelPathSelection(providerQuery: nil, modelQuery: segments[0])
    }

    private static func pathArgumentSegments(in components: URLComponents) -> [String] {
        let rawSegments = components.percentEncodedPath
            .split(separator: "/", omittingEmptySubsequences: true)
            .map(String.init)
        guard !rawSegments.isEmpty else { return [] }
        let argumentSegments: ArraySlice<String>
        if let host = components.host, !host.isEmpty {
            argumentSegments = rawSegments[...]
        } else {
            argumentSegments = rawSegments.dropFirst()
        }
        return argumentSegments.compactMap { segment in
            let decoded = (segment.removingPercentEncoding ?? segment)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return decoded.isEmpty ? nil : decoded
        }
    }

    private static func firstQueryValue(named names: [String], in items: [URLQueryItem]) -> String? {
        firstQueryItem(named: names, in: items)?.value
    }

    private static func firstQueryItem(named names: [String], in items: [URLQueryItem]) -> URLQueryItem? {
        let normalizedNames = Set(names.map(normalizedQueryParameterName))
        return items.first {
            normalizedNames.contains(normalizedQueryParameterName($0.name))
        }
    }

    private static func normalizedQueryParameterName(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .filter { $0 != "_" && $0 != "-" && !$0.isWhitespace }
    }

    private static func firstNonEmptyQueryValue(named names: [String], in items: [URLQueryItem]) -> String? {
        guard let value = firstQueryValue(named: names, in: items)?
            .trimmingCharacters(in: .whitespacesAndNewlines) else {
            return nil
        }
        return value.isEmpty ? nil : value
    }

    private static func firstBoolValue(named names: [String], in items: [URLQueryItem]) -> Bool? {
        let normalizedNames = Set(names.map(normalizedQueryParameterName))
        var hasTrueValue = false
        for item in items where normalizedNames.contains(normalizedQueryParameterName(item.name)) {
            switch parseBoolValue(item.value) {
            case .some(false):
                return false
            case .some(true):
                hasTrueValue = true
            case nil:
                continue
            }
        }
        return hasTrueValue ? true : nil
    }

    private static func parseBoolValue(_ rawValue: String?) -> Bool? {
        guard let raw = rawValue?
            .trimmingCharacters(in: .whitespacesAndNewlines) else {
            return true
        }
        if raw.isEmpty { return true }
        switch raw.automationLookupKey {
        case "1", "true", "t", "yes", "y", "on", "enable", "enabled", "show", "visible", "start", "startup", "开启", "启用", "是", "真":
            return true
        case "0", "false", "f", "no", "n", "off", "disable", "disabled", "hide", "hidden", "stop", "关闭", "禁用", "否", "假":
            return false
        default:
            return nil
        }
    }

    private static func firstTargetLanguageValue(named names: [String], in items: [URLQueryItem]) -> TargetLanguage? {
        guard let raw = firstQueryValue(named: names, in: items)?
            .trimmingCharacters(in: .whitespacesAndNewlines) else {
            return nil
        }
        let key = raw.automationLookupKey
        switch key {
        case "auto", "automatic", "autodetect", "自动", "自动(中英互译)":
            return .auto
        case "zh", "zhcn", "zhhans", "chinese", "chineselanguage", "simplifiedchinese", "simplifiedchineselanguage", "cn", "中文", "简体中文":
            return .chinese
        case "en", "eng", "english", "englishlanguage", "英语", "英文":
            return .english
        case "ja", "jp", "japanese", "japaneselanguage", "日本語", "日语", "日文":
            return .japanese
        case "ko", "kr", "korean", "koreanlanguage", "한국어", "韩语", "韩文":
            return .korean
        case "fr", "fra", "french", "frenchlanguage", "français", "法语", "法文":
            return .french
        case "de", "deu", "german", "germanlanguage", "deutsch", "德语", "德文":
            return .german
        case "es", "spa", "spanish", "spanishlanguage", "español", "西班牙语", "西文":
            return .spanish
        default:
            return TargetLanguage.allCases.first { $0.rawValue.automationLookupKey == key }
        }
    }

    private static func historyFilterCriteria(from items: [URLQueryItem]) -> HistoryFilterCriteria {
        HistoryFilterCriteria(
            query: firstNonEmptyQueryValue(named: ["query", "q", "search", "keyword"], in: items) ?? "",
            actionFilter: firstNonEmptyQueryValue(named: ["action", "actionName"], in: items) ?? HistoryFilterCriteria.allActions,
            modelFilter: firstNonEmptyQueryValue(named: ["model"], in: items) ?? HistoryFilterCriteria.allModels,
            tagFilter: firstNonEmptyQueryValue(named: ["tag", "tags"], in: items) ?? HistoryFilterCriteria.allTags,
            favoriteOnly: firstBoolValue(named: ["favorite", "favorites", "starred"], in: items) == true
        )
    }

    private static func hasHistoryFilterParameters(in items: [URLQueryItem]) -> Bool {
        firstQueryItem(named: [
            "query",
            "q",
            "search",
            "keyword",
            "action",
            "actionName",
            "model",
            "tag",
            "tags",
            "favorite",
            "favorites",
            "starred"
        ], in: items) != nil
    }

    private static func historyContextOptions(from items: [URLQueryItem]) -> AutomationHistoryContextOptions {
        AutomationHistoryContextOptions(
            name: firstNonEmptyQueryValue(named: ["name", "contextName", "profileName", "contextProfileName"], in: items),
            maxEntries: firstIntValue(named: ["limit", "maxEntries", "entries", "entryLimit"], in: items),
            maxFieldCharacters: firstIntValue(named: ["maxChars", "maxCharacters", "maxFieldCharacters", "maxFieldChars", "fieldLimit"], in: items)
        )
    }

    private static func firstIntValue(named names: [String], in items: [URLQueryItem]) -> Int? {
        guard let rawValue = firstNonEmptyQueryValue(named: names, in: items),
              let value = Int(rawValue),
              value > 0 else {
            return nil
        }
        return value
    }

    private static func defaultActionQuery(for command: String) -> String? {
        switch command {
        case "ask":
            return "提问"
        case "translate":
            return "翻译"
        case "polish":
            return "润色"
        case "summarize":
            return "总结"
        case "explain":
            return "解释代码"
        default:
            return nil
        }
    }
}

extension AIAction {
    func applyingAutomationOptions(_ options: AutomationRunOptions, settings: AppSettings) -> AIAction {
        guard options.hasOverrides else { return self }
        var action = self
        let enabledProviders = settings.providers.filter { $0.isEnabled }
        let explicitProviderQuery = options.providerQuery?.trimmedNonEmpty
        let provider = AIAction.automationProvider(matching: explicitProviderQuery,
                                                   in: enabledProviders)
            ?? (explicitProviderQuery == nil
                ? AIAction.automationProvider(forModel: options.modelQuery, in: enabledProviders)
                : nil)
        if let provider {
            action.providerID = provider.id
        }
        if let model = AIAction.automationModel(matching: options.modelQuery, in: provider) {
            action.modelOverride = model
        }
        if let saveHistory = options.saveHistory {
            action.saveHistory = saveHistory
        }
        if let targetLanguage = options.targetLanguage {
            action.isTranslation = true
            action.targetLanguage = targetLanguage
        }
        if let replaceByDefault = options.replaceByDefault {
            action.replaceByDefault = replaceByDefault
        }
        return action
    }

    private static func automationProvider(matching providerQuery: String?,
                                           in providers: [AIProvider]) -> AIProvider? {
        guard let providerQuery else { return nil }
        return providers.first {
            $0.id.automationMatches(providerQuery) ||
            $0.name.automationMatches(providerQuery)
        }
    }

    private static func automationProvider(forModel modelQuery: String?,
                                           in providers: [AIProvider]) -> AIProvider? {
        guard let modelQuery = modelQuery?.trimmedNonEmpty else { return nil }
        return providers.first { $0.enabledModelNames.containsAutomationLookup(modelQuery) }
    }

    private static func automationModel(matching modelQuery: String?, in provider: AIProvider?) -> String? {
        guard let provider, let modelQuery = modelQuery?.trimmedNonEmpty else { return nil }
        return provider.enabledModelNames.first {
            $0.automationMatches(modelQuery)
        }
    }
}

private extension Array where Element == String {
    func containsAutomationLookup(_ query: String?) -> Bool {
        guard let query = query?.trimmedNonEmpty else { return false }
        return contains { $0.automationMatches(query) }
    }
}

private extension String {
    var trimmedNonEmpty: String? {
        let value = trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    func automationMatches(_ query: String) -> Bool {
        automationLookupKey == query.automationLookupKey
    }

    var automationLookupKey: String {
        lowercased().filter {
            !$0.isWhitespace &&
            $0 != "-" &&
            $0 != "_" &&
            $0 != "/" &&
            $0 != "."
        }
    }
}
