import Foundation

extension AppSettings {
    package static func load(defaults: UserDefaults = .standard,
                     historyStore: HistoryStore = .shared) -> AppSettings {
        let data = defaults.data(forKey: Self.storeKey)
        let decoded = data.flatMap { try? JSONDecoder().decode(AppSettings.self, from: $0) }
        let settings = decoded ?? AppSettings()
        if data != nil && decoded == nil {
            settings.historyLimit = Self.importedHistoryLimitRange.upperBound
        }
        settings.persistenceDefaults = defaults
        settings.persistenceHistoryStore = historyStore
        settings.lastSavedSettingsData = data
        if data != nil {
            settings.loadKeysFromLocalSecretStore()
        }
        if settings.loadHistoryFromLocalStoreOrMigrate(), data == nil || decoded != nil {
            settings.save()
        }
        return settings
    }

    private func loadKeysFromLocalSecretStore() {
        var writeFailures = 0
        for i in providers.indices {
            if providers[i].apiKey.isEmpty {
                providers[i].apiKey = LocalSecretStore.apiKey(for: providers[i].id)
                secretStoreCache[providers[i].id] = providers[i].apiKey
            } else if LocalSecretStore.setAPIKey(providers[i].apiKey, for: providers[i].id) {
                secretStoreCache[providers[i].id] = providers[i].apiKey
            } else {
                writeFailures += 1
            }
        }
        updateSecretStoreStatus(writeFailures: writeFailures)
    }

    @discardableResult
    package func save(historyStore: HistoryStore? = nil) -> Bool {
        if historyNeedsMigrationRetry && !loadHistoryFromLocalStoreOrMigrate() {
            return false
        }
        let historyStore = historyStore ?? persistenceHistoryStore

        var writeFailures = 0
        var didWriteSecrets = false
        for provider in providers where secretStoreCache[provider.id] != provider.apiKey {
            didWriteSecrets = true
            if LocalSecretStore.setAPIKey(provider.apiKey, for: provider.id) {
                secretStoreCache[provider.id] = provider.apiKey
            } else {
                writeFailures += 1
            }
        }
        if didWriteSecrets || secretStoreStatus == "not-checked" {
            updateSecretStoreStatus(writeFailures: writeFailures)
        }
        // A failed legacy migration must not discard the only recoverable copy.
        guard writeFailures == 0 else { return false }

        if historyNeedsValidation {
            let safeLimit = Self.clampedHistoryLimit(historyLimit)
            if safeLimit != historyLimit { historyLimit = safeLimit }
            let sanitized = Self.sanitizedStoredHistory(history, limit: historyLimit)
            if sanitized != history {
                guard historyStore.replaceAll(sanitized, limit: historyLimit) else { return false }
                history = sanitized
                historyLimitNeedsPersistence = false
            }
            historyNeedsValidation = false
        }
        if historyLimitNeedsPersistence {
            guard historyStore.prune(limit: historyLimit) else { return false }
            historyLimitNeedsPersistence = false
        }

        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            let data = try encoder.encode(self)
            if data != lastSavedSettingsData {
                persistenceDefaults.set(data, forKey: Self.storeKey)
                lastSavedSettingsData = data
            }
            needsPostLoadSave = false
            return true
        } catch {
            return false
        }
    }

    @discardableResult
    package func loadHistoryFromLocalStoreOrMigrate() -> Bool {
        switch persistenceHistoryStore.loadResult(limit: historyLimit) {
        case .failure:
            historyNeedsMigrationRetry = true
            return false
        case .success(let storedHistory):
            if storedHistory.isEmpty && !history.isEmpty {
                guard persistenceHistoryStore.replaceAll(history, limit: historyLimit) else {
                    historyNeedsMigrationRetry = true
                    return false
                }
                needsPostLoadSave = true
            } else {
                history = storedHistory
            }
            historyNeedsMigrationRetry = false
            historyLimitNeedsPersistence = true
            return true
        }
    }

    private func updateSecretStoreStatus(writeFailures: Int) {
        let summary = LocalSecretStore.diagnosticSummary()
        secretStoreStatus = writeFailures > 0 ? "\(summary), writeFailures=\(writeFailures)" : summary
    }
}
