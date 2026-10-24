import SnapAILogic
import Foundation

@MainActor
final class ResultSubmissionCoordinator {
    typealias PreparationHandler = (String, AIAction, @escaping (String) -> [ChatMessage]) -> PrivacyPreparedSubmission?

    private let settings: AppSettings
    private(set) var messages: [ChatMessage] = []

    init(settings: AppSettings) {
        self.settings = settings
    }

    func prepare(text: String,
                 action: AIAction,
                 messageBuilder: @escaping (String) -> [ChatMessage],
                 using handler: PreparationHandler?) -> PrivacyPreparedSubmission? {
        if let handler {
            return handler(text, action, messageBuilder)
        }
        let preview = PrivacySubmissionPreview.prepare(text: text, action: action,
                                                       settings: settings, messageBuilder: messageBuilder)
        return PrivacyPreparedSubmission(text: preview.processedText,
                                         diagnostic: preview.diagnostic(previewRequired: false),
                                         messages: preview.messages)
    }

    func initialMessages(action: AIAction,
                         targetLanguage: TargetLanguage,
                         sourceText: String,
                         imageData: Data?,
                         imageMimeType: String,
                         sourceContext: SelectionSourceContext?) -> [ChatMessage] {
        RequestSession.initialMessages(
            settings: settings,
            action: action,
            targetLanguage: targetLanguage,
            sourceText: sourceText,
            imageData: imageData,
            imageMimeType: imageMimeType,
            sourceContext: sourceContext
        ).messages
    }

    func followUpMessages(assistantText: String, userText: String) -> [ChatMessage] {
        var messages = currentMessages()
        RequestSession.appendFollowUp(to: &messages,
                                      assistantText: assistantText,
                                      userText: userText)
        return messages
    }

    func currentMessages() -> [ChatMessage] {
        var messages = messages.filter { $0.role != .system }
        if !settings.effectiveSystemPrompt.isEmpty {
            messages.insert(ChatMessage(role: .system, content: settings.effectiveSystemPrompt), at: 0)
        }
        return messages
    }

    func replaceMessages(_ messages: [ChatMessage]) {
        self.messages = messages
    }
}
