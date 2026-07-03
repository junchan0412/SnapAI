import AppKit

@MainActor
extension AppDelegate {
    func installServicesProvider() {
        NSApp.servicesProvider = self
        NSUpdateDynamicServices()
    }

    @objc(handleSnapAIService:userData:error:)
    func handleSnapAIService(_ pasteboard: NSPasteboard,
                             userData: String?,
                             error: AutoreleasingUnsafeMutablePointer<NSString?>) {
        let serviceInvocationTarget = currentCaptureTargetApp()
        let action = actionForAutomation(query: userData) ?? settings.enabledActions.first
        guard let action else {
            error.pointee = "SnapAI 还没有可用动作,请先打开设置完成配置。" as NSString
            openSettings()
            return
        }
        guard let text = serviceText(from: pasteboard) else {
            triggerCapturedSelection(action: action,
                                     preferredTarget: serviceInvocationTarget,
                                     forceDismissTransientUIBeforeCopy: true)
            return
        }
        previousApp = serviceInvocationTarget
        previousSelectionSnapshot = nil
        recordTextCaptureOutcome(TextCaptureOutcome(text: text,
                                                    method: .service,
                                                    accessibilityAttempted: false,
                                                    clipboardAttempted: false,
                                                    failureReason: nil,
                                                    pasteboardReasonCode: nil,
                                                    clipboardWaitAttempts: 0))
        runQuickInput(text: text,
                      action: action,
                      originalText: text,
                      autoReplaceEnabled: AutomationWriteBackPolicy.capturedSelection(action: action).autoReplaceEnabled,
                      captureMethod: .service,
                      sourceContext: SelectionSourceContext.make(appName: previousApp?.localizedName))
    }

    func serviceText(from pasteboard: NSPasteboard) -> String? {
        ServicePasteboardText.text(from: pasteboard)
    }
}
