import Foundation

extension AppSettings {
    func exportConfigurationData() -> Data? {
        guard let data = try? JSONEncoder().encode(self),
              let exportSettings = try? JSONDecoder().decode(AppSettings.self, from: data) else {
            return nil
        }
        exportSettings.history = []
        exportSettings.actionUsageCounts = [:]
        exportSettings.panelWidth = Self.defaultPanelWidth
        exportSettings.panelHeight = Self.defaultPanelHeight
        exportSettings.iCloudSyncEnabled = false
        exportSettings.iCloudRevision = 0
        exportSettings.iCloudUpdatedAt = nil
        exportSettings.iCloudLastSyncAt = nil
        exportSettings.iCloudLastSyncStatus = "未同步"
        exportSettings.iCloudLastRemoteDeviceID = ""
        exportSettings.iCloudHasLocalChanges = false
        exportSettings.onboardingDone = true
        return try? JSONEncoder().encode(exportSettings)
    }

    static func providersForImportedConfiguration(_ providers: [AIProvider],
                                                  keyResolver: (String) -> String = { LocalSecretStore.apiKey(for: $0) }) -> [AIProvider] {
        var seenProviderIDs = Set<String>()
        return providers.prefix(importedProviderLimit).map { provider in
            let originalID = provider.id.trimmingCharacters(in: .whitespacesAndNewlines)
            var copy = provider
            copy.id = uniqueImportedID(provider.id, seenIDs: &seenProviderIDs)
            copy.name = limitedImportedString(provider.name.trimmingCharacters(in: .whitespacesAndNewlines),
                                              maxLength: importedProviderNameLimit,
                                              fallback: "新供应商")
            copy.baseURL = limitedImportedString(provider.baseURL.trimmingCharacters(in: .whitespacesAndNewlines),
                                                 maxLength: importedProviderBaseURLLimit,
                                                 fallback: "")
            copy.apiKey = keyResolver(originalID.isEmpty ? copy.id : originalID)
            copy.models = sanitizedImportedModels(provider.models)
            copy.temperature = sanitizedImportedProviderTemperature(provider.temperature)
            copy.maxTokens = sanitizedImportedMaxTokens(provider.maxTokens)
            copy.requestTimeout = sanitizedImportedRequestTimeout(provider.requestTimeout)
            return copy
        }
    }

    static func importedProviderConfiguration(_ providers: [AIProvider],
                                              activeProviderID: String,
                                              activeModel: String,
                                              keyResolver: (String) -> String = { LocalSecretStore.apiKey(for: $0) })
    -> (providers: [AIProvider], activeProviderID: String, activeModel: String) {
        let sanitizedProviders = providersForImportedConfiguration(providers, keyResolver: keyResolver)
        let sanitizedActiveModel = sanitizedActiveModelName(activeModel)
        let sanitizedActiveProviderID = providerIDAfterProviderSanitization(
            originalProviders: providers,
            sanitizedProviders: sanitizedProviders,
            providerID: activeProviderID,
            modelName: sanitizedActiveModel
        )
        return (sanitizedProviders, sanitizedActiveProviderID, sanitizedActiveModel)
    }

    static func sanitizedStoredProviders(_ providers: [AIProvider]) -> [AIProvider] {
        var seenProviderIDs = Set<String>()
        return providers.prefix(importedProviderLimit).map { provider in
            var copy = provider
            let trimmedID = provider.id.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmedID.isEmpty || seenProviderIDs.contains(provider.id) {
                copy.id = uniqueImportedID(trimmedID, seenIDs: &seenProviderIDs)
            } else {
                seenProviderIDs.insert(provider.id)
            }
            copy.name = limitedImportedString(provider.name.trimmingCharacters(in: .whitespacesAndNewlines),
                                              maxLength: importedProviderNameLimit,
                                              fallback: "新供应商")
            copy.baseURL = limitedImportedString(provider.baseURL.trimmingCharacters(in: .whitespacesAndNewlines),
                                                 maxLength: importedProviderBaseURLLimit,
                                                 fallback: "")
            copy.models = sanitizedImportedModels(provider.models)
            copy.temperature = sanitizedImportedProviderTemperature(provider.temperature)
            copy.maxTokens = sanitizedImportedMaxTokens(provider.maxTokens)
            copy.requestTimeout = sanitizedImportedRequestTimeout(provider.requestTimeout)
            return copy
        }
    }

