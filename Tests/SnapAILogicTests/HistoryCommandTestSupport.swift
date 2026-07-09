import Foundation
#if !SNAPAI_MANUAL_TEST_MAIN
@testable import SnapAILogic
#endif

func historyExportCommandInputs(_ history: [HistoryEntry]) -> [HistoryExportCommandInput] {
    history.map { entry in
        HistoryExportCommandInput(displayActionName: entry.displayActionName,
                                  displayModelFilterName: entry.displayModelFilterName,
                                  displayTags: entry.displayTags,
                                  isFavorite: entry.isFavorite)
    }
}

func historyContextCommandInputs(_ history: [HistoryEntry]) -> [HistoryContextCommandInput] {
    history.map { entry in
        HistoryContextCommandInput(displayActionName: entry.displayActionName,
                                   displayModelFilterName: entry.displayModelFilterName,
                                   displayTags: entry.displayTags,
                                   isFavorite: entry.isFavorite,
                                   isUsableForContext: HistoryContextProfileBuilder.isUsableForContext(entry))
    }
}

func actionTemplateAction(_ action: AIAction) -> ActionTemplateAction {
    ActionTemplateAction(id: action.id,
                         name: action.name,
                         icon: action.icon,
                         group: action.group,
                         prompt: action.prompt,
                         isTranslation: action.isTranslation,
                         targetLanguage: action.targetLanguage.rawValue,
                         replaceByDefault: action.replaceByDefault,
                         isEnabled: action.isEnabled,
                         thinkingMode: action.thinkingMode,
                         thinkingBudget: action.thinkingBudget,
                         saveHistory: action.saveHistory)
}

func aiAction(_ action: ActionTemplateAction) -> AIAction {
    var result = AIAction(name: action.name,
                          icon: action.icon,
                          group: action.group,
                          prompt: action.prompt,
                          isTranslation: action.isTranslation,
                          targetLanguage: TargetLanguage(rawValue: action.targetLanguage) ?? .auto,
                          replaceByDefault: action.replaceByDefault,
                          isEnabled: action.isEnabled,
                          thinkingMode: action.thinkingMode,
                          thinkingBudget: AIAction.sanitizedThinkingBudget(action.thinkingBudget),
                          saveHistory: action.saveHistory)
    result.id = action.id
    return result
}
