import Foundation
import SnapAILogic

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

    static func urlRun(options: SnapAILogic.AutomationRunOptions) -> AutomationWriteBackPolicy {
        if options.replaceByDefault == true {
            return .disabled(reason: "URL 调用没有可信原选区,不会自动写回。")
        }
        return .disabled(reason: "URL 调用仅打开结果窗。")
    }

    static func capturedSelection(action: AIAction) -> AutomationWriteBackPolicy {
        action.replaceByDefault ? .capturedSelection : .disabled(reason: "动作未开启完成后替换确认。")
    }
}

extension AIAction {
    func applyingAutomationOptions(_ options: SnapAILogic.AutomationRunOptions, settings: AppSettings) -> AIAction {
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
        if let targetLanguage = options.targetLanguage.flatMap(TargetLanguage.init(logic:)) {
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

extension HistoryFilterCriteria {
    init(logic criteria: SnapAILogic.HistoryFilterCriteria) {
        self.init(query: criteria.query,
                  actionFilter: criteria.actionFilter,
                  modelFilter: criteria.modelFilter,
                  tagFilter: criteria.tagFilter,
                  favoriteOnly: criteria.favoriteOnly)
    }
}

extension TargetLanguage {
    init?(logic language: SnapAILogic.TargetLanguage) {
        self.init(rawValue: language.rawValue)
    }
}

extension AIRoutingPreference {
    init?(logic preference: SnapAILogic.AIRoutingPreference) {
        self.init(rawValue: preference.rawValue)
    }
}

extension WorkModePreset {
    init?(logic mode: SnapAILogic.WorkModePreset) {
        self.init(rawValue: mode.rawValue)
    }
}

extension TypewriterSpeed {
    init?(logic speed: SnapAILogic.TypewriterSpeed) {
        self.init(rawValue: speed.rawValue)
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
