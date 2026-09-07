import Foundation

package struct FallbackRouteFailure {
    package var safeErrorMessage: String
    package var outputCharacterCount: Int
    package var receivedCharacterCount: Int
    package var elapsedMilliseconds: Int
    package var nextRoute: AIRequestRoute?
    package var decision: AIRequestFallbackDecision

    package func diagnosticsMarkingFailure(_ diagnostics: AIRequestDiagnostics,
                                   route: AIRequestRoute) -> AIRequestDiagnostics {
        var copy = diagnostics
        copy.mark(route: route,
                  status: .failed,
                  message: safeErrorMessage,
                  elapsedMilliseconds: elapsedMilliseconds,
                  outputCharacterCount: outputCharacterCount,
                  fallbackDecision: decision)
        return copy
    }
}

package enum FallbackRunner {
    package static func routeFailure(error: Error,
                             outputText: String,
                             thinkingText: String = "",
                             routeStartedAt: Date,
                             route: AIRequestRoute,
                             routes: [AIRequestRoute],
                             index: Int,
                             diagnostics: AIRequestDiagnostics,
                             fallbackEnabled: Bool) -> FallbackRouteFailure {
        let safeErrorMessage = SensitiveTextSanitizer.sanitizedMessage(error.localizedDescription)
        let outputCharacterCount = outputText.count
        let receivedCharacterCount = outputText.count + thinkingText.count
        let nextRoute = routes.indices.contains(index + 1) ? routes[index + 1] : nil
        let decision = AIRequestFallbackDecision.decide(
            fallbackEnabled: fallbackEnabled,
            hasNextRoute: nextRoute != nil,
            outputCharacterCount: outputCharacterCount,
            requiresCloudFallbackConfirmation: diagnostics.requiresCloudFallbackConfirmation(from: route,
                                                                                              to: nextRoute)
        )
        return FallbackRouteFailure(
            safeErrorMessage: safeErrorMessage,
            outputCharacterCount: outputCharacterCount,
            receivedCharacterCount: receivedCharacterCount,
            elapsedMilliseconds: AIRequestAttemptDiagnostic.elapsedMilliseconds(since: routeStartedAt),
            nextRoute: nextRoute,
            decision: decision
        )
    }
}