    func normalizeImportedConfiguration() {
        let originalProviders = providers
        let providerConfig = Self.importedProviderConfiguration(providers,
                                                                activeProviderID: activeProviderID,
                                                                activeModel: activeModel)
        providers = providerConfig.providers
        activeProviderID = providerConfig.activeProviderID
        activeModel = providerConfig.activeModel
        temperature = Self.clampedTemperature(temperature)
        actions = Self.sanitizedImportedActions(actions,
                                                originalProviders: originalProviders,
                                                sanitizedProviders: providers)
        askPrompt = Self.sanitizedPrompt(askPrompt,
                                         fallback: Self.defaultAskPrompt)
        translatePrompt = Self.sanitizedPrompt(translatePrompt,
                                               fallback: Self.defaultTranslatePrompt,
                                               migrateOldTranslateDefault: true)
        systemPrompt = Self.sanitizedPrompt(systemPrompt,
                                            fallback: Self.defaultSystemPrompt,
                                            allowEmpty: true,
                                            maxLength: Self.importedSystemPromptLimit)
        historyLimit = Self.clampedHistoryLimit(historyLimit)
        savedHistoryFilters = Self.sanitizedStoredSavedHistoryFilters(savedHistoryFilters)
        redactionRules = Self.sanitizedImportedRedactionRules(redactionRules)
        let context = Self.sanitizedImportedContextProfiles(contextProfiles,
                                                            activeID: activeContextProfileID)
        contextProfiles = context.profiles
        activeContextProfileID = context.activeID
        normalizeActive()
    }

    static func clampedTemperature(_ value: Double) -> Double {
        guard value.isFinite else { return 0.3 }
        return min(max(value, 0), 1)
    }

    static func clampedHistoryLimit(_ value: Int) -> Int {
        min(max(value, importedHistoryLimitRange.lowerBound), importedHistoryLimitRange.upperBound)
    }

    static func clampedPanelWidth(_ value: Double) -> Double {
        clampedPanelDimension(value,
                              fallback: defaultPanelWidth,
                              range: importedPanelWidthRange)
    }

    static func clampedPanelHeight(_ value: Double) -> Double {
        clampedPanelDimension(value,
                              fallback: defaultPanelHeight,
                              range: importedPanelHeightRange)
    }

    private static func clampedPanelDimension(_ value: Double,
                                              fallback: Double,
                                              range: ClosedRange<Double>) -> Double {
        guard value.isFinite else { return fallback }
        return min(max(value, range.lowerBound), range.upperBound)
    }

    static func sanitizedImportedModels(_ models: [AIModelEntry]) -> [AIModelEntry] {
        var seenNames = Set<String>()
        return models.prefix(importedModelLimit).compactMap { model in
            let name = limitedImportedString(model.name.trimmingCharacters(in: .whitespacesAndNewlines),
                                             maxLength: importedModelNameLimit,
                                             fallback: "")
            guard !name.isEmpty,
                  seenNames.insert(name).inserted else { return nil }
            return AIModelEntry(name: name, enabled: model.enabled)
        }
    }

