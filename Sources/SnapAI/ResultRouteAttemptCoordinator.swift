import Foundation

struct ResultRunnableRouteAttempt {
    var index: Int
    var route: AIRequestRoute
    var diagnostics: AIRequestDiagnostics
    var scopedSettings: AppSettings
    var routeNote: String?
}

enum ResultRoutePreparation {
    case advance(nextIndex: Int, diagnostics: AIRequestDiagnostics, routeNote: String?)
    case unavailable(diagnostics: AIRequestDiagnostics, message: String)
    case ready(ResultRunnableRouteAttempt)
}

struct ResultRecordedRouteFailure {
    var failure: FallbackRouteFailure
    var diagnostics: AIRequestDiagnostics
}

@MainActor
final class ResultRouteAttemptCoordinator {
    private let settings: AppSettings

    init(settings: AppSettings) {
        self.settings = settings
    }

    func prepare(index: Int,
                 routes: [AIRequestRoute],
                 diagnostics: AIRequestDiagnostics) -> ResultRoutePreparation {
        let route = routes[index]
        var updatedDiagnostics = diagnostics
        let hasNextRoute = routes.indices.contains(index + 1)

        if updatedDiagnostics.shouldSkipRouteBeforeRequest(route,
                                                           autoRouteEnabled: settings.autoRouteEnabled,
                                                           hasNextRoute: hasNextRoute) {
            updatedDiagnostics.mark(route: route,
                                    status: .skipped,
                                    message: updatedDiagnostics.routeSkipMessage(for: route))
            return .advance(nextIndex: index + 1,
                            diagnostics: updatedDiagnostics,
                            routeNote: updatedDiagnostics.routeSkipSwitchNote(for: route,
                                                                             nextRoute: routes[index + 1]))
        }

        updatedDiagnostics.mark(route: route, status: .running)
        guard let scopedSettings = AIRequestRouter.scopedSettings(from: settings, route: route) else {
            updatedDiagnostics.mark(route: route,
                                    status: .skipped,
                                    message: "路由模型不可用或供应商已禁用")
            if hasNextRoute {
                return .advance(nextIndex: index + 1,
                                diagnostics: updatedDiagnostics,
                                routeNote: nil)
            }
            return .unavailable(diagnostics: updatedDiagnostics,
                                message: "路由到的模型不可用,请检查供应商和模型设置。")
        }

        return .ready(ResultRunnableRouteAttempt(index: index,
                                                 route: route,
                                                 diagnostics: updatedDiagnostics,
                                                 scopedSettings: scopedSettings,
                                                 routeNote: updatedDiagnostics.routeDisplayNote(for: route)))
    }

    func recordSuccess(attempt: ResultRunnableRouteAttempt,
                       routeStartedAt: Date,
                       firstTokenMilliseconds: Int?,
                       outputCharacterCount: Int) -> AIRequestDiagnostics {
        let elapsedMilliseconds = AIRequestAttemptDiagnostic.elapsedMilliseconds(since: routeStartedAt)
        var diagnostics = attempt.diagnostics
        diagnostics.mark(route: attempt.route,
                         status: .succeeded,
                         elapsedMilliseconds: elapsedMilliseconds,
                         outputCharacterCount: outputCharacterCount)
        RoutingMetricsStore.shared.recordSuccess(route: attempt.route,
                                                 elapsedMilliseconds: elapsedMilliseconds,
                                                 firstTokenMilliseconds: firstTokenMilliseconds)
        return diagnostics
    }

    func recordFailure(error: Error,
                       outputText: String,
                       thinkingText: String,
                       routeStartedAt: Date,
                       routes: [AIRequestRoute],
                       attempt: ResultRunnableRouteAttempt,
                       firstTokenMilliseconds: Int?) -> ResultRecordedRouteFailure {
        let failure = FallbackRunner.routeFailure(
            error: error,
            outputText: outputText,
            thinkingText: thinkingText,
            routeStartedAt: routeStartedAt,
            route: attempt.route,
            routes: routes,
            index: attempt.index,
            diagnostics: attempt.diagnostics,
            fallbackEnabled: settings.fallbackEnabled
        )
        let diagnostics = failure.diagnosticsMarkingFailure(attempt.diagnostics,
                                                            route: attempt.route)
        RoutingMetricsStore.shared.recordFailure(route: attempt.route,
                                                 elapsedMilliseconds: failure.elapsedMilliseconds,
                                                 firstTokenMilliseconds: firstTokenMilliseconds,
                                                 reason: failure.safeErrorMessage)
        return ResultRecordedRouteFailure(failure: failure,
                                          diagnostics: diagnostics)
    }
}
