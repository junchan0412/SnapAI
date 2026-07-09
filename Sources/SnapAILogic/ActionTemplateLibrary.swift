import Foundation

public struct ActionTemplateAction: Codable, Identifiable, Equatable {
    public static let defaultThinkingBudget = 8_000
    public static let thinkingBudgetRange = 1_024...64_000
    public static let maxNameLength = 80
    public static let maxIconLength = 80
    public static let maxGroupLength = 80
    public static let maxPromptLength = 20_000

    public var id: String
    public var name: String
    public var icon: String
    public var group: String
    public var prompt: String
    public var isTranslation: Bool
    public var targetLanguage: String
    public var replaceByDefault: Bool
    public var isEnabled: Bool
    public var thinkingMode: Bool
    public var thinkingBudget: Int
    public var saveHistory: Bool

    public init(id: String = UUID().uuidString,
                name: String = "新动作",
                icon: String = "wand.and.stars",
                group: String = "",
                prompt: String = "{{text}}",
                isTranslation: Bool = false,
                targetLanguage: String = "自动(中英互译)",
                replaceByDefault: Bool = false,
                isEnabled: Bool = true,
                thinkingMode: Bool = false,
                thinkingBudget: Int = Self.defaultThinkingBudget,
                saveHistory: Bool = true) {
        self.id = id
        self.name = name
        self.icon = icon
        self.group = group
        self.prompt = prompt
        self.isTranslation = isTranslation
        self.targetLanguage = targetLanguage
        self.replaceByDefault = replaceByDefault
        self.isEnabled = isEnabled
        self.thinkingMode = thinkingMode
        self.thinkingBudget = Self.sanitizedThinkingBudget(thinkingBudget)
        self.saveHistory = saveHistory
    }

    public static func sanitizedThinkingBudget(_ value: Int) -> Int {
        min(max(value, thinkingBudgetRange.lowerBound), thinkingBudgetRange.upperBound)
    }

    enum CodingKeys: String, CodingKey {
        case id, name, icon, group, prompt, isTranslation, targetLanguage
        case replaceByDefault, isEnabled, thinkingMode, thinkingBudget, saveHistory
    }
}

extension ActionTemplateAction {
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decode(String.self, forKey: .id)) ?? UUID().uuidString
        name = (try? c.decode(String.self, forKey: .name)) ?? "新动作"
        icon = (try? c.decode(String.self, forKey: .icon)) ?? "wand.and.stars"
        group = (try? c.decode(String.self, forKey: .group)) ?? ""
        prompt = (try? c.decode(String.self, forKey: .prompt)) ?? "{{text}}"
        isTranslation = (try? c.decode(Bool.self, forKey: .isTranslation)) ?? false
        targetLanguage = (try? c.decode(String.self, forKey: .targetLanguage)) ?? "自动(中英互译)"
        replaceByDefault = (try? c.decode(Bool.self, forKey: .replaceByDefault)) ?? false
        isEnabled = (try? c.decode(Bool.self, forKey: .isEnabled)) ?? true
        thinkingMode = (try? c.decode(Bool.self, forKey: .thinkingMode)) ?? false
        thinkingBudget = Self.sanitizedThinkingBudget((try? c.decode(Int.self, forKey: .thinkingBudget)) ?? Self.defaultThinkingBudget)
        saveHistory = (try? c.decode(Bool.self, forKey: .saveHistory)) ?? true
    }
}

public struct ActionTemplate: Codable, Identifiable, Equatable {
    public var id: String
    public var title: String
    public var category: String
    public var summary: String
    public var action: ActionTemplateAction
}

public struct ActionTemplateBundle: Codable, Equatable {
    public static let currentSchemaVersion = 1

    public var schemaVersion: Int = currentSchemaVersion
    public var appName: String = "SnapAI"
    public var bundleName: String
    public var exportedAt: Date
    public var templates: [ActionTemplate]
}

public enum ActionTemplateLibrary {
    public static let defaultBundleName = "SnapAI 动作库"

    public static var builtIns: [ActionTemplate] {
        [
            ActionTemplate(
                id: "email-reply",
                title: "邮件回复",
                category: "写作",
                summary: "把原文整理成自然、礼貌、专业的邮件正文。",
                action: ActionTemplateAction(name: "邮件回复", icon: "envelope",
                                             group: "写作",
                                             prompt: "请根据下面的内容起草一封自然、礼貌、简洁的邮件回复。保留必要事实,语气专业,最后只输出邮件正文:\n\n{{text}}")
            ),
            ActionTemplate(
                id: "meeting-notes",
                title: "会议纪要",
                category: "总结",
                summary: "从会议记录中提炼背景、结论、待办和负责人。",
                action: ActionTemplateAction(name: "会议纪要", icon: "list.clipboard",
                                             group: "总结",
                                             prompt: "请把下面的会议内容整理为会议纪要,包含:背景、关键结论、待办事项、负责人/时间(如原文有)。使用清晰的 Markdown:\n\n{{text}}")
            ),
            ActionTemplate(
                id: "code-review",
                title: "代码审查",
                category: "代码",
                summary: "按严重程度审查 bug、回归风险、边界条件和测试缺口。",
                action: ActionTemplateAction(name: "代码审查", icon: "checklist",
                                             group: "代码",
                                             prompt: "请审查下面的代码或变更,优先指出 bug、回归风险、边界条件和测试缺口。按严重程度排序,给出可执行修改建议:\n\n{{text}}")
            ),
            ActionTemplate(
                id: "bilingual-polish",
                title: "中英双语润色",
                category: "写作",
                summary: "输出中文优化版和英文优化版,适合双语内容准备。",
                action: ActionTemplateAction(name: "中英双语润色", icon: "character.book.closed",
                                             group: "写作",
                                             prompt: "请将下面内容润色为自然、专业的中英双语表达。先给中文优化版,再给英文优化版,保持原意:\n\n{{text}}")
            ),
            ActionTemplate(
                id: "image-understanding",
                title: "图片理解",
                category: "图片",
                summary: "理解截图或图片附带文字,提取关键信息和下一步建议。",
                action: ActionTemplateAction(name: "图片理解", icon: "photo",
                                             group: "图片",
                                             prompt: "请仔细理解图片和随附文字,提取关键信息、可见问题和下一步建议:\n\n{{text}}")
            )
        ]
    }