    static func sanitizedImportedActions(_ actions: [AIAction]) -> [AIAction] {
        guard !actions.isEmpty else { return AIAction.defaults() }
        var seenIDs = Set<String>()
        let cleaned = actions.prefix(importedActionLimit).map { action in
            var copy = action
            copy.id = uniqueImportedID(action.id, seenIDs: &seenIDs)
            copy.name = limitedImportedString(action.name.trimmingCharacters(in: .whitespacesAndNewlines),
                                              maxLength: AIAction.maxNameLength,
                                              fallback: "新动作")
            copy.icon = limitedImportedString(action.icon.trimmingCharacters(in: .whitespacesAndNewlines),
                                              maxLength: AIAction.maxIconLength,
                                              fallback: "wand.and.stars")
            copy.group = limitedImportedString(action.group.trimmingCharacters(in: .whitespacesAndNewlines),
                                               maxLength: AIAction.maxGroupLength,
                                               fallback: "")
            copy.prompt = limitedImportedString(action.prompt.trimmingCharacters(in: .whitespacesAndNewlines),
                                                maxLength: AIAction.maxPromptLength,
                                                fallback: "{{text}}")
            copy.thinkingBudget = AIAction.sanitizedThinkingBudget(action.thinkingBudget)
            copy.providerID = sanitizedOptionalImportedString(action.providerID)
            copy.modelOverride = sanitizedActionModelOverride(action.modelOverride)
            return copy
        }
        return cleaned.isEmpty ? AIAction.defaults() : cleaned
    }

    static func sanitizedImportedActions(_ actions: [AIAction],
                                         originalProviders: [AIProvider],
                                         sanitizedProviders: [AIProvider]) -> [AIAction] {
        sanitizedImportedActions(actions).map { action in
            var copy = action
            if let providerID = action.providerID {
                copy.providerID = providerIDAfterProviderSanitization(originalProviders: originalProviders,
                                                                      sanitizedProviders: sanitizedProviders,
                                                                      providerID: providerID,
                                                                      modelName: action.modelOverride)
                if let override = copy.modelOverride,
                   let mappedProvider = sanitizedProviders.first(where: { $0.id == copy.providerID }),
                   !mappedProvider.enabledModelNames.contains(override) {
                    copy.modelOverride = nil
                }
            }
            return copy
        }
    }

    static func sanitizedStoredHistory(_ entries: [HistoryEntry], limit: Int) -> [HistoryEntry] {
        let cappedLimit = clampedHistoryLimit(limit)
        guard cappedLimit > 0 else { return [] }
        var seenIDs = Set<String>()
        return entries.prefix(cappedLimit).map { entry in
            var copy = entry
            copy.id = uniqueImportedID(entry.id, seenIDs: &seenIDs)
            copy.actionName = limitedImportedString(entry.actionName.trimmingCharacters(in: .whitespacesAndNewlines),
                                                    maxLength: AIAction.maxNameLength,
                                                    fallback: "未命名动作")
            copy.provider = limitedImportedString(entry.provider.trimmingCharacters(in: .whitespacesAndNewlines),
                                                  maxLength: importedProviderNameLimit,
                                                  fallback: "")
            copy.model = limitedImportedString(entry.model.trimmingCharacters(in: .whitespacesAndNewlines),
                                               maxLength: importedModelNameLimit,
                                               fallback: "")
            let sourcePayload = limitedHistoryText(entry.source,
                                                   maxLength: historySourceCharacterLimit)
            let outputPayload = limitedHistoryText(entry.output,
                                                   maxLength: historyOutputCharacterLimit)
            copy.source = sourcePayload.text
            copy.output = outputPayload.text
            var appendedTags: [String] = []
            if sourcePayload.wasTruncated || entry.displayTags.contains(PrivacyHistoryTag.sourceTruncated) {
                appendedTags.append(PrivacyHistoryTag.sourceTruncated)
            }
            if outputPayload.wasTruncated || entry.displayTags.contains(PrivacyHistoryTag.outputTruncated) {
                appendedTags.append(PrivacyHistoryTag.outputTruncated)
            }
            copy.tags = historyTags(entry.tags, appending: appendedTags)
            return copy
        }
    }

