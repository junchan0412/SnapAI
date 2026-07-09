import Foundation
import SnapAILogic

extension AIAction {
    var actionTemplateAction: ActionTemplateAction {
        ActionTemplateAction(id: id,
                             name: name,
                             icon: icon,
                             group: group,
                             prompt: prompt,
                             isTranslation: isTranslation,
                             targetLanguage: targetLanguage.rawValue,
                             replaceByDefault: replaceByDefault,
                             isEnabled: isEnabled,
                             thinkingMode: thinkingMode,
                             thinkingBudget: thinkingBudget,
                             saveHistory: saveHistory)
    }
}

extension ActionTemplateAction {
    var aiAction: AIAction {
        var action = AIAction(name: name,
                              icon: icon,
                              group: group,
                              prompt: prompt,
                              isTranslation: isTranslation,
                              targetLanguage: TargetLanguage(rawValue: targetLanguage) ?? .auto,
                              replaceByDefault: replaceByDefault,
                              isEnabled: isEnabled,
                              thinkingMode: thinkingMode,
                              thinkingBudget: AIAction.sanitizedThinkingBudget(thinkingBudget),
                              saveHistory: saveHistory)
        action.id = id
        action.hotKey = nil
        action.providerID = nil
        action.modelOverride = nil
        return action
    }
}

extension Array where Element == AIAction {
    var actionTemplateActions: [ActionTemplateAction] {
        map(\.actionTemplateAction)
    }
}

extension Array where Element == ActionTemplateAction {
    var aiActions: [AIAction] {
        AppSettings.sanitizedImportedActions(map(\.aiAction))
    }
}