    public static func exportBundleData(actions: [ActionTemplateAction],
                                        bundleName: String = defaultBundleName,
                                        exportedAt: Date = Date()) throws -> Data {
        let templates = sanitizedShareableActions(actions).enumerated().map { index, action in
            ActionTemplate(
                id: CommandIdentifier.slug(for: action.name.isEmpty ? "action-\(index + 1)" : action.name),
                title: action.name,
                category: action.group,
                summary: templateSummary(for: action),
                action: action
            )
        }
        let bundle = ActionTemplateBundle(bundleName: bundleName,
                                          exportedAt: exportedAt,
                                          templates: templates)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(bundle)
    }

    public static func importedActions(from data: Data) throws -> [ActionTemplateAction] {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if let bundle = try? decoder.decode(ActionTemplateBundle.self, from: data) {
            return sanitizedShareableActions(bundle.templates.map(\.action))
        }
        return sanitizedShareableActions(try decoder.decode([ActionTemplateAction].self, from: data))
    }

    public static func installedAction(from template: ActionTemplate,
                                       existingActions: [ActionTemplateAction]) -> ActionTemplateAction {
        installedActions(from: [template.action], existingActions: existingActions).first ?? template.action
    }

    public static func installedActions(from importedActions: [ActionTemplateAction],
                                        existingActions: [ActionTemplateAction]) -> [ActionTemplateAction] {
        var seenNames = Set(existingActions.map { normalizedName($0.name) })
        var seenIDs = Set(existingActions.map(\.id))
        return sanitizedShareableActions(importedActions).map { action in
            var copy = action
            copy.id = CommandIdentifier.unique(base: copy.name, usedIDs: &seenIDs)
            copy.name = uniqueActionName(copy.name, seenNames: &seenNames)
            return copy
        }
    }

    private static func sanitizedShareableActions(_ actions: [ActionTemplateAction]) -> [ActionTemplateAction] {
        guard !actions.isEmpty else { return [] }
        return actions.prefix(200).map { action in
            ActionTemplateAction(id: action.id,
                                 name: limitedString(action.name, maxLength: ActionTemplateAction.maxNameLength, fallback: "新动作"),
                                 icon: limitedString(action.icon, maxLength: ActionTemplateAction.maxIconLength, fallback: "wand.and.stars"),
                                 group: limitedString(action.group, maxLength: ActionTemplateAction.maxGroupLength, fallback: ""),
                                 prompt: limitedString(action.prompt, maxLength: ActionTemplateAction.maxPromptLength, fallback: "{{text}}"),
                                 isTranslation: action.isTranslation,
                                 targetLanguage: limitedString(action.targetLanguage, maxLength: 80, fallback: "自动(中英互译)"),
                                 replaceByDefault: action.replaceByDefault,
                                 isEnabled: action.isEnabled,
                                 thinkingMode: action.thinkingMode,
                                 thinkingBudget: action.thinkingBudget,
                                 saveHistory: action.saveHistory)
        }
    }

    private static func templateSummary(for action: ActionTemplateAction) -> String {
        let group = action.group.trimmingCharacters(in: .whitespacesAndNewlines)
        if !group.isEmpty {
            return "\(group)动作模板"
        }
        return "自定义动作模板"
    }

    private static func uniqueActionName(_ name: String, seenNames: inout Set<String>) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let base = trimmed.isEmpty ? "新动作" : trimmed
        let normalized = normalizedName(base)
        if seenNames.insert(normalized).inserted {
            return base
        }
        var suffix = 2
        while true {
            let candidate = "\(base) \(suffix)"
            if seenNames.insert(normalizedName(candidate)).inserted {
                return candidate
            }
            suffix += 1
        }
    }

    private static func normalizedName(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
    }

    private static func limitedString(_ value: String,
                                      maxLength: Int,
                                      fallback: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolved = trimmed.isEmpty ? fallback : trimmed
        guard resolved.count > maxLength else { return resolved }
        return String(resolved.prefix(maxLength))
    }
}
