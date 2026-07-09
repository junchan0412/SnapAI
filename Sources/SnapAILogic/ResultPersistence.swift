import Foundation

public struct ResultCompletionMetrics: Equatable {
    public var elapsed: TimeInterval
    public var characterCount: Int
}

public enum ResultPersistence {
    public static func completionMetrics(startTime: Date?,
                                         outputText: String,
                                         now: Date = Date()) -> ResultCompletionMetrics {
        let elapsed = startTime.map { max(0, now.timeIntervalSince($0)) } ?? 0
        return ResultCompletionMetrics(elapsed: elapsed,
                                       characterCount: outputText.count)
    }

    public static func conversationExport(actionName: String,
                                          sourceText: String,
                                          outputText: String,
                                          providerName: String,
                                          modelName: String,
                                          fallbackModelName: String,
                                          elapsed: TimeInterval,
                                          diagnosticsText: String,
                                          protectsContent: Bool,
                                          date: Date = Date()) -> ConversationExport {
        ConversationExport(actionName: actionName,
                           sourceText: sourceText,
                           outputText: outputText,
                           providerName: providerName,
                           modelName: modelName.isEmpty ? fallbackModelName : modelName,
                           elapsed: elapsed,
                           diagnostics: diagnosticsText,
                           protectsContent: protectsContent,
                           date: date)
    }
}
