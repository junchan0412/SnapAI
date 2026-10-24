import Foundation
import SnapAILogic

@MainActor
func runSubmissionPrivacyRuntimeTests() async -> [String] {
    var failures: [String] = []
    func check(_ condition: Bool, _ message: String) {
        if !condition { failures.append("Submission privacy: " + message) }
    }

    let root = FileManager.default.temporaryDirectory.appendingPathComponent("SnapAI-SubmissionPrivacy-\(UUID().uuidString)")
    let suite = "com.snapai.submission-privacy-runtime.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defer {
        defaults.removePersistentDomain(forName: suite)
        try? FileManager.default.removeItem(at: root)
    }
    let settings = AppSettings()
    settings.persistenceDefaults = defaults
    settings.persistenceHistoryStore = HistoryStore(url: root.appendingPathComponent("history.sqlite"))
    settings.providers = []
    settings.autoRouteEnabled = false
    settings.fallbackEnabled = false
    settings.iCloudSyncEnabled = false
    settings.typewriterSpeed = .off
    settings.privacyPreviewEnabled = true
    settings.redactionEnabled = false
    settings.systemPrompt = "System system@example.invalid"
    settings.redactionRules = PrivacyRedactionRule.defaults()

    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [StreamFixtureProtocol.self]
    let session = URLSession(configuration: configuration)
    defer { session.invalidateAndCancel() }
    StreamFixtureProtocol.store.resetPlans([])

    let imageData = Data("opaque attachment fixture".utf8)
    let mimeType = "image/jpeg"
    let sourceContext = SelectionSourceContext.make(appName: "Xcode")
    let source = "Source source@example.invalid"
    let action = AIAction(name: "Privacy fixture", prompt: "Template template@example.invalid {{lang}}\n{{text}}",
                          isTranslation: true, saveHistory: false)
    let alternate = AIAction(name: "Alternate privacy fixture", prompt: "Alternate alternate@example.invalid\n{{text}}",
                             targetLanguage: .japanese, saveHistory: false)

    func makeVM() -> ResultViewModel {
        let vm = ResultViewModel(settings: settings, session: session)
        vm.start(text: source, action: action, imageData: imageData, imageMimeType: mimeType,
                 sourceContext: sourceContext)
        return vm
    }
    func showAnswer(_ text: String, in vm: ResultViewModel) {
        _ = vm.streamingCoordinator.appendContentToken(text, extractsThinkTags: false)
        vm.output = vm.completeText
    }
    func checkImageAndContext(_ messages: [ChatMessage], _ operation: String) {
        let attachments = messages.filter { $0.imageData != nil }
        check(attachments.count == 1 && attachments.first?.imageData == imageData &&
              attachments.first?.imageMimeType == mimeType,
              "\(operation) retains the complete attachment and its MIME type")
        check(messages.first { $0.role == .user }?.content.contains(sourceContext.promptPrefix) == true,
              "\(operation) includes the source context in the preview and submitted conversation")
    }

    settings.redactionEnabled = true
    let initialPreview = PrivacySubmissionPreview.prepare(text: source, action: action, settings: settings) { text in
        RequestSession.initialMessages(settings: settings, action: action, targetLanguage: action.targetLanguage,
                                       sourceText: text, imageData: imageData, imageMimeType: mimeType,
                                       sourceContext: sourceContext).messages
    }
    let initialPrepared = initialPreview.preparedSubmission(userPreferenceEnabled: true)
    let initialVM = ResultViewModel(settings: settings, session: session)
    settings.systemPrompt = "A setting changed after confirmation"
    initialVM.start(text: initialPrepared.text, originalText: source, action: action,
                    imageData: imageData, imageMimeType: mimeType,
                    submissionPrivacy: initialPrepared.diagnostic, sourceContext: sourceContext,
                    preparedMessages: initialPrepared.messages)
    check(initialPrepared.messages != nil && initialVM.comparisonMessages == initialPreview.messages,
          "initial submission uses the exact confirmed messages without rebuilding changed settings")
    check(initialVM.submissionPrivacy?.hasImage == true,
          "initial submission diagnostics retain the confirmed attachment")
    checkImageAndContext(initialVM.comparisonMessages, "initial submission")

    for operation in ["resend", "language", "action"] {
        settings.redactionEnabled = false
        settings.systemPrompt = "System system@example.invalid"
        let vm = makeVM()
        vm.sourceText = "Edited edited@example.invalid"
        settings.redactionEnabled = true
        var previews: [PrivacySubmissionPreview] = []
        var accepts = true
        vm.prepareSourceSubmission = { text, submittedAction, messageBuilder in
            let preview = PrivacySubmissionPreview.prepare(text: text, action: submittedAction,
                                                           settings: settings, messageBuilder: messageBuilder)
            previews.append(preview)
            return accepts ? preview.preparedSubmission(userPreferenceEnabled: settings.privacyPreviewEnabled) : nil
        }
        switch operation {
        case "resend": vm.resendEdited()
        case "language": vm.changeLanguage(.english)
        default: vm.switchAction(alternate)
        }
        check(previews.count == 1 && previews.last?.messages == vm.comparisonMessages,
              "\(operation) submits exactly the complete messages shown by its preparation handler")
        check(previews.last?.hasImage == true && previews.last?.systemPrompt == "System [邮箱]",
              "\(operation) previews the attachment and redacted system prompt")
        check(vm.comparisonMessages.map(\.role) == [.system, .user] &&
              vm.comparisonMessages.allSatisfy { !$0.content.contains("@example.invalid") },
              "\(operation) redacts source, action template and system text in the final payload")
        checkImageAndContext(vm.comparisonMessages, operation)
        if operation == "language" {
            check(vm.targetLanguage == .english && previews.last?.userPrompt.contains(TargetLanguage.english.instruction) == true,
                  "language changes are rendered before confirmation")
        } else if operation == "action" {
            check(vm.action == alternate && previews.last?.userPrompt.contains("Alternate [邮箱]") == true,
                  "action changes are rendered before confirmation")
        }

        showAnswer("Retained answer retained@example.invalid", in: vm)
        vm.thinkingText = "Retained thinking"
        vm.sourceText = "Cancelled edit cancelled@example.invalid"
        accepts = false
        let messagesBefore = vm.comparisonMessages
        let sourceBefore = vm.sourceText
        let actionBefore = vm.action
        let languageBefore = vm.targetLanguage
        let outputBefore = vm.output
        let completeBefore = vm.completeText
        let diagnosticBefore = vm.submissionPrivacy
        switch operation {
        case "resend": vm.resendEdited()
        case "language": vm.changeLanguage(.french)
        default: vm.switchAction(action)
        }
        check(previews.count == 2 && previews.last?.messages != nil,
              "cancelled \(operation) still presents the complete proposed request")
        check(vm.comparisonMessages == messagesBefore && vm.sourceText == sourceBefore && vm.action == actionBefore &&
              vm.targetLanguage == languageBefore && vm.output == outputBefore && vm.completeText == completeBefore &&
              vm.thinkingText == "Retained thinking" && vm.submissionPrivacy == diagnosticBefore,
              "cancelling \(operation) preserves the current messages, input, action, output and diagnostics")
    }

    settings.redactionEnabled = false
    settings.systemPrompt = "System system@example.invalid"
    let followUpVM = makeVM()
    showAnswer("Previous assistant assistant@example.invalid", in: followUpVM)
    settings.redactionEnabled = true
    var followUpPreviews: [PrivacySubmissionPreview] = []
    var acceptsFollowUp = true
    followUpVM.prepareFollowUpSubmission = { text, submittedAction, messageBuilder in
        let preview = PrivacySubmissionPreview.prepare(text: text, action: submittedAction,
                                                       settings: settings, messageBuilder: messageBuilder)
        followUpPreviews.append(preview)
        return acceptsFollowUp ? preview.preparedSubmission(userPreferenceEnabled: true) : nil
    }
    followUpVM.followUp = "  Follow-up followup@example.invalid  "
    followUpVM.sendFollowUp()
    check(followUpPreviews.count == 1 && followUpPreviews.last?.messages == followUpVM.comparisonMessages,
          "follow-up submits the exact full conversation shown in its preview")
    check(followUpVM.comparisonMessages.map(\.role) == [.system, .user, .assistant, .user] &&
          followUpVM.comparisonMessages.first { $0.role == .assistant }?.content == "Previous assistant [邮箱]" &&
          followUpVM.comparisonMessages.last?.content == "Follow-up [邮箱]" &&
          followUpVM.comparisonMessages.allSatisfy { !$0.content.contains("@example.invalid") },
          "follow-up previews and redacts historical assistant, original user, system and new user content")
    checkImageAndContext(followUpVM.comparisonMessages, "follow-up")
    check(followUpVM.followUp.isEmpty && followUpVM.followUpHistoryCount == 1,
          "confirmed follow-up clears the editor and records one history item")

    showAnswer("Current response current@example.invalid", in: followUpVM)
    followUpVM.followUp = "  Cancel follow-up cancelled@example.invalid  "
    acceptsFollowUp = false
    let followUpMessagesBefore = followUpVM.comparisonMessages
    let followUpOutputBefore = followUpVM.output
    let followUpCompleteBefore = followUpVM.completeText
    let followUpInputBefore = followUpVM.followUp
    let followUpDiagnosticBefore = followUpVM.submissionPrivacy
    followUpVM.sendFollowUp()
    check(followUpPreviews.count == 2 && followUpPreviews.last?.messages?.count == 6,
          "cancelled follow-up previews all previous turns and the pending assistant response")
    check(followUpVM.comparisonMessages == followUpMessagesBefore && followUpVM.output == followUpOutputBefore &&
          followUpVM.completeText == followUpCompleteBefore && followUpVM.followUp == followUpInputBefore &&
          followUpVM.followUpHistoryCount == 1 && followUpVM.submissionPrivacy == followUpDiagnosticBefore,
          "cancelling follow-up preserves the conversation, output, draft and follow-up history")

    for operation in ["retry", "regenerate"] {
        settings.redactionEnabled = false
        settings.redactionRules = PrivacyRedactionRule.defaults()
        settings.systemPrompt = "Original system system@example.invalid"
        let vm = makeVM()
        showAnswer("Previous assistant assistant@example.invalid", in: vm)
        vm.followUp = "Previous question question@example.invalid"
        vm.sendFollowUp()
        showAnswer("Response being replaced", in: vm)
        var previews: [PrivacySubmissionPreview] = []
        var accepts = true
        let prepare: ResultSubmissionCoordinator.PreparationHandler = { text, submittedAction, messageBuilder in
            let preview = PrivacySubmissionPreview.prepare(text: text, action: submittedAction,
                                                           settings: settings, messageBuilder: messageBuilder)
            previews.append(preview)
            return accepts ? preview.preparedSubmission(userPreferenceEnabled: true) : nil
        }
        vm.prepareSourceSubmission = prepare
        vm.prepareFollowUpSubmission = prepare
        settings.redactionEnabled = true
        settings.systemPrompt = "Changed system changed@example.invalid"
        if operation == "retry" { vm.retry() } else { vm.regenerate() }
        check(previews.count == 1 && previews.last?.messages == vm.comparisonMessages,
              "\(operation) obtains a fresh preview and submits exactly its full conversation")
        check(previews.last?.redactionEnabled == true && previews.last?.systemPrompt == "Changed system [邮箱]" &&
              vm.comparisonMessages.map(\.role) == [.system, .user, .assistant, .user] &&
              vm.comparisonMessages.first { $0.role == .assistant }?.content == "Previous assistant [邮箱]" &&
              vm.comparisonMessages.allSatisfy { !$0.content.contains("@example.invalid") &&
                  !$0.content.contains("Response being replaced") },
              "\(operation) reapplies current redaction and system settings to history without adding the replaced answer")
        checkImageAndContext(vm.comparisonMessages, operation)

        showAnswer("Preserved response", in: vm)
        vm.thinkingText = "Preserved reasoning"
        let messagesBefore = vm.comparisonMessages
        let outputBefore = vm.output
        let completeBefore = vm.completeText
        let diagnosticBefore = vm.submissionPrivacy
        settings.redactionEnabled = false
        settings.systemPrompt = "Disabled redaction visible@example.invalid"
        accepts = false
        if operation == "retry" { vm.retry() } else { vm.regenerate() }
        check(previews.count == 2 && previews.last?.redactionEnabled == false &&
              previews.last?.systemPrompt == "Disabled redaction visible@example.invalid",
              "cancelled \(operation) previews the latest disabled-redaction preference and system prompt")
        check(vm.comparisonMessages == messagesBefore && vm.output == outputBefore && vm.completeText == completeBefore &&
              vm.thinkingText == "Preserved reasoning" && vm.submissionPrivacy == diagnosticBefore,
              "cancelling \(operation) leaves messages, visible and complete output, reasoning and diagnostics unchanged")

        settings.redactionEnabled = true
        settings.redactionRules = [PrivacyRedactionRule(name: "Updated rule", pattern: "new-system-secret",
                                                       replacement: "[updated-rule]")]
        settings.systemPrompt = "Current new-system-secret"
        accepts = true
        if operation == "retry" { vm.retry() } else { vm.regenerate() }
        check(previews.count == 3 && previews.last?.systemPrompt == "Current [updated-rule]" &&
              previews.last?.totalRedactionMatches == 1 && previews.last?.messages == vm.comparisonMessages,
              "\(operation) rebuilds its preview with changed rules after a cancelled attempt")
        checkImageAndContext(vm.comparisonMessages, "\(operation) after rule change")
    }

    check(StreamFixtureProtocol.store.requests().isEmpty && settings.history.isEmpty,
          "all preview and cancellation checks remain offline without saving successful history")
    return failures
}
