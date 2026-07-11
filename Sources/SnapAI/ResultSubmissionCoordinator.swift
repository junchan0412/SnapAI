import Foundation

@MainActor
final class ResultSubmissionCoordinator {
    private let settings: AppSettings
    private(set) var messages: [ChatMessage] = []

    init(settings: AppSettings) {
        self.settings = settings
    }

    func prepare(text: String,
                 action: AIAction,
                 using handler: ((String, AIAction) -> PrivacyPreparedSubmission?)?) -> PrivacyPreparedSubmission? {
        if let handler {
            return handler(text, action)
        }
        return PrivacyPreparedSubmission.passthrough(
            text: text,
            saveHistoryEnabled: action.saveHistory,
            historyContentStorage: settings.historyContentStorage
        )
    }

    func beginInitialRequest(action: AIAction,
                             targetLanguage: TargetLanguage,
                             sourceText: String,
                             imageData: Data?,
                             imageMimeType: String,
                             sourceContext: SelectionSourceContext?) -> Bool {
        let payload = RequestSession.initialMessages(
            settings: settings,
            action: action,
            targetLanguage: targetLanguage,
            sourceText: sourceText,
            imageData: imageData,
            imageMimeType: imageMimeType,
            sourceContext: sourceContext
        )
        messages = payload.messages
        return payload.hasImage
    }

    func appendFollowUp(assistantText: String, userText: String) {
        RequestSession.appendFollowUp(to: &messages,
                                      assistantText: assistantText,
                                      userText: userText)
    }
}
