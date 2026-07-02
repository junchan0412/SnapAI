import Foundation

struct ResultCompletionMetrics: Equatable {
    var elapsed: TimeInterval
    var characterCount: Int
}

enum ResultPersistence {
    static func completionMetrics(startTime: Date?,
                                  outputText: String,
                                  now: Date = Date()) -> ResultCompletionMetrics {
        let elapsed = startTime.map { max(0, now.timeIntervalSince($0)) } ?? 0
        return ResultCompletionMetrics(elapsed: elapsed,
                                       characterCount: outputText.count)
    }

    static func conversationExport(actionName: String,
                                   sourceText: String,
                                   outputText: String,
                                   providerName: String,
                                   modelName: String,
                                   fallbackModelName: String,
                                   elapsed: TimeInterval,
                                   diagnostics: AIRequestDiagnostics?,
                                   protectsContent: Bool,
                                   date: Date = Date()) -> ConversationExport {
        ConversationExport(actionName: actionName,
                           sourceText: sourceText,
                           outputText: outputText,
                           providerName: providerName,
                           modelName: modelName.isEmpty ? fallbackModelName : modelName,
                           elapsed: elapsed,
                           diagnostics: diagnostics?.summaryText(includeAttemptMessages: false) ?? "",
                           protectsContent: protectsContent,
                           date: date)
    }

    @discardableResult
    static func saveHistoryIfNeeded(settings: AppSettings,
                                    alreadySaved: Bool,
                                    action: AIAction,
                                    sourceText: String,
                                    outputText: String,
                                    errorMessage: String?,
                                    providerName: String,
                                    fallbackProviderName: String,
                                    modelName: String,
                                    fallbackModelName: String,
                                    historyTags: [String],
                                    contentStorage: HistoryContentStorage?) -> Bool {
        guard !alreadySaved,
              !outputText.isEmpty,
              errorMessage == nil else {
            return alreadySaved
        }
        settings.addHistory(action: action.name,
                            source: sourceText,
                            output: outputText,
                            provider: providerName.isEmpty ? fallbackProviderName : providerName,
                            model: modelName.isEmpty ? fallbackModelName : modelName,
                            tags: historyTags,
                            contentStorage: contentStorage)
        return true
    }
}
