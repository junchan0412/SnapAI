import Foundation
import SnapAILogic

struct ResultCompletionContext {
    var recordUsage: Bool
    var saveHistory: Bool
    var action: AIAction
    var sourceText: String
    var outputText: String
    var errorMessage: String?
    var providerName: String
    var modelName: String
    var historyTags: [String]
    var contentStorage: HistoryContentStorage?
    var autoReplaceEnabled: Bool
    var replacementOriginalText: String
}

struct ResultCompletionOutcome: Equatable {
    var metrics: ResultCompletionMetrics
    var didAutoReplace: Bool
}

@MainActor
final class ResultCompletionCoordinator {
    let state = ResultCompletionState()

    private let settings: AppSettings
    private var lifecycle = ResultCompletionLifecycle()
    private var startTime: Date?

    init(settings: AppSettings) {
        self.settings = settings
    }

    func reset(now: Date = Date()) {
        lifecycle.reset()
        startTime = now
        state.reset()
    }

    @discardableResult
    func markRouteStarted(now: Date = Date()) -> Date {
        startTime = now
        return now
    }

    func finish(context: ResultCompletionContext,
                now: Date = Date(),
                onReplace: ((String, String) -> Void)?) -> ResultCompletionOutcome? {
        guard lifecycle.beginCompletion() else { return nil }

        let metrics = ResultPersistence.completionMetrics(startTime: startTime,
                                                          outputText: context.outputText,
                                                          now: now)
        state.replace(with: metrics)

        if context.recordUsage {
            settings.recordActionUsage(actionName: context.action.name)
        }

        if context.saveHistory && context.action.saveHistory {
            let saved = ResultPersistence.saveHistoryIfNeeded(
                settings: settings,
                alreadySaved: lifecycle.isHistorySaved,
                action: context.action,
                sourceText: context.sourceText,
                outputText: context.outputText,
                errorMessage: context.errorMessage,
                providerName: context.providerName,
                fallbackProviderName: settings.activeProvider?.name ?? "",
                modelName: context.modelName,
                fallbackModelName: settings.model,
                historyTags: context.historyTags,
                contentStorage: context.contentStorage
            )
            lifecycle.updateHistorySaved(saved)
        } else if context.recordUsage {
            settings.save()
        }

        let shouldAutoReplace = ResultWriteBackCoordinator.shouldAutoReplace(
            recordUsage: context.recordUsage,
            autoReplaceEnabled: context.autoReplaceEnabled,
            replaceByDefault: context.action.replaceByDefault,
            outputText: context.outputText,
            errorMessage: context.errorMessage
        )
        if shouldAutoReplace {
            ResultWriteBackCoordinator.replace(original: context.replacementOriginalText,
                                               replacement: context.outputText,
                                               handler: onReplace)
        }

        return ResultCompletionOutcome(metrics: metrics,
                                       didAutoReplace: shouldAutoReplace)
    }
}
