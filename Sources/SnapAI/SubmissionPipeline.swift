import AppKit
import SnapAILogic

/// 提交装配:取词 → 脱敏预览 → 隐私确认 → 启动请求。
///
/// 从 AppDelegate 抽出,使触发流程可独立阅读与测试;AppDelegate 只保留
/// 薄编排(triggerAction/runQuickInput),装配细节全部在此。
@MainActor
final class SubmissionPipeline {
    private weak var host: AppDelegate?

    init(host: AppDelegate) {
        self.host = host
    }

    /// 选中文字触发:捕获 → 装配 → 启动结果面板。返回 true 表示已启动请求。
    func triggerCapturedSelection(action: AIAction,
                                  preferredTarget: NSRunningApplication? = nil,
                                  forceDismissTransientUIBeforeCopy: Bool = false) {
        guard let host else { return }
        // #bug2 代际令牌:新触发使所有未完成的旧捕获回调失效,避免过期空结果弹「未检测到选中文字」。
        host.captureGeneration += 1
        let gen = host.captureGeneration
        host.previousApp = host.captureTargetApp(preferredTarget: preferredTarget)
        host.previousSelectionSnapshot = nil
        host.previousCaptureMethod = nil
        TextCapture.captureDetailed(preferAX: host.settings.useAXFirst,
                                    targetApp: host.previousApp,
                                    forceDismissTransientUIBeforeCopy: forceDismissTransientUIBeforeCopy) { [weak self, weak host] outcome in
            guard let self, let host else { return }
            // 过期捕获丢弃:已有更新的触发覆盖了本次。
            guard gen == host.captureGeneration else { return }
            // 已有动作在跑则丢弃本次空结果,避免在正常生成中弹「未检测到选中文字」。
            guard !host.resultVM.isStreaming else { return }
            let text = outcome.usableText
            guard let text = text, !text.isEmpty else {
                host.recordTextCaptureOutcome(outcome)
                host.showNoSelectionNotice(action: action)
                return
            }
            host.recordTextCaptureOutcome(outcome)
            host.previousSelectionSnapshot = TextCapture.recentSelectionSnapshot(matching: text)
            host.previousCaptureMethod = outcome.method
            let sourceContext = SelectionSourceContext.make(appName: host.previousApp?.localizedName)
            guard let prepared = self.prepareTextForSubmission(text,
                                                               action: action,
                                                               imageData: nil,
                                                               sourceContext: sourceContext) else { return }
            host.resultVM.start(text: prepared.text,
                                originalText: text,
                                action: action,
                                submissionPrivacy: prepared.diagnostic,
                                autoReplaceEnabled: AutomationWriteBackPolicy.capturedSelection(action: action).autoReplaceEnabled,
                                captureMethod: outcome.method,
                                sourceContext: sourceContext,
                                preparedMessages: prepared.messages)
            host.panelController.show()
        }
    }

    /// 快捷提问/自动化触发:装配文本(含图片)并启动请求。返回 false 表示隐私确认被取消。
    @discardableResult
    func runQuickInput(text: String,
                       action: AIAction,
                       originalText: String? = nil,
                       imageData: Data? = nil,
                       imageMimeType: String = "image/png",
                       retainedImageData: Data? = nil,
                       retainedImageMimeType: String = "image/png",
                       autoReplaceEnabled: Bool = false,
                       captureMethod: TextCaptureMethod? = nil,
                       sourceContext: SelectionSourceContext? = nil) -> Bool {
        guard let host else { return false }
        guard let prepared = prepareTextForSubmission(text,
                                                      action: action,
                                                      imageData: imageData,
                                                      imageMimeType: imageMimeType,
                                                      sourceContext: sourceContext) else { return false }
        host.quickInput.hide()
        host.resultVM.start(text: prepared.text,
                            originalText: originalText,
                            action: action,
                            imageData: imageData,
                            imageMimeType: imageMimeType,
                            retainedImageData: retainedImageData,
                            retainedImageMimeType: retainedImageMimeType,
                            submissionPrivacy: prepared.diagnostic,
                            autoReplaceEnabled: autoReplaceEnabled,
                            captureMethod: captureMethod,
                            sourceContext: sourceContext,
                            preparedMessages: prepared.messages)
        host.panelController.show()
        return true
    }

    func prepareTextForSubmission(_ text: String,
                                  action: AIAction,
                                  imageData: Data? = nil,
                                  userPromptOverride: String? = nil,
                                  imageMimeType: String = "image/png",
                                  sourceContext: SelectionSourceContext? = nil,
                                  messageBuilder: ((String) -> [ChatMessage])? = nil) -> PrivacyPreparedSubmission? {
        guard let host else { return nil }
        let settings = host.settings
        let preview = PrivacySubmissionPreview.prepare(text: text, action: action, settings: settings) { sourceText in
            if let messageBuilder { return messageBuilder(sourceText) }
            var messages = RequestSession.initialMessages(settings: settings,
                                                          action: action,
                                                          targetLanguage: action.targetLanguage,
                                                          sourceText: sourceText,
                                                          imageData: imageData,
                                                          imageMimeType: imageMimeType,
                                                          sourceContext: sourceContext).messages
            if userPromptOverride != nil, let index = messages.lastIndex(where: { $0.role == .user }) {
                messages[index].content = sourceText
            }
            return messages
        }
        let previewRequirement = preview.previewRequirement(userPreferenceEnabled: settings.privacyPreviewEnabled)
        let prepared = preview.preparedSubmission(userPreferenceEnabled: settings.privacyPreviewEnabled)
        guard previewRequirement.isRequired else { return prepared }
        return confirmPrivacyPreview(preview, requirement: previewRequirement) ? prepared : nil
    }

    func confirmPrivacyPreview(_ preview: PrivacySubmissionPreview,
                               requirement: PrivacyPreviewRequirement) -> Bool {
        let alert = NSAlert()
        alert.messageText = "发送给 AI 前确认"
        alert.informativeText = requirement.confirmationMessage(redactionEnabled: preview.redactionEnabled)
        alert.alertStyle = .informational
        alert.addButton(withTitle: "发送")
        alert.addButton(withTitle: "取消")

        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 560, height: 240))
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder
        let textView = NSTextView(frame: scroll.bounds)
        textView.isEditable = false
        textView.isSelectable = true
        textView.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        textView.string = preview.contentText(previewRequirement: requirement)
        textView.textContainerInset = NSSize(width: 8, height: 8)
        scroll.documentView = textView
        alert.accessoryView = scroll
        NSApp.activate(ignoringOtherApps: true)
        return alert.runModal() == .alertFirstButtonReturn
    }
}
