import Foundation
import SnapAILogic

@MainActor
extension ResultViewModel {
    func conversationFollowUpMessages(assistantText: String, userText: String) -> [ChatMessage] {
        guard let conversationSession else {
            return submissionCoordinator.followUpMessages(assistantText: assistantText, userText: userText)
        }
        var messages = conversationSession.contextMessages.filter { $0.role != .system }
        if !settings.effectiveSystemPrompt.isEmpty {
            messages.insert(ChatMessage(role: .system, content: settings.effectiveSystemPrompt), at: 0)
        }
        if conversationSession.messages.last?.role != .assistant, !assistantText.isEmpty {
            messages.append(ChatMessage(role: .assistant, content: assistantText))
        }
        messages.append(ChatMessage(role: .user, content: userText))
        return messages
    }

    func recordConversationOutput(isComplete: Bool) {
        guard conversationSession != nil else { return }
        if !completeText.isEmpty {
            conversationSession?.messages.append(ConversationMessage(
                ChatMessage(role: .assistant, content: completeText),
                providerName: activeProviderName, modelName: activeModelName, isComplete: isComplete))
        }
        persistConversation()
    }

    @discardableResult
    func persistConversation() -> Bool {
        guard var conversationSession else { return false }
        conversationSession.updatedAt = Date()
        self.conversationSession = conversationSession
        let result = settings.persistenceConversationStore.save(conversationSession,
            historyLimit: settings.historyLimit,
            contentStorage: settings.historyContentStorage == .metadataOnly ? .metadataOnly
                : (submissionPrivacy?.effectiveHistoryContentStorage ?? settings.historyContentStorage),
            protectsContent: contentExportProtectionEnabled)
        switch result {
        case .success(let saved): return saved
        case .failure:
            operationCoordinator.showError("会话保存失败，请先复制或导出结果。")
            return false
        }
    }

    func restoreConversation(_ conversation: ConversationSession) {
        guard !isGenerating else { return }
        resetOutput()
        conversationSession = conversation
        action = conversation.action
        targetLanguage = action.targetLanguage
        sourceText = conversation.sourceText
        sourceImageData = conversation.sourceImageWasSubmitted == false ? nil : conversation.sourceImageData
        retainedImageData = conversation.sourceImageData
        retainedImageMimeType = conversation.sourceImageMimeType
        sourceImageMimeType = conversation.sourceImageMimeType
        replacementOriginalText = ""
        autoReplaceEnabled = false
        pendingCaptureMethod = nil
        pendingSourceContext = nil
        submissionPrivacy = nil
        restoredConversation = true
        activeProviderName = ""
        activeModelName = ""
        var messages = conversation.contextMessages
        if let last = conversation.messages.last, last.role == .assistant {
            _ = streamingCoordinator.appendContentToken(last.content, extractsThinkTags: false)
            _ = streamingCoordinator.finish()
            output = last.content
            completionState.replace(with: ResultCompletionMetrics(elapsed: 0, characterCount: last.content.count))
            activeProviderName = last.providerName
            activeModelName = last.modelName
            if !last.isComplete { incompleteResultReason = .interrupted }
            if messages.last?.role == .assistant { messages.removeLast() }
        }
        submissionCoordinator.replaceMessages(messages)
        followUp = ""
    }

    func branchConversation(through messageID: String) {
        guard !isGenerating, let session = conversationSession else { return }
        do {
            let branch = try session.branch(throughMessageID: messageID)
            restoreConversation(branch)
            if persistConversation() { operationCoordinator.showSuccess("已创建分支，原会话保持不变。") }
        } catch { operationCoordinator.showError(error.localizedDescription) }
    }

    func compressConversation(through messageID: String, summary: String) {
        guard !isGenerating, conversationSession != nil else { return }
        do {
            try conversationSession?.compress(throughMessageID: messageID, summary: summary)
            if persistConversation() { operationCoordinator.showSuccess("已启用摘要，原始轮次仍保留，可随时撤销。") }
        } catch { operationCoordinator.showError(error.localizedDescription) }
    }

    func disableConversationCompression() {
        guard !isGenerating else { return }
        try? conversationSession?.activateCompression(id: nil)
        _ = persistConversation()
    }
}
