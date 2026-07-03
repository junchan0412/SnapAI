import Foundation

extension AppSettings {
    static func load() -> AppSettings {
        if let data = UserDefaults.standard.data(forKey: Self.storeKey),
           let s = try? JSONDecoder().decode(AppSettings.self, from: data) {
            let hadPlaintext = String(data: data, encoding: .utf8)?.contains("\"apiKey\"") ?? false
            s.loadKeysFromKeychain()
            s.loadHistoryFromLocalStoreOrMigrate()
            // 旧版本可能把明文 Key 存在 JSON 里;迁移后立即重写一次以彻底清除明文
            if hadPlaintext || s.needsPostLoadSave { s.save() }
            return s
        }
        let settings = AppSettings()
        settings.loadHistoryFromLocalStoreOrMigrate()
        return settings
    }

    /// 从 Keychain 回填各供应商的 apiKey(decode 后它们都是空字符串)
    private func loadKeysFromKeychain() {
        for i in providers.indices {
            // 迁移分支可能已在内存里带了明文 key(来自旧 JSON),优先保留并落 Keychain
            if providers[i].apiKey.isEmpty {
                providers[i].apiKey = Keychain.apiKey(for: providers[i].id)
            } else {
                Keychain.setAPIKey(providers[i].apiKey, for: providers[i].id)
            }
            keychainCache[providers[i].id] = providers[i].apiKey
        }
    }

    func save() {
        // 仅当 Key 发生变化时才写 Keychain(避免打字时频繁写入)
        for p in providers where keychainCache[p.id] != p.apiKey {
            Keychain.setAPIKey(p.apiKey, for: p.id)
            keychainCache[p.id] = p.apiKey
        }
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
}
