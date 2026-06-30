import Foundation

struct ActionTemplate: Codable, Identifiable, Equatable {
    var id: String
    var title: String
    var category: String
    var summary: String
    var action: AIAction
}

struct ActionTemplateBundle: Codable, Equatable {
    static let currentSchemaVersion = 1

    var schemaVersion: Int = currentSchemaVersion
    var appName: String = "SnapAI"
    var bundleName: String
    var exportedAt: Date
    var templates: [ActionTemplate]
}

enum ActionTemplateLibrary {
    static let defaultBundleName = "SnapAI 动作库"

    static var builtIns: [ActionTemplate] {
        [
            ActionTemplate(
                id: "email-reply",
                title: "邮件回复",
                category: "写作",
                summary: "把原文整理成自然、礼貌、专业的邮件正文。",
                action: AIAction(name: "邮件回复", icon: "envelope",
                                 group: "写作",
                                 prompt: "请根据下面的内容起草一封自然、礼貌、简洁的邮件回复。保留必要事实,语气专业,最后只输出邮件正文:\n\n{{text}}")
            ),
            ActionTemplate(
                id: "meeting-notes",
                title: "会议纪要",
                category: "总结",
                summary: "从会议记录中提炼背景、结论、待办和负责人。",
                action: AIAction(name: "会议纪要", icon: "list.clipboard",
                                 group: "总结",
                                 prompt: "请把下面的会议内容整理为会议纪要,包含:背景、关键结论、待办事项、负责人/时间(如原文有)。使用清晰的 Markdown:\n\n{{text}}")
            ),
            ActionTemplate(
                id: "code-review",
                title: "代码审查",
                category: "代码",
                summary: "按严重程度审查 bug、回归风险、边界条件和测试缺口。",
                action: AIAction(name: "代码审查", icon: "checklist",
                                 group: "代码",
                                 prompt: "请审查下面的代码或变更,优先指出 bug、回归风险、边界条件和测试缺口。按严重程度排序,给出可执行修改建议:\n\n{{text}}")
            ),
            ActionTemplate(
                id: "bilingual-polish",
                title: "中英双语润色",
                category: "写作",
                summary: "输出中文优化版和英文优化版,适合双语内容准备。",
                action: AIAction(name: "中英双语润色", icon: "character.book.closed",
                                 group: "写作",
                                 prompt: "请将下面内容润色为自然、专业的中英双语表达。先给中文优化版,再给英文优化版,保持原意:\n\n{{text}}")
            ),
            ActionTemplate(
                id: "image-understanding",
                title: "图片理解",
                category: "图片",
                summary: "理解截图或图片附带文字,提取关键信息和下一步建议。",
                action: AIAction(name: "图片理解", icon: "photo",
                                 group: "图片",
                                 prompt: "请仔细理解图片和随附文字,提取关键信息、可见问题和下一步建议:\n\n{{text}}")
            )
        ]
    }

    static func exportBundleData(actions: [AIAction],
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

    static func importedActions(from data: Data) throws -> [AIAction] {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if let bundle = try? decoder.decode(ActionTemplateBundle.self, from: data) {
            return sanitizedShareableActions(bundle.templates.map(\.action))
        }
        return sanitizedShareableActions(try decoder.decode([AIAction].self, from: data))
    }

    static func installedAction(from template: ActionTemplate,
                                existingActions: [AIAction]) -> AIAction {
        installedActions(from: [template.action], existingActions: existingActions).first ?? template.action
    }

    static func installedActions(from importedActions: [AIAction],
                                 existingActions: [AIAction]) -> [AIAction] {
        var seenNames = Set(existingActions.map { normalizedName($0.name) })
        var seenIDs = Set(existingActions.map(\.id))
        return sanitizedShareableActions(importedActions).map { action in
            var copy = action
            copy.id = CommandIdentifier.unique(base: copy.name, usedIDs: &seenIDs)
            copy.name = uniqueActionName(copy.name, seenNames: &seenNames)
            copy.hotKey = nil
            return copy
        }
    }

    private static func sanitizedShareableActions(_ actions: [AIAction]) -> [AIAction] {
        guard !actions.isEmpty else { return [] }
        return AppSettings.sanitizedImportedActions(actions).map { action in
            var copy = action
            copy.hotKey = nil
            copy.providerID = nil
            copy.modelOverride = nil
            return copy
        }
    }

    private static func templateSummary(for action: AIAction) -> String {
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
}
