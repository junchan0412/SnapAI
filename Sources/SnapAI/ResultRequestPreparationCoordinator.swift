struct ResultRequestPreparationInput {
    var action: AIAction
    var sourceText: String
    var history: [ChatMessage]
    var explicitHasImage: Bool
    var captureMethod: TextCaptureMethod?
    var sourceContext: SelectionSourceContext?
    var submissionPrivacy: PrivacySubmissionDiagnostic?
}

struct PreparedResultRequest {
    var routes: [AIRequestRoute]
    var diagnostics: AIRequestDiagnostics
    var submissionPrivacy: PrivacySubmissionDiagnostic?
}

enum ResultRequestPreparation {
    case ready(PreparedResultRequest)
    case unavailable(message: String,
                     diagnostics: AIRequestDiagnostics,
                     submissionPrivacy: PrivacySubmissionDiagnostic?)
}

@MainActor
final class ResultRequestPreparationCoordinator {
    private let settings: AppSettings

    init(settings: AppSettings) {
        self.settings = settings
    }

    func prepare(_ input: ResultRequestPreparationInput) -> ResultRequestPreparation {
        let submissionPrivacy = refreshedSubmissionPrivacy(input.submissionPrivacy,
                                                           history: input.history)
        let contextDiagnostic = AIRequestContextDiagnostic.make(settings: settings)
        let requestHasImage = input.explicitHasImage || input.history.contains { $0.imageData != nil }
        let payloadDiagnostic = AIRequestPayloadDiagnostic.make(messages: input.history,
                                                                explicitHasImage: requestHasImage)
        let actionPipeline = ActionPipelineDiagnostic.make(action: input.action,
                                                           settings: settings,
                                                           hasImage: requestHasImage,
                                                           captureMethod: input.captureMethod,
                                                           sourceKind: input.sourceContext?.kind)
        let routes = AIRequestRouter.candidates(
            settings: settings,
            action: input.action,
            sourceText: input.sourceText,
            hasImage: requestHasImage,
            routingTextCharacterCount: payloadDiagnostic.textCharacterCount,
            routingMetrics: RoutingMetricsStore.shared.snapshot()
        )

        let diagnostics = makeDiagnostics(input: input,
                                          submissionPrivacy: submissionPrivacy,
                                          requestHasImage: requestHasImage,
                                          actionPipeline: actionPipeline,
                                          contextDiagnostic: contextDiagnostic,
                                          payloadDiagnostic: payloadDiagnostic,
                                          routes: routes)
        guard !routes.isEmpty else {
            return .unavailable(
                message: "没有可用的 AI 供应商或模型,请在设置中启用至少一个模型。",
                diagnostics: diagnostics,
                submissionPrivacy: submissionPrivacy
            )
        }
        return .ready(PreparedResultRequest(routes: routes,
                                           diagnostics: diagnostics,
                                           submissionPrivacy: submissionPrivacy))
    }

    private func refreshedSubmissionPrivacy(_ privacy: PrivacySubmissionDiagnostic?,
                                            history: [ChatMessage]) -> PrivacySubmissionDiagnostic? {
        guard let privacy else { return nil }
        let counts = RequestSession.payloadCharacterCounts(messages: history)
        return privacy.withPayloadCharacterCounts(finalUserPromptCharacterCount: counts.finalUserPrompt,
                                                  systemPromptCharacterCount: counts.systemPrompt)
    }

    private func makeDiagnostics(input: ResultRequestPreparationInput,
                                 submissionPrivacy: PrivacySubmissionDiagnostic?,
                                 requestHasImage: Bool,
                                 actionPipeline: ActionPipelineDiagnostic,
                                 contextDiagnostic: AIRequestContextDiagnostic,
                                 payloadDiagnostic: AIRequestPayloadDiagnostic,
                                 routes: [AIRequestRoute]) -> AIRequestDiagnostics {
        let unavailabilitySummary = routes.isEmpty
            ? AIRequestDiagnostics.noCandidateRouteReasonSummary(providers: settings.providers)
            : "not-checked"
        let unavailabilityRecovery = routes.isEmpty
            ? AIRequestDiagnostics.noCandidateRouteRecoverySuggestion(providers: settings.providers)
            : ""
        return AIRequestDiagnostics(
            actionName: input.action.name,
            actionRequiresReasoning: input.action.thinkingMode,
            sourceCharacterCount: input.sourceText.count,
            hasImage: requestHasImage,
            fallbackEnabled: settings.fallbackEnabled,
            autoRouteEnabled: settings.autoRouteEnabled,
            routingPreference: settings.routingPreference,
            candidateCount: routes.count,
            actionPipeline: actionPipeline,
            context: contextDiagnostic,
            payload: payloadDiagnostic,
            submissionPrivacy: submissionPrivacy,
            candidateRoutes: routes,
            candidateUnavailabilitySummary: unavailabilitySummary,
            candidateUnavailabilityRecoverySuggestion: unavailabilityRecovery
        )
    }
}
