import Foundation

extension AppSettings {
    var activeContextProfile: ContextProfile? {
        contextProfiles.first {
            $0.id == activeContextProfileID &&
            $0.isEnabled &&
            !$0.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    var effectiveSystemPrompt: String {
        let base = systemPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let profile = activeContextProfile else { return base }
        let context = profile.content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !context.isEmpty else { return base }
        let profileName = MarkdownExportSafety.metadata(profile.name,
                                                         fallback: "未命名上下文",
                                                         maxLength: 80)
        let block = """
        当前上下文包: \(profileName)
        \(context)
        """
        return [base, block].filter { !$0.isEmpty }.joined(separator: "\n\n")
    }

    var effectiveSystemPromptMarkdownExport: String {
        let prompt = effectiveSystemPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        let contextName = MarkdownExportSafety.metadata(activeContextProfile?.name,
                                                        fallback: "无",
                                                        maxLength: 80)
        return """
        # SnapAI 实际系统提示

        - 当前上下文包: \(contextName)
        - 字符数: \(prompt.count)

        ## 内容

        \(prompt.isEmpty ? "无内容" : prompt)
        """
    }

    var contextStatusSummary: ContextStatusSummary {
        ContextStatusSummary.make(settings: self)
    }

    var contextStatusMarkdownExport: String {
        let summary = contextStatusSummary
        return """
        # SnapAI 上下文状态

        - 上下文包总数: \(summary.profileCount)
        - 可用上下文包: \(summary.usableProfileCount)
        - 当前上下文包: \(MarkdownExportSafety.metadata(summary.activeProfileName, fallback: "无", maxLength: 80))
        - 当前上下文字符数: \(summary.activeContextCharacterCount)
        - 全局 System Prompt 字符数: \(summary.globalSystemPromptCharacterCount)
        - 实际 System Prompt 字符数: \(summary.effectiveSystemPromptCharacterCount)
        """
    }

    func hasContextProfile(named name: String) -> Bool {
        contextProfileIndex(named: name) != nil
    }

    @discardableResult
    func upsertContextProfile(from draft: HistoryContextProfileDraft) -> ContextProfileUpsertResult {
        let trimmedName = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedName = trimmedName.isEmpty ? "历史上下文" : trimmedName
        if let index = contextProfileIndex(named: resolvedName) {
            contextProfiles[index].name = resolvedName
            contextProfiles[index].content = draft.content
            contextProfiles[index].isEnabled = true
            activeContextProfileID = contextProfiles[index].id
            save()
            return ContextProfileUpsertResult(profile: contextProfiles[index], didUpdate: true)
        }

        let profile = ContextProfile(name: resolvedName,
                                     content: draft.content,
                                     isEnabled: true)
        contextProfiles.append(profile)
        activeContextProfileID = profile.id
        save()
        return ContextProfileUpsertResult(profile: profile, didUpdate: false)
    }

    private func contextProfileIndex(named name: String) -> Int? {
        let normalizedName = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalizedName.isEmpty else { return nil }
        return contextProfiles.firstIndex {
            $0.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == normalizedName
        }
    }
}
