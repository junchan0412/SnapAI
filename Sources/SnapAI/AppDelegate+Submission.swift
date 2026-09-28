import AppKit
import SnapAILogic

/// 触发流程的薄转发:取词、脱敏预览、隐私确认、启动请求的装配细节
/// 全在 `SubmissionPipeline`,这里只保留各扩展与 coordinator 的调用入口。
extension AppDelegate {
    func triggerAction(id: String) {
        guard let action = settings.enabledActions.first(where: { $0.id == id }) else { return }
        triggerCapturedSelection(action: action)
    }

    func triggerCapturedSelection(action: AIAction,
                                  preferredTarget: NSRunningApplication? = nil,
                                  forceDismissTransientUIBeforeCopy: Bool = false) {
        submissionPipeline.triggerCapturedSelection(action: action,
                                                    preferredTarget: preferredTarget,
                                                    forceDismissTransientUIBeforeCopy: forceDismissTransientUIBeforeCopy)
    }

    func captureTargetApp(preferredTarget: NSRunningApplication?) -> NSRunningApplication? {
        guard preferredTarget != nil else {
            return currentCaptureTargetApp()
        }
        let frontmost = NSWorkspace.shared.frontmostApplication
        rememberExternalFrontmostApp(frontmost)
        return CaptureTargetResolver.resolveDeferred(serviceInvocation: preferredTarget,
                                                     frontmost: frontmost,
                                                     lastExternal: lastExternalFrontmostApp)
    }

    @discardableResult
    func runQuickInput(text: String,
                       action: AIAction,
                       originalText: String? = nil,
                       imageData: Data? = nil,
                       imageMimeType: String = "image/png",
                       autoReplaceEnabled: Bool = false,
                       captureMethod: TextCaptureMethod? = nil,
                       sourceContext: SelectionSourceContext? = nil) -> Bool {
        submissionPipeline.runQuickInput(text: text,
                                         action: action,
                                         originalText: originalText,
                                         imageData: imageData,
                                         imageMimeType: imageMimeType,
                                         autoReplaceEnabled: autoReplaceEnabled,
                                         captureMethod: captureMethod,
                                         sourceContext: sourceContext)
    }

    func prepareTextForSubmission(_ text: String,
                                  action: AIAction,
                                  imageData: Data?,
                                  userPromptOverride: String? = nil) -> PrivacyPreparedSubmission? {
        submissionPipeline.prepareTextForSubmission(text,
                                                    action: action,
                                                    imageData: imageData,
                                                    userPromptOverride: userPromptOverride)
    }

    func confirmPrivacyPreview(_ preview: PrivacySubmissionPreview,
                               requirement: PrivacyPreviewRequirement) -> Bool {
        submissionPipeline.confirmPrivacyPreview(preview, requirement: requirement)
    }
}
