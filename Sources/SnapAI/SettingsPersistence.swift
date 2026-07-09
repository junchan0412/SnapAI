import Foundation

extension AppSettings {
    static func load() -> AppSettings {
        if let data = UserDefaults.standard.data(forKey: Self.storeKey),
           let s = try? JSONDecoder().decode(AppSettings.self, from: data) {
            let hadPlaintext = String(data: data, encoding: .utf8)?.contains("\"apiKey\"") ?? false
            s.loadKeysFromLocalSecretStore()
            s.loadHistoryFromLocalStoreOrMigrate()
            // 旧版本可能把明文 Key 存在 JSON 里;迁移后立即重写一次以彻底清除明文
            if hadPlaintext || s.needsPostLoadSave { s.save() }
            return s
        }
        let settings = AppSettings()
        settings.loadHistoryFromLocalStoreOrMigrate()
        return settings
    }

    /// 从本地加密密钥存储回填各供应商的 apiKey(decode 后它们都是空字符串)
    private func loadKeysFromLocalSecretStore() {
        var writeFailures = 0
        for i in providers.indices {
            // 迁移分支可能已在内存里带了明文 key(来自旧 JSON),优先保留并落本地加密存储。
            if providers[i].apiKey.isEmpty {
                providers[i].apiKey = LocalSecretStore.apiKey(for: providers[i].id)
            } else if !LocalSecretStore.setAPIKey(providers[i].apiKey, for: providers[i].id) {
                writeFailures += 1
            }
            secretStoreCache[providers[i].id] = providers[i].apiKey
        }
        updateSecretStoreStatus(writeFailures: writeFailures)
    }

    func save() {
        // 仅当 Key 发生变化时才写本地加密存储(避免打字时频繁写入)
        var writeFailures = 0
        for p in providers where secretStoreCache[p.id] != p.apiKey {
            if LocalSecretStore.setAPIKey(p.apiKey, for: p.id) {
                secretStoreCache[p.id] = p.apiKey
            } else {
                writeFailures += 1
            }
        }
        updateSecretStoreStatus(writeFailures: writeFailures)
        let sanitizedHistory = Self.sanitizedStoredHistory(history, limit: historyLimit)
        if sanitizedHistory != history {
            history = sanitizedHistory
            HistoryStore.shared.replaceAll(history, limit: historyLimit)
        }
        if let data = try? JSONEncoder().encode(self) {
            UserDefaults.standard.set(data, forKey: Self.storeKey)
        }
    }

    private func loadHistoryFromLocalStoreOrMigrate() {
        let storedHistory = HistoryStore.shared.load(limit: historyLimit)
        if !storedHistory.isEmpty {
            history = storedHistory
            return
        }
        if !history.isEmpty {
            HistoryStore.shared.replaceAll(history, limit: historyLimit)
        }
    }

    private func updateSecretStoreStatus(writeFailures: Int) {
        let summary = LocalSecretStore.diagnosticSummary()
        if writeFailures > 0 {
            secretStoreStatus = "\(summary), writeFailures=\(writeFailures)"
        } else {
            secretStoreStatus = summary
        }
    }
}