    static func sanitizedStoredSavedHistoryFilters(_ filters: [SavedHistoryFilter]) -> [SavedHistoryFilter] {
        var seenIDs = Set<String>()
        var seenNames = Set<String>()
        return filters.prefix(importedSavedHistoryFilterLimit).compactMap { filter in
            let safeName = sanitizedSavedHistoryFilterName(filter.name)
            guard !safeName.isEmpty else { return nil }
            let nameKey = savedHistoryFilterNameKey(safeName)
            guard seenNames.insert(nameKey).inserted else { return nil }
            var copy = filter
            copy.id = uniqueImportedID(filter.id, seenIDs: &seenIDs)
            copy.name = safeName
            copy.criteria = sanitizedHistoryFilterCriteria(filter.criteria)
            if copy.updatedAt < copy.createdAt {
                copy.updatedAt = copy.createdAt
            }
            return copy
        }
    }

    static func sanitizedHistoryFilterCriteria(_ criteria: HistoryFilterCriteria) -> HistoryFilterCriteria {
        HistoryFilterCriteria(
            query: limitedImportedString(criteria.query.trimmingCharacters(in: .whitespacesAndNewlines),
                                         maxLength: importedSavedHistoryFilterQueryLimit,
                                         fallback: ""),
            actionFilter: sanitizedHistoryFacet(criteria.actionFilter,
                                                allValue: HistoryFilterCriteria.allActions),
            modelFilter: sanitizedHistoryFacet(criteria.modelFilter,
                                               allValue: HistoryFilterCriteria.allModels),
            tagFilter: sanitizedHistoryFacet(criteria.tagFilter,
                                             allValue: HistoryFilterCriteria.allTags),
            favoriteOnly: criteria.favoriteOnly
        )
    }

    static func sanitizedSavedHistoryFilterName(_ name: String) -> String {
        limitedImportedString(name.trimmingCharacters(in: .whitespacesAndNewlines),
                              maxLength: importedSavedHistoryFilterNameLimit,
                              fallback: "")
    }

    private static func sanitizedHistoryFacet(_ value: String, allValue: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed != allValue else { return allValue }
        let limited = limitedImportedString(trimmed,
                                            maxLength: importedSavedHistoryFilterNameLimit,
                                            fallback: allValue)
        return limited.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? allValue : limited
    }

    static func savedHistoryFilterNameKey(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
    }

    static func sanitizedImportedProviderTemperature(_ value: Double?) -> Double? {
        guard let value, value.isFinite else { return nil }
        return clampedTemperature(value)
    }

    static func sanitizedImportedMaxTokens(_ value: Int?) -> Int? {
        guard let value, value > 0 else { return nil }
        return min(max(value, importedMaxTokensRange.lowerBound), importedMaxTokensRange.upperBound)
    }

    static func sanitizedImportedRequestTimeout(_ value: Double?) -> Double? {
        guard let value, value.isFinite, value > 0 else { return nil }
        return min(max(value, importedRequestTimeoutRange.lowerBound), importedRequestTimeoutRange.upperBound)
    }

    static func sanitizedImportedRedactionRules(_ rules: [PrivacyRedactionRule]) -> [PrivacyRedactionRule] {
        guard !rules.isEmpty else { return [] }
        var seenIDs = Set<String>()
        let cleaned = rules.prefix(importedRedactionRuleLimit).compactMap { rule -> PrivacyRedactionRule? in
            let pattern = rule.pattern.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !pattern.isEmpty,
                  pattern.count <= importedRedactionPatternLimit,
                  PrivacyFilter.validatePattern(pattern) == nil else {
                return nil
            }

            var copy = rule
            copy.id = uniqueImportedID(rule.id, seenIDs: &seenIDs)
            copy.name = limitedImportedString(rule.name.trimmingCharacters(in: .whitespacesAndNewlines),
                                              maxLength: importedRedactionNameLimit,
                                              fallback: "自定义规则")
            copy.pattern = pattern
            copy.replacement = limitedImportedString(rule.replacement,
                                                     maxLength: importedRedactionReplacementLimit,
                                                     fallback: "")
            return copy
        }
        if cleaned.isEmpty {
            return PrivacyRedactionRule.defaults()
        }
        return isLegacyDefaultRedactionRules(cleaned) ? PrivacyRedactionRule.defaults() : cleaned
    }

