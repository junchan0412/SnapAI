import Foundation

extension AppSettings {
    /// 追加一条历史并裁剪到上限
    @discardableResult
    func addHistory(action: String, source: String, output: String,
                    provider: String, model: String, tags: [String] = [],
                    contentStorage: HistoryContentStorage? = nil,
                    store: HistoryStore = .shared) -> Bool {
        guard historyLimit > 0 else { return false }
        let payload = historyPayload(source: source,
                                     output: output,
                                     tags: tags,
                                     contentStorage: contentStorage ?? historyContentStorage)
        let entry = HistoryEntry(actionName: Self.limitedImportedString(action.trimmingCharacters(in: .whitespacesAndNewlines),
                                                                        maxLength: AIAction.maxNameLength,
                                                                        fallback: "未命名动作"),
                                 source: payload.source,
                                 output: payload.output,
                                 provider: Self.limitedImportedString(provider.trimmingCharacters(in: .whitespacesAndNewlines),
                                                                      maxLength: Self.importedProviderNameLimit,
                                                                      fallback: ""),
                                 model: Self.limitedImportedString(model.trimmingCharacters(in: .whitespacesAndNewlines),
                                                                   maxLength: Self.importedModelNameLimit,
                                                                   fallback: ""),
                                 tags: payload.tags)
        guard store.upsert(entry, limit: historyLimit) else { return false }
        history.insert(entry, at: 0)
        history = Array(history.prefix(historyLimit))
        save()
        return true
    }

    @discardableResult
    func clearHistory(store: HistoryStore = .shared) -> Bool {
        guard store.deleteAll() else { return false }
        history.removeAll()
        save()
        return true
    }

    @discardableResult
    func deleteHistory(id: String, store: HistoryStore = .shared) -> Bool {
        guard history.contains(where: { $0.id == id }) else { return false }
        guard store.delete(id: id) else { return false }
        history.removeAll { $0.id == id }
        save()
        return true
    }

    @discardableResult
    func toggleHistoryFavorite(id: String, store: HistoryStore = .shared) -> Bool {
        guard let idx = history.firstIndex(where: { $0.id == id }) else { return false }
        var updated = history[idx]
        updated.isFavorite.toggle()
        guard store.upsert(updated, limit: historyLimit) else { return false }
        history[idx] = updated
        save()
        return true
    }

    @discardableResult
    func updateHistoryTags(id: String,
                           tags: [String],
                           store: HistoryStore = .shared) -> Bool {
        guard let idx = history.firstIndex(where: { $0.id == id }) else { return false }
        var updated = history[idx]
        updated.tags = Self.historyTags(tags)
        guard store.upsert(updated, limit: historyLimit) else { return false }
        history[idx] = updated
        save()
        return true
    }

    @discardableResult
    func upsertSavedHistoryFilter(name: String,
                                  criteria: HistoryFilterCriteria,
                                  date: Date = Date()) -> SavedHistoryFilter? {
        let safeName = Self.sanitizedSavedHistoryFilterName(name)
        guard !safeName.isEmpty else { return nil }
        let safeCriteria = Self.sanitizedHistoryFilterCriteria(criteria)
        let nameKey = Self.savedHistoryFilterNameKey(safeName)

        var filter: SavedHistoryFilter
        if let index = savedHistoryFilters.firstIndex(where: { Self.savedHistoryFilterNameKey($0.name) == nameKey }) {
            filter = savedHistoryFilters[index]
            filter.name = safeName
            filter.criteria = safeCriteria
            filter.updatedAt = date
            savedHistoryFilters.remove(at: index)
        } else {
            filter = SavedHistoryFilter(name: safeName,
                                        criteria: safeCriteria,
                                        createdAt: date,
                                        updatedAt: date)
        }
        savedHistoryFilters.insert(filter, at: 0)
        savedHistoryFilters = Self.sanitizedStoredSavedHistoryFilters(savedHistoryFilters)
        save()
        return savedHistoryFilters.first { $0.id == filter.id }
    }

    func deleteSavedHistoryFilter(id: String) {
        savedHistoryFilters.removeAll { $0.id == id }
        save()
    }

    func recordActionUsage(actionName: String) {
        let name = Self.limitedImportedString(actionName.trimmingCharacters(in: .whitespacesAndNewlines),
                                              maxLength: AIAction.maxNameLength,
                                              fallback: "未命名动作")
        let current = actionUsageCounts[name] ?? 0
        actionUsageCounts[name] = current >= Self.importedActionUsageCountRange.upperBound
            ? Self.importedActionUsageCountRange.upperBound
            : max(0, current) + 1
        actionUsageCounts = Self.sanitizedStoredActionUsageCounts(actionUsageCounts)
    }

    private func historyPayload(source: String,
                                output: String,
                                tags: [String],
                                contentStorage: HistoryContentStorage) -> (source: String, output: String, tags: [String]) {
        switch contentStorage {
        case .full:
            let sourcePayload = Self.limitedHistoryText(source,
                                                        maxLength: Self.historySourceCharacterLimit)
            let outputPayload = Self.limitedHistoryText(output,
                                                        maxLength: Self.historyOutputCharacterLimit)
            var appendedTags: [String] = []
            if sourcePayload.wasTruncated {
                appendedTags.append(PrivacyHistoryTag.sourceTruncated)
            }
            if outputPayload.wasTruncated {
                appendedTags.append(PrivacyHistoryTag.outputTruncated)
            }
            return (sourcePayload.text, outputPayload.text, Self.historyTags(tags, appending: appendedTags))
        case .metadataOnly:
            return ("", "", Self.historyTags(tags, appending: [PrivacyHistoryTag.metadataOnly]))
        }
    }

    static func limitedHistoryText(_ text: String,
                                   maxLength: Int) -> (text: String, wasTruncated: Bool) {
        guard text.count > maxLength else {
            return (text, false)
        }
        let marker = "\n\n[SnapAI: 历史记录已截断, 原始字符数 \(text.count)]"
        let visibleLimit = max(0, maxLength - marker.count)
        return (String(text.prefix(visibleLimit)) + marker, true)
    }

    static func historyTags(_ tags: [String], appending appendedTags: [String] = []) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        let requiredTags = normalizedHistoryTags(appendedTags)
        let userTagLimit = max(0, historyTagLimit - requiredTags.count)
        for value in normalizedHistoryTags(tags) where result.count < userTagLimit {
            guard !seen.contains(value) else { continue }
            seen.insert(value)
            result.append(value)
        }
        for value in requiredTags where result.count < historyTagLimit {
            guard !seen.contains(value) else { continue }
            seen.insert(value)
            result.append(value)
        }
        return result
    }

    private static func normalizedHistoryTags(_ tags: [String]) -> [String] {
        tags.compactMap { value in
            let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
            let limited = limitedImportedString(normalized,
                                                maxLength: historyTagCharacterLimit,
                                                fallback: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return limited.isEmpty ? nil : limited
        }
    }

    private static func historyTags(_ tags: [String], appending tag: String) -> [String] {
        historyTags(tags, appending: [tag])
    }
}
