import Foundation

struct RequestSessionPayload {
    var messages: [ChatMessage]
    var hasImage: Bool
}

enum RequestSession {
    static func initialMessages(settings: AppSettings,
                                action: AIAction,
                                targetLanguage: TargetLanguage,
                                sourceText: String,
                                imageData: Data?,
                                imageMimeType: String,
                                sourceContext: SelectionSourceContext?) -> RequestSessionPayload {
        var scopedAction = action
        scopedAction.targetLanguage = targetLanguage
        let renderedText = scopedAction.render(text: sourceText)
        let userContent = userContent(renderedText: renderedText,
                                      sourceContext: sourceContext)

        var messages: [ChatMessage] = []
        let systemPrompt = settings.effectiveSystemPrompt
        if !systemPrompt.isEmpty {
            messages.append(ChatMessage(role: .system, content: systemPrompt))
        }
        var userMessage = ChatMessage(role: .user, content: userContent)
        if let imageData {
            userMessage.imageData = imageData
            userMessage.imageMimeType = imageMimeType
        }
        messages.append(userMessage)
        return RequestSessionPayload(messages: messages,
                                     hasImage: imageData != nil)
    }

    static func appendFollowUp(to messages: inout [ChatMessage],
                               assistantText: String,
                               userText: String) {
        if !assistantText.isEmpty {
            messages.append(ChatMessage(role: .assistant, content: assistantText))
        }
        messages.append(ChatMessage(role: .user, content: userText))
    }

    static func userContent(renderedText: String,
                            sourceContext: SelectionSourceContext?) -> String {
        guard let sourceContext else { return renderedText }
        return "\(sourceContext.promptPrefix)\n\n\(renderedText)"
    }

    static func payloadCharacterCounts(messages: [ChatMessage]) -> (finalUserPrompt: Int, systemPrompt: Int) {
        let finalUserPrompt = messages.reversed().first { $0.role == .user }?.content.count ?? 0
        let systemPrompt = messages.first { $0.role == .system }?.content.count ?? 0
        return (finalUserPrompt, systemPrompt)
    }
}