    static func sanitizedStoredRedactionRules(_ rules: [PrivacyRedactionRule]) -> [PrivacyRedactionRule] {
        guard !rules.isEmpty else { return [] }
        var seenIDs = Set<String>()
        let cleaned = rules.prefix(importedRedactionRuleLimit).map { rule in
            var copy = rule
            copy.id = uniqueImportedID(rule.id, seenIDs: &seenIDs)
            copy.name = limitedImportedString(rule.name.trimmingCharacters(in: .whitespacesAndNewlines),
                                              maxLength: importedRedactionNameLimit,
                                              fallback: "自定义规则")
            copy.pattern = limitedImportedString(rule.pattern.trimmingCharacters(in: .whitespacesAndNewlines),
                                                 maxLength: importedRedactionPatternLimit,
                                                 fallback: "")
            copy.replacement = limitedImportedString(rule.replacement,
                                                     maxLength: importedRedactionReplacementLimit,
                                                     fallback: "")
            return copy
        }
        return isLegacyDefaultRedactionRules(cleaned) ? PrivacyRedactionRule.defaults() : cleaned
    }

    private static func isLegacyDefaultRedactionRules(_ rules: [PrivacyRedactionRule]) -> Bool {
        let legacy = legacyDefaultRedactionRules()
        guard rules.count == legacy.count else { return false }
        return zip(rules, legacy).allSatisfy { current, expected in
            current.name == expected.name &&
            current.pattern == expected.pattern &&
            current.replacement == expected.replacement &&
            current.isEnabled == expected.isEnabled
        }
    }

    private static func legacyDefaultRedactionRules() -> [PrivacyRedactionRule] {
        [
            PrivacyRedactionRule(
                name: "邮箱地址",
                pattern: #"[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}"#,
                replacement: "[邮箱]"
            ),
            PrivacyRedactionRule(
                name: "手机号",
                pattern: #"(?<!\d)(?:\+?86[- ]?)?1[3-9]\d{9}(?!\d)"#,
                replacement: "[手机号]"
            ),
            PrivacyRedactionRule(
                name: "疑似 API Key",
                pattern: #"(?i)\b(?:sk(?:-[a-z0-9]+)+|gh[pousr]_[a-z0-9_]{20,}|xox[baprs]-[a-z0-9-]{20,}|(?:api[_-]?key|token|secret)[_:\-= ]+[a-z0-9][a-z0-9._-]{11,})\b"#,
                replacement: "[密钥]"
            )
        ]
    }

    static func sanitizedImportedContextProfiles(_ profiles: [ContextProfile],
                                                 activeID: String) -> (profiles: [ContextProfile], activeID: String) {
        var seenIDs = Set<String>()
        var requestedActiveID = ""
        let cleaned = profiles.prefix(importedContextProfileLimit).compactMap { profile -> ContextProfile? in
            let trimmedName = profile.name.trimmingCharacters(in: .whitespacesAndNewlines)
            let trimmedContent = profile.content.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedName.isEmpty || !trimmedContent.isEmpty else { return nil }

            var copy = profile
            copy.id = uniqueImportedID(profile.id, seenIDs: &seenIDs)
            copy.name = limitedImportedString(trimmedName,
                                              maxLength: importedContextNameLimit,
                                              fallback: "未命名上下文")
            copy.content = limitedImportedString(trimmedContent,
                                                 maxLength: importedContextContentLimit,
                                                 fallback: "")
            if requestedActiveID.isEmpty && profile.id == activeID {
                requestedActiveID = copy.id
            }
            return copy
        }

        let active = cleaned.first { profile in
            profile.id == requestedActiveID &&
            profile.isEnabled &&
            !profile.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }?.id ?? cleaned.first { profile in
            profile.isEnabled &&
            !profile.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }?.id ?? ""

        return (cleaned, active)
    }

