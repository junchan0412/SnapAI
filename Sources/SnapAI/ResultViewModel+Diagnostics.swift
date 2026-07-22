import Foundation
import SnapAILogic

@MainActor
extension ResultViewModel {
    var privacyProtectionStatusText: String? {
        submissionPrivacy?.protectionSummaryText
    }
    var contentExportProtectionEnabled: Bool {
        submissionPrivacy?.contentExportProtectionEnabled == true
    }
    var errorRecoverySuggestionText: String? {
        AIRequestDiagnostics.visibleErrorRecoverySuggestion(diagnostics: requestDiagnostics,
                                                            errorMessage: errorMessage)
    }
    var errorRecoveryCode: String? {
        AIRequestDiagnostics.visibleErrorRecoveryCode(diagnostics: requestDiagnostics,
                                                      errorMessage: errorMessage)
    }
    var errorRecoverySettingsDescriptor: ResultRecoverySettingsDescriptor {
        ResultRecoveryCommand.openAISettingsDescriptor(recoveryCode: errorRecoveryCode)
    }
    var errorRecoveryRetryDescriptor: ResultRecoveryRetryDescriptor {
        ResultRecoveryCommand.retryDescriptor(recoveryCode: errorRecoveryCode)
    }
    var errorRecoveryPrimaryAction: ResultRecoveryPrimaryAction {
        ResultRecoveryCommand.primaryAction(recoveryCode: errorRecoveryCode)
    }
    var requestHealthStatusText: String {
        requestDiagnostics?.healthStatusLine ?? "none"
    }
    var routeExplanationText: String? {
        requestDiagnostics?.visibleRouteExplanation
    }
    var routeStatusTitle: String {
        requestDiagnostics?.visibleRouteStatusTitle ?? (settings.autoRouteEnabled ? "自动路由" : "固定模型")
    }
    var activeContextSummaryText: String? {
        guard settings.contextStatusSummary.hasActiveContext else { return nil }
        let summary = settings.contextStatusSummary
        return "\(summary.activeProfileName) · \(summary.activeContextCharacterCount) 字"
    }
}