    static func sanitizedStoredContextProfiles(_ profiles: [ContextProfile],
                                               activeID: String) -> (profiles: [ContextProfile], activeID: String) {
        sanitizedImportedContextProfiles(profiles, activeID: activeID)
    }

    static func sanitizedStoredActionUsageCounts(_ counts: [String: Int]) -> [String: Int] {
        var merged: [String: Int] = [:]
        for (name, count) in counts {
            let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedName.isEmpty,
                  count >= importedActionUsageCountRange.lowerBound else { continue }
            let safeName = limitedImportedString(trimmedName,
                                                 maxLength: AIAction.maxNameLength,
                                                 fallback: "")
            guard !safeName.isEmpty else { continue }
            let safeCount = min(max(count, importedActionUsageCountRange.lowerBound),
                                importedActionUsageCountRange.upperBound)
            let combined = min((merged[safeName] ?? 0) + safeCount,
                               importedActionUsageCountRange.upperBound)
            merged[safeName] = combined
        }
        let ranked = merged.sorted {
            if $0.value != $1.value { return $0.value > $1.value }
            return $0.key.localizedStandardCompare($1.key) == .orderedAscending
        }.prefix(importedActionUsageLimit)
        return Dictionary(uniqueKeysWithValues: ranked.map { ($0.key, $0.value) })
    }

    static func sanitizedPrompt(_ value: String?,
                                fallback: String,
                                allowEmpty: Bool = false,
                                maxLength: Int = importedPromptLimit,
                                migrateOldTranslateDefault: Bool = false) -> String {
        var resolved = value ?? fallback
        if migrateOldTranslateDefault && resolved == oldDefaultTranslatePrompt {
            resolved = defaultTranslatePrompt
        }
        if resolved.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return allowEmpty ? "" : fallback
        }
        return limitedImportedString(resolved,
                                     maxLength: maxLength,
                                     fallback: allowEmpty ? "" : fallback)
    }

    private static func uniqueImportedID(_ candidate: String, seenIDs: inout Set<String>) -> String {
        let trimmed = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
        let proposed = trimmed.isEmpty ? UUID().uuidString : trimmed
        if seenIDs.insert(proposed).inserted {
            return proposed
        }
        let replacement = UUID().uuidString
        seenIDs.insert(replacement)
        return replacement
    }

    static func limitedImportedString(_ value: String,
                                      maxLength: Int,
                                      fallback: String) -> String {
        let resolved = value.isEmpty ? fallback : value
        guard resolved.count > maxLength else { return resolved }
        return String(resolved.prefix(maxLength))
    }

    private static func sanitizedOptionalImportedString(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func sanitizedActionModelOverride(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let limited = limitedImportedString(trimmed,
                                            maxLength: importedModelNameLimit,
                                            fallback: "")
        return limited.isEmpty ? nil : limited
    }

    static func sanitizedActiveModelName(_ value: String) -> String {
        limitedImportedString(value.trimmingCharacters(in: .whitespacesAndNewlines),
                              maxLength: importedModelNameLimit,
                              fallback: "")
    }

    static func providerIDAfterProviderSanitization(originalProviders: [AIProvider],
                                                    sanitizedProviders: [AIProvider],
                                                    providerID: String,
                                                    modelName: String?) -> String {
        let requestedID = providerID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !requestedID.isEmpty else { return "" }
        let requestedModel = sanitizedActiveModelName(modelName ?? "")
        let pairs = zip(Array(originalProviders.prefix(sanitizedProviders.count)), sanitizedProviders)
            .filter { original, _ in
                original.id.trimmingCharacters(in: .whitespacesAndNewlines) == requestedID
            }
        guard !pairs.isEmpty else { return requestedID }
        if !requestedModel.isEmpty,
           let match = pairs.first(where: { _, sanitized in
               sanitized.enabledModelNames.contains(requestedModel)
           }) {
            return match.1.id
        }
        return pairs[0].1.id
    }
}
