import AppKit
import ApplicationServices
import Carbon.HIToolbox
import Combine
import Foundation

#if !SNAPAI_MANUAL_TEST_MAIN
  @testable import SnapAILogic
#endif

func testTextReplacementPreparationDelay() {
  expect(
    TextEditTiming.replacementPreparationDelay(
      hasAccessibleSelection: true,
      restoredSnapshot: false,
      assumeSelectionIsPreserved: false) == 0.03,
    "pastes immediately when AX can still see the selection")
  expect(
    TextEditTiming.replacementPreparationDelay(
      hasAccessibleSelection: false,
      restoredSnapshot: true,
      assumeSelectionIsPreserved: false) == 0.08,
    "allows a restored AX range to settle before replacement")
  expect(
    TextEditTiming.replacementPreparationDelay(
      hasAccessibleSelection: false,
      restoredSnapshot: false,
      assumeSelectionIsPreserved: true) == 0.05,
    "clipboard and service captures trust the preserved target selection instead of keyboard reselection"
  )
  expect(
    TextEditTiming.replacementPreparationDelay(
      hasAccessibleSelection: false,
      restoredSnapshot: false,
      assumeSelectionIsPreserved: false) == 0.03,
    "does not synthesize Shift-Left reselection when no reliable selection handle exists")
}

func testResultContentRenderModeAvoidsStreamingMarkdownReparse() {
    expect(ResultContentRenderMode.resolve(text: "", isStreaming: false) == .empty,
           "empty completed results do not build a content renderer")
    expect(ResultContentRenderMode.resolve(text: "", isStreaming: true) == .waiting,
           "empty streaming results show a lightweight waiting state")
    expect(ResultContentRenderMode.resolve(text: "# partial", isStreaming: true) == .streamingText,
           "partial streaming output stays plain text instead of reparsing markdown on every tick")
    expect(ResultContentRenderMode.resolve(text: "# complete", isStreaming: false) == .markdown,
           "completed output switches to markdown rendering")
    expect(ResultAutoScrollPolicy.shouldScroll(lastScrollTime: 1,
                                               currentTime: 1.01,
                                               isStreaming: true) == false,
           "streaming auto-scroll suppresses updates above the 20 Hz budget")
    expect(ResultAutoScrollPolicy.shouldScroll(lastScrollTime: 1,
                                               currentTime: 1.0 + ResultAutoScrollPolicy.streamingMinimumInterval,
                                               isStreaming: true),
           "streaming auto-scroll advances after its frame budget")
    expect(ResultAutoScrollPolicy.shouldScroll(lastScrollTime: 1,
                                               currentTime: 1.001,
                                               isStreaming: false),
           "completed output always receives a final bottom alignment")
}

func testMarkdownPresentationBuildsBlocksAndRejectsStaleRefreshes() {
    let presentation = MarkdownPresentationBuilder.build("""
    # 标题

    正文 **加粗**

    - 项目一
    - 项目二

    1. 第一步
    2. 第二步

    > 引用

    ```swift
    let value = 1
    ```
    """)

    expect(presentation.blocks.count == 6,
           "markdown presentation builds one immutable snapshot for all block types")
    if case .heading(let level, let content) = presentation.blocks[0] {
        expect(level == 1 && String(content.characters) == "标题",
               "markdown presentation preserves heading level and inline content")
    } else {
        expect(false, "markdown presentation starts with a heading")
    }
    if case .paragraph(let content) = presentation.blocks[1] {
        expect(String(content.characters) == "正文 加粗",
               "markdown inline parsing is completed before SwiftUI rendering")
    } else {
        expect(false, "markdown presentation includes a paragraph")
    }
    if case .bullet(let items) = presentation.blocks[2] {
        expect(items.map { String($0.characters) } == ["项目一", "项目二"],
               "markdown presentation groups bullet items")
    } else {
        expect(false, "markdown presentation includes a bullet list")
    }
    if case .ordered(let items) = presentation.blocks[3] {
        expect(items.map { String($0.characters) } == ["第一步", "第二步"],
               "markdown presentation groups ordered items")
    } else {
        expect(false, "markdown presentation includes an ordered list")
    }
    if case .quote(let content) = presentation.blocks[4] {
        expect(String(content.characters) == "引用",
               "markdown presentation preserves quote content")
    } else {
        expect(false, "markdown presentation includes a quote")
    }
    if case .code(let code, let language) = presentation.blocks[5] {
        expect(code == "let value = 1" && language == "swift",
               "markdown presentation preserves fenced code and language")
    } else {
        expect(false, "markdown presentation includes a code block")
    }

    expect(MarkdownPresentationBuilder.build("").blocks.isEmpty,
           "empty markdown produces an empty presentation")
    expect(MarkdownPresentationRefreshPolicy.shouldPublish(requestGeneration: 3,
                                                           currentGeneration: 3,
                                                           requestedText: "new",
                                                           currentText: "new"),
           "matching markdown generations publish")
    expect(!MarkdownPresentationRefreshPolicy.shouldPublish(requestGeneration: 2,
                                                            currentGeneration: 3,
                                                            requestedText: "old",
                                                            currentText: "new"),
           "stale markdown generations cannot replace a newer result")
}

func testResultLiveOutputStatesPublishIndependently() {
    let output = ResultOutputState()
    let thinking = ResultThinkingState()
    var outputChanges = 0
    var thinkingChanges = 0
    let outputSubscription = output.objectWillChange.sink { outputChanges += 1 }
    let thinkingSubscription = thinking.objectWillChange.sink { thinkingChanges += 1 }

    expect(output.replace(with: "partial"), "new output text is accepted")
    expect(outputChanges == 1, "output state publishes its own streaming update")
    expect(thinkingChanges == 0, "output updates do not invalidate thinking observers")
    expect(!output.replace(with: "partial"), "identical output text is ignored")
    expect(outputChanges == 1, "identical output does not publish another update")
    expect(output.append(" result"), "incremental output text is appended")
    expect(output.text == "partial result", "incremental output preserves existing text")
    expect(outputChanges == 2, "incremental output publishes one leaf update")
    expect(!output.append(""), "empty output chunks are ignored")
    expect(outputChanges == 2, "empty output chunks do not publish")

    expect(thinking.replace(with: "reasoning"), "new thinking text is accepted")
    expect(outputChanges == 2, "thinking updates do not invalidate output observers")
    expect(thinkingChanges == 1, "thinking state publishes its own update")
    expect(!thinking.replace(with: "reasoning"), "identical thinking text is ignored")
    expect(thinkingChanges == 1, "identical thinking does not publish another update")

    withExtendedLifetime((outputSubscription, thinkingSubscription)) {}
}

func testResultOperationFeedbackAndExportFilenameAreActionable() {
    let success = ResultOperationFeedback.success("结果已复制")
    let repeated = ResultOperationFeedback.success("结果已复制")
    let warning = ResultOperationFeedback.warning("导出失败")

    expect(success.kind == .success && success.systemImage == "checkmark.circle.fill",
           "successful result operations use an affirmative feedback icon")
    expect(warning.kind == .warning && warning.systemImage == "exclamationmark.triangle.fill",
           "failed result operations use a warning feedback icon")
    expect(warning.dismissDelaySeconds > success.dismissDelaySeconds,
           "failure feedback remains visible longer than success feedback")
    expect(success.id != repeated.id,
           "repeating the same operation creates a fresh feedback event")

    expect(ResultExportFilename.suggested(actionName: "总结/报告:\n测试", timestamp: -8)
           == "总结-报告-测试-0.md",
           "export filenames remove path separators, controls, and negative timestamps")
    expect(ResultExportFilename.suggested(actionName: " \n ", timestamp: 42)
           == "SnapAI-42.md",
           "empty sanitized action names use a clear export fallback")
    let longName = ResultExportFilename.suggested(actionName: String(repeating: "a", count: 100),
                                                  timestamp: 1)
    expect(longName == "\(String(repeating: "a", count: 64))-1.md",
           "export filenames cap user-controlled action names")
    expect(ResultExportFilename.suggested(actionName: "SnapAI-History", timestamp: 123)
           == "SnapAI-History-123.md",
           "history exports reuse the safe timestamped markdown filename policy")
}

func testResultCompletionStatePublishesOneDeduplicatedSnapshot() {
    let state = ResultCompletionState()
    var changes = 0
    let subscription = state.objectWillChange.sink { changes += 1 }
    let metrics = ResultCompletionMetrics(elapsed: 1.25, characterCount: 320)

    expect(state.replace(with: metrics), "new completion metrics are accepted")
    expect(changes == 1, "elapsed and character count publish as one snapshot")
    expect(state.metrics == metrics, "completion state keeps both metrics together")
    expect(!state.replace(with: metrics), "identical completion metrics are ignored")
    expect(changes == 1, "identical completion metrics do not republish")
    expect(state.reset(), "non-empty completion state resets")
    expect(changes == 2, "reset publishes one empty snapshot")
    expect(!state.reset(), "already-empty completion state ignores duplicate reset")
    expect(changes == 2, "duplicate reset does not republish")

    let diagnostics = ResultDiagnosticTextSnapshot(fullText: "full", briefText: "brief")
    expect(diagnostics != .empty && diagnostics.fullText == "full" && diagnostics.briefText == "brief",
           "diagnostic text snapshot keeps full and brief variants in one value")
    withExtendedLifetime(subscription) {}
}

func testResultCompletionLifecycleRunsOnceAndResetsCleanly() {
    var lifecycle = ResultCompletionLifecycle()
    expect(!lifecycle.isFinished && !lifecycle.isHistorySaved,
           "new completion lifecycle starts clean")
    expect(lifecycle.beginCompletion(), "first completion attempt is accepted")
    expect(!lifecycle.beginCompletion(), "duplicate completion attempt is rejected")
    lifecycle.updateHistorySaved(true)
    lifecycle.updateHistorySaved(false)
    expect(lifecycle.isHistorySaved, "history saved state is monotonic within one completion")
    lifecycle.reset()
    expect(!lifecycle.isFinished && !lifecycle.isHistorySaved,
           "new request resets completion and history guards together")
    expect(lifecycle.beginCompletion(), "completion is accepted again after reset")
}

func testScreenCaptureTemporaryFileUsesUniqueUnpredictablePath() {
  let directory = URL(fileURLWithPath: "/tmp/snapai-test-temp", isDirectory: true)
  let firstUUID = UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!
  let secondUUID = UUID(uuidString: "11111111-2222-3333-4444-555555555555")!
  let first = ScreenCaptureTemporaryFile.makeURL(
    temporaryDirectory: directory,
    uuid: firstUUID)
  let second = ScreenCaptureTemporaryFile.makeURL(
    temporaryDirectory: directory,
    uuid: secondUUID)

  expect(
    first.deletingLastPathComponent().path == directory.path,
    "screen capture temporary files stay inside the supplied temporary directory")
  expect(
    first.pathExtension == "png",
    "screen capture temporary files use png extension for screencapture output")
  expect(
    first.lastPathComponent == "snapai-screen-\(firstUUID.uuidString).png",
    "screen capture temporary file names include an unpredictable UUID")
  expect(
    first != second,
    "screen capture temporary file names differ for different UUIDs")
  expect(
    !first.lastPathComponent.contains("snapai_ss_"),
    "screen capture temporary file names no longer use the old timestamp prefix")
}

func testScreenCapturePermissionPreflightAndRecoveryMessage() {
  expect(
    ScreenCapturePermission.isGranted(preflight: { true }),
    "screen capture permission helper reports granted preflight")
  expect(
    !ScreenCapturePermission.isGranted(preflight: { false }),
    "screen capture permission helper reports missing preflight")
  expect(
    ScreenCapturePermission.recoveryMessage.contains("屏幕录制"),
    "screen capture permission recovery message names the required permission")
  expect(
    ScreenCapturePermission.recoveryMessage.contains("允许 SnapAI"),
    "screen capture permission recovery message tells the user what to allow")
}

func testScreenCaptureFailureDiagnosticsAreShareableAndPathFree() {
  let diagnostic = ScreenCaptureFailureDiagnostic(
    reason: .commandFailed(1),
    permissionGranted: true,
    output: ScreenCaptureOutputSnapshot(exists: false, byteCount: nil)
  )

  expect(
    diagnostic.userMessage.contains("退出码 1"),
    "screen capture command failures explain the exit status")
  expect(
    diagnostic.userMessage.contains("屏幕录制"),
    "screen capture command failures include the recovery permission")
  expect(
    diagnostic.shareableText.contains("SnapAI Screen Capture Diagnostic"),
    "screen capture diagnostics identify their source")
  expect(
    diagnostic.shareableText.contains("Reason: command-failed"),
    "screen capture diagnostics include a stable reason code")
  expect(
    diagnostic.shareableText.contains("Command Exit Status: 1"),
    "screen capture diagnostics include the command exit status")
  expect(
    diagnostic.shareableText.contains("Output File Exists: no"),
    "screen capture diagnostics include output existence")
  expect(
    !diagnostic.shareableText.contains("/Users/"),
    "screen capture diagnostics avoid sharing local file paths")
}

func testScreenCaptureFailureDiagnosticsDescribeOutputProblems() {
  let emptyOutput = ScreenCaptureFailureDiagnostic(
    reason: .outputEmpty,
    permissionGranted: true,
    output: ScreenCaptureOutputSnapshot(exists: true, byteCount: 0)
  )
  let invalidImage = ScreenCaptureFailureDiagnostic(
    reason: .invalidImage,
    permissionGranted: true,
    output: ScreenCaptureOutputSnapshot(exists: true, byteCount: 128)
  )
  let optimizedTooLarge = ScreenCaptureFailureDiagnostic(
    reason: .optimizedImageTooLarge,
    permissionGranted: true,
    output: ScreenCaptureOutputSnapshot(exists: true, byteCount: 9_000_000)
  )

  expect(
    emptyOutput.userMessage.contains("空图片文件"),
    "screen capture diagnostics explain empty output files")
  expect(
    emptyOutput.shareableText.contains("Output File Bytes: 0"),
    "screen capture diagnostics include empty output size")
  expect(
    invalidImage.userMessage.contains("无法解析"),
    "screen capture diagnostics explain invalid image output")
  expect(
    invalidImage.shareableText.contains("Output File Bytes: 128"),
    "screen capture diagnostics include invalid output size")
  expect(
    optimizedTooLarge.userMessage.contains("压缩后仍超过"),
    "screen capture diagnostics explain images that remain too large after optimization")
  expect(
    optimizedTooLarge.shareableText.contains("Reason: optimized-image-too-large"),
    "screen capture diagnostics expose a stable reason code for encoded payload overflow")
}

func testWriteBackUndoRecordAvailability() {
  let record = TextWriteBackRecordState(
    targetName: nil,
    targetState: .missing,
    originalText: "旧文本",
    replacementText: "新文本")
  expect(record.isUndoAvailable, "allows recent write-back undo")
  expect(record.undoState() == .available, "reports available undo state")
  expect(record.targetState == .missing, "reports missing target state for legacy records")
  expect(record.undoTitle == "撤销上次替换到 原应用", "uses generic replace title without target app")
  expect(
    record.diagnosticSummary.contains("undo=available"), "reports available undo in diagnostics")
  expect(
    record.diagnosticSummary.contains("targetState=missing"),
    "reports missing target state in diagnostics")
  expect(record.diagnosticSummary.contains("operation=replace"), "reports replace operation")
  expect(record.diagnosticSummary.contains("originalChars=3"), "reports original length")
  expect(record.diagnosticSummary.contains("replacementChars=3"), "reports replacement length")
  expect(
    record.recoverySuggestion == "可通过命令面板或菜单撤销上次写回",
    "available write-back records explain how to undo")
  expect(
    record.diagnosticSummary.contains("recovery=可通过命令面板或菜单撤销上次写回"),
    "write-back record diagnostics include recovery guidance")
  expect(!record.diagnosticSummary.contains("旧文本"), "does not leak original text")
  expect(!record.diagnosticSummary.contains("新文本"), "does not leak replacement text")

  let append = TextWriteBackRecordState(
    targetName: nil,
    targetState: .missing,
    operation: .append,
    originalText: "",
    replacementText: "\n追加内容")
  expect(append.isUndoAvailable, "allows recent append undo without original text")
  expect(append.undoTitle == "撤销上次追加到 原应用", "uses generic append title without target app")
  expect(append.diagnosticSummary.contains("operation=append"), "reports append operation")
  expect(!append.diagnosticSummary.contains("追加内容"), "does not leak appended text")

  let expired = TextWriteBackRecordState(
    targetName: nil,
    targetState: .missing,
    originalText: "旧文本",
    replacementText: "新文本",
    createdAt: Date(timeIntervalSinceNow: -TextWriteBackRecordState.expirationInterval - 1))
  expect(!expired.isUndoAvailable, "expires stale write-back undo records")
  expect(expired.undoState() == .expired, "reports expired undo state")
  expect(expired.diagnosticSummary.contains("undo=expired"), "reports expired undo in diagnostics")
  expect(
    expired.recoverySuggestion == "撤销窗口已过期; 请在目标应用中手动恢复",
    "expired write-back records explain manual recovery")
  expect(
    expired.diagnosticSummary.contains("recovery=撤销窗口已过期; 请在目标应用中手动恢复"),
    "expired write-back diagnostics include recovery guidance")

  let empty = TextWriteBackRecordState(
    targetName: nil,
    targetState: .missing,
    originalText: "",
    replacementText: "新文本")
  expect(!empty.isUndoAvailable, "rejects empty undo records")
  expect(empty.undoState() == .missingOriginal, "reports missing original undo state")
  expect(
    empty.recoverySuggestion == "缺少原文快照; 请在目标应用中手动恢复",
    "missing-original write-back records explain manual recovery")

  let missingReplacement = TextWriteBackRecordState(
    targetName: nil,
    targetState: .missing,
    originalText: "旧文本",
    replacementText: "")
  expect(!missingReplacement.isUndoAvailable, "rejects missing replacement undo records")
  expect(
    missingReplacement.undoState() == .missingReplacement, "reports missing replacement undo state")
  expect(
    missingReplacement.recoverySuggestion == "缺少写回内容; 请重新复制结果或手动恢复",
    "missing-replacement write-back records explain recovery")

  expect(
    TextWriteBackStateResolver.targetState(
      processIdentifier: nil,
      isTerminated: false,
      currentProcessIdentifier: 10) == .missing,
    "resolves missing write-back targets")
  expect(
    TextWriteBackStateResolver.targetState(
      processIdentifier: 11,
      isTerminated: true,
      currentProcessIdentifier: 10) == .terminated,
    "resolves terminated write-back targets")
  expect(
    TextWriteBackStateResolver.targetState(
      processIdentifier: 10,
      isTerminated: false,
      currentProcessIdentifier: 10) == .currentApp,
    "resolves current-app write-back targets")
  expect(
    TextWriteBackStateResolver.targetState(
      processIdentifier: 11,
      isTerminated: false,
      currentProcessIdentifier: 10) == .running,
    "resolves running external write-back targets")
}

func testWriteBackFallbackDiagnosticSummarizesFailureWithoutContent() {
  expect(
    WriteBackCompatibility.profile(for: "Google Chrome")?.displayName == "浏览器",
    "writeback compatibility identifies browser targets")
  expect(
    WriteBackCompatibility.profile(for: "wechat")?.displayName == "微信",
    "writeback compatibility matches app aliases case-insensitively")
  expect(
    WriteBackCompatibility.recoveryHint(for: "Obsidian")?.contains("编辑模式") == true,
    "writeback compatibility provides app-specific recovery guidance")
  expect(
    WriteBackCompatibility.profile(for: "Unknown Notes") == nil,
    "writeback compatibility returns nil for unknown apps")

  let diagnostic = TextWriteBackFallbackDiagnostic(
    operation: .replace,
    targetState: .missing,
    targetName: nil,
    reason:
      "目标不可用: /Users/alice/Documents/input.txt Authorization: Bearer sk-live-secret-value-1234567890",
    copiedToPasteboard: true,
    originalCharacterCount: 12,
    payloadCharacterCount: 34
  )
  let summary = diagnostic.diagnosticSummary

  expect(
    summary.contains("state=fallback-copied"),
    "writeback fallback diagnostics report fallback state")
  expect(
    summary.contains("operation=replace"),
    "writeback fallback diagnostics report operation")
  expect(
    summary.contains("targetState=missing"),
    "writeback fallback diagnostics report target state")
  expect(
    summary.contains("copiedToPasteboard=yes"),
    "writeback fallback diagnostics report pasteboard recovery")
  expect(
    summary.contains("originalChars=12"),
    "writeback fallback diagnostics report original length")
  expect(
    summary.contains("payloadChars=34"),
    "writeback fallback diagnostics report copied payload length")
  expect(
    summary.contains("recovery=回到原应用后手动粘贴剪贴板内容; 如需替换请重新选中原文"),
    "writeback fallback diagnostics include actionable recovery guidance")
  expect(
    diagnostic.recoverySuggestion == "回到原应用后手动粘贴剪贴板内容; 如需替换请重新选中原文",
    "writeback fallback recovery guidance matches missing replace targets")
  expect(
    diagnostic.noticeMessage.contains("建议: 回到原应用后手动粘贴剪贴板内容; 如需替换请重新选中原文"),
    "writeback fallback notice surfaces actionable recovery guidance")
  expect(
    diagnostic.noticeMessage.contains("结果已复制到剪贴板。"),
    "writeback fallback notice explains pasteboard recovery state")
  expect(
    !summary.contains("/Users/alice"),
    "writeback fallback diagnostics redact user paths")
  expect(
    summary.contains("/Users/[user]/Documents/input.txt"),
    "writeback fallback diagnostics keep useful redacted path suffix")
  expect(
    !summary.contains("sk-live-secret-value-1234567890"),
    "writeback fallback diagnostics redact secrets")
  expect(
    summary.contains("Authorization: Bearer [REDACTED]"),
    "writeback fallback diagnostics keep sanitized auth context")
  expect(
    !diagnostic.noticeMessage.contains("/Users/alice"),
    "writeback fallback notice redacts user paths")
  expect(
    !diagnostic.noticeMessage.contains("sk-live-secret-value-1234567890"),
    "writeback fallback notice redacts secrets")

  let append = TextWriteBackFallbackDiagnostic(
    operation: .append,
    targetState: .missing,
    targetName: nil,
    reason: "paste failed",
    copiedToPasteboard: false,
    originalCharacterCount: 0,
    payloadCharacterCount: 20
  )
  expect(
    append.recoverySuggestion == "回到原应用后手动粘贴剪贴板内容; 如需追加请定位到目标位置; 若剪贴板未更新请手动复制结果",
    "writeback fallback recovery guidance adapts to append and pasteboard failure")
  expect(
    append.diagnosticSummary.contains("recovery=回到原应用后手动粘贴剪贴板内容; 如需追加请定位到目标位置; 若剪贴板未更新请手动复制结果"),
    "writeback fallback diagnostics include append recovery guidance")
  expect(
    append.noticeMessage.contains("结果未能自动复制到剪贴板。"),
    "writeback fallback notice explains pasteboard copy failure")
  expect(
    append.noticeMessage.contains("若剪贴板未更新请手动复制结果"),
    "writeback fallback notice explains manual copy recovery")

  let pasteboardSafetyRecovery = "当前剪贴板内容过大或格式过多,为避免丢失用户剪贴板,已取消自动粘贴。请手动复制结果后粘贴。"
  let protectedPasteboard = TextWriteBackFallbackDiagnostic(
    operation: .replace,
    targetState: .missing,
    targetName: nil,
    reason: "pasteboard snapshot unsafe reason=too-large",
    copiedToPasteboard: false,
    originalCharacterCount: 12,
    payloadCharacterCount: 34,
    recoveryOverride: pasteboardSafetyRecovery
  )
  expect(
    protectedPasteboard.recoverySuggestion == pasteboardSafetyRecovery,
    "writeback fallback diagnostics can surface pasteboard safety recovery guidance")
  expect(
    protectedPasteboard.diagnosticSummary.contains("recovery=\(pasteboardSafetyRecovery)"),
    "writeback fallback summary keeps pasteboard safety recovery searchable")
  expect(
    protectedPasteboard.noticeMessage.contains("建议: \(pasteboardSafetyRecovery)"),
    "writeback fallback notice explains pasteboard safety cancellation")

  let chrome = TextWriteBackFallbackDiagnostic(
    operation: .replace,
    targetState: .missing,
    targetName: "Google Chrome",
    reason: "paste failed",
    copiedToPasteboard: true,
    originalCharacterCount: 12,
    payloadCharacterCount: 34,
    recoveryOverride: nil
  )
  expect(
    chrome.recoverySuggestion.contains("浏览器写回失败"),
    "writeback fallback diagnostics use browser-specific compatibility recovery")
  expect(
    chrome.diagnosticSummary.contains("浏览器写回失败"),
    "writeback fallback summary includes app-specific compatibility recovery")
}

func testWriteBackUndoFallbackDiagnosticSummarizesFailureWithoutContent() {
  let record = TextWriteBackRecordState(
    targetName: nil,
    targetState: .missing,
    operation: .replace,
    originalText: "替换前的敏感原文",
    replacementText: "替换后的敏感结果")
  let diagnostic = TextWriteBackUndoFallbackDiagnostic(
    record: record,
    reason:
      "目标不可用: /Users/alice/Documents/input.txt Authorization: Bearer sk-live-secret-value-1234567890",
    copiedOriginalToPasteboard: true
  )
  let summary = diagnostic.diagnosticSummary

  expect(
    summary.contains("state=undo-fallback"),
    "writeback undo fallback diagnostics report undo fallback state")
  expect(
    summary.contains("undo=available"),
    "writeback undo fallback diagnostics keep the original undo state")
  expect(
    summary.contains("operation=replace"),
    "writeback undo fallback diagnostics report operation")
  expect(
    summary.contains("targetState=missing"),
    "writeback undo fallback diagnostics report target state")
  expect(
    summary.contains("copiedOriginalToPasteboard=yes"),
    "writeback undo fallback diagnostics report copied original recovery")
  expect(
    summary.contains("originalChars=8"),
    "writeback undo fallback diagnostics report original length")
  expect(
    summary.contains("replacementChars=8"),
    "writeback undo fallback diagnostics report replacement length")
  expect(
    summary.contains("recovery=替换前的原文已复制到剪贴板; 请回到目标应用手动粘贴恢复"),
    "writeback undo fallback diagnostics include recovery guidance")
  expect(
    diagnostic.noticeMessage.contains("建议: 替换前的原文已复制到剪贴板; 请回到目标应用手动粘贴恢复"),
    "writeback undo fallback notice surfaces recovery guidance")
  expect(
    !summary.contains("替换前的敏感原文") && !summary.contains("替换后的敏感结果"),
    "writeback undo fallback diagnostics do not include document content")
  expect(
    !diagnostic.noticeMessage.contains("替换前的敏感原文")
      && !diagnostic.noticeMessage.contains("替换后的敏感结果"),
    "writeback undo fallback notice does not include document content")
  expect(
    !summary.contains("/Users/alice") && !diagnostic.noticeMessage.contains("/Users/alice"),
    "writeback undo fallback messages redact user paths")
  expect(
    !summary.contains("sk-live-secret-value-1234567890")
      && !diagnostic.noticeMessage.contains("sk-live-secret-value-1234567890"),
    "writeback undo fallback messages redact secrets")

  let append = TextWriteBackUndoFallbackDiagnostic(
    record: TextWriteBackRecordState(
      targetName: nil,
      targetState: .missing,
      operation: .append,
      originalText: "",
      replacementText: "追加内容"),
    reason: "原应用暂不可用",
    copiedOriginalToPasteboard: false
  )
  expect(
    append.recoverySuggestion == "请在目标应用中使用系统撤销,或手动移除上次追加内容",
    "writeback undo fallback adapts recovery for append operations")
  expect(
    append.diagnosticSummary.contains("copiedOriginalToPasteboard=no"),
    "writeback undo fallback reports when no original was copied")

  let pasteboardUndoRecovery = "当前剪贴板内容过大或格式过多,为避免丢失用户剪贴板,已取消自动撤销。请在目标应用中使用系统撤销,或手动恢复。"
  let protectedPasteboardUndo = TextWriteBackUndoFallbackDiagnostic(
    record: record,
    reason: "pasteboard snapshot unsafe reason=too-large",
    copiedOriginalToPasteboard: false,
    recoveryOverride: pasteboardUndoRecovery
  )
  expect(
    protectedPasteboardUndo.recoverySuggestion == pasteboardUndoRecovery,
    "writeback undo fallback diagnostics can surface pasteboard safety recovery guidance")
  expect(
    protectedPasteboardUndo.diagnosticSummary.contains("recovery=\(pasteboardUndoRecovery)"),
    "writeback undo fallback summary keeps pasteboard safety recovery searchable")
  expect(
    protectedPasteboardUndo.noticeMessage.contains("建议: \(pasteboardUndoRecovery)"),
    "writeback undo fallback notice explains pasteboard safety cancellation")
}

func testWriteBackCommandFactoryReflectsUndoAvailability() {
  expect(
    WriteBackCommandFactory.undoDescriptor(for: nil) == nil,
    "missing writeback record produces no undo command")
  expect(
    WriteBackCommandFactory.undoMenuTitle(for: nil) == "撤销上次写回",
    "missing writeback record uses generic menu title")

  let replace = TextWriteBackRecordState(
    targetName: nil,
    targetState: .missing,
    operation: .replace,
    originalText: "旧文本",
    replacementText: "新文本")
  let replaceInput = WriteBackCommandInput(
    undoTitle: replace.undoTitle,
    operation: .replace,
    diagnosticSummary: replace.diagnosticSummary,
    isUndoAvailable: replace.isUndoAvailable
  )
  let replaceDescriptor = WriteBackCommandFactory.undoDescriptor(for: replaceInput)
  expect(replaceDescriptor?.id == "undo-write-back", "writeback undo command uses stable id")
  expect(replaceDescriptor?.title == "撤销上次替换到 原应用", "replace undo command uses record title")
  expect(
    replaceDescriptor?.subtitle == "恢复替换前的原文", "replace undo command explains restore behavior")
  expect(
    replaceDescriptor?.keywords.contains("替换") == true,
    "replace undo command is searchable by replace")
  expect(
    replaceDescriptor?.shortcutText == WriteBackCommandFactory.undoShortcutText,
    "writeback undo command exposes its menu shortcut")
  expect(
    replaceDescriptor?.action == .undoLastWriteBack, "writeback undo command carries undo action")
  expect(
    WriteBackCommandFactory.undoMenuTitle(for: replaceInput) == replace.undoTitle,
    "available writeback record drives menu title")
  expect(
    WriteBackCommandFactory.statusSummary(
      for: replaceInput,
      fallback: "state=fallback-copied")?.contains("operation=replace") == true,
    "writeback status summary prefers live records over stale fallback strings")

  let append = TextWriteBackRecordState(
    targetName: nil,
    targetState: .missing,
    operation: .append,
    originalText: "",
    replacementText: "\n追加")
  let appendInput = WriteBackCommandInput(
    undoTitle: append.undoTitle,
    operation: .append,
    diagnosticSummary: append.diagnosticSummary,
    isUndoAvailable: append.isUndoAvailable
  )
  let appendDescriptor = WriteBackCommandFactory.undoDescriptor(for: appendInput)
  expect(appendDescriptor?.subtitle == "移除上次追加内容", "append undo command explains removal behavior")
  expect(
    appendDescriptor?.keywords.contains("追加") == true, "append undo command is searchable by append"
  )

  let expired = TextWriteBackRecordState(
    targetName: nil,
    targetState: .missing,
    originalText: "旧文本",
    replacementText: "新文本",
    createdAt: Date(timeIntervalSinceNow: -TextWriteBackRecordState.expirationInterval - 1))
  let expiredInput = WriteBackCommandInput(
    undoTitle: expired.undoTitle,
    operation: .replace,
    diagnosticSummary: expired.diagnosticSummary,
    isUndoAvailable: expired.isUndoAvailable
  )
  expect(
    WriteBackCommandFactory.undoDescriptor(for: expiredInput) == nil,
    "expired writeback record produces no undo command")
  let expiredStatus = WriteBackCommandFactory.statusSummary(
    for: expiredInput,
    fallback: "state=available")
  expect(
    expiredStatus?.contains("state=unavailable") == true
      && expiredStatus?.contains("undo=expired") == true,
    "writeback status summary reports live expiration instead of stale availability")
  expect(
    WriteBackCommandFactory.statusSummary(
      for: nil,
      fallback: "state=fallback-copied") == "state=fallback-copied",
    "writeback status summary falls back when no live record exists")
}

func testCapturedTextPreservesSelectionWhitespace() {
  expect(
    TextCapture.usableCapturedText("  hello\n") == "  hello\n",
    "preserves selected whitespace for exact replacement")
  expect(TextCapture.usableCapturedText(" \n\t") == nil, "rejects whitespace-only captures")

  let outcome = TextCaptureOutcome(
    text: "  hello\n",
    method: .clipboard,
    accessibilityAttempted: true,
    clipboardAttempted: true,
    failureReason: nil,
    pasteboardReasonCode: nil,
    clipboardWaitAttempts: 3)
  expect(outcome.usableText == "  hello\n", "capture outcome preserves usable selection whitespace")
}

func testTextWriteBackAppendPayloadContract() {
  expect(
    TextWriteBackPayload.appendPayload(for: "追加内容") == "\n追加内容",
    "append writeback inserts exactly one leading newline before the result")
  expect(
    TextWriteBackPayload.appendPayload(for: "\n已有换行") == "\n\n已有换行",
    "append writeback preserves the result text exactly after its separator newline")
}

func testTextCaptureExtractsSelectedSubstringFromAXValueRange() {
  let value = "ab😀cd"
  expect(
    TextCapture.selectedSubstring(in: value, range: CFRange(location: 2, length: 2)) == "😀",
    "extracts selected text from UTF-16 AX ranges that cover an emoji")
  expect(
    TextCapture.selectedSubstring(in: value, range: CFRange(location: 1, length: 4)) == "b😀c",
    "extracts mixed ASCII and emoji selections from AX value ranges")
  expect(
    TextCapture.selectedSubstring(in: value, range: CFRange(location: 2, length: 1)) == nil,
    "rejects AX ranges that split a surrogate pair")
  expect(
    TextCapture.selectedSubstring(in: value, range: CFRange(location: 0, length: 0)) == nil,
    "rejects empty AX selection ranges")
  expect(
    TextCapture.selectedSubstring(in: value, range: CFRange(location: 99, length: 1)) == nil,
    "rejects out-of-bounds AX selection ranges")
  expect(
    TextCapture.selectedSubstring(in: "   ", range: CFRange(location: 0, length: 3)) == nil,
    "rejects whitespace-only text extracted through AX ranges")
}

func testServicePasteboardTextAcceptsCommonPlainTextTypes() {
  func textForType(_ rawType: String, text: String = "来自服务菜单的文本") -> String? {
    let pasteboard = NSPasteboard(name: NSPasteboard.Name("SnapAIServiceTest-\(UUID().uuidString)"))
    pasteboard.clearContents()
    pasteboard.setString(text, forType: NSPasteboard.PasteboardType(rawType))
    defer { pasteboard.releaseGlobally() }
    return ServicePasteboardText.text(from: pasteboard)
  }

  expect(
    textForType("public.utf8-plain-text") == "来自服务菜单的文本",
    "services text helper accepts public.utf8-plain-text")
  expect(
    textForType("public.plain-text") == "来自服务菜单的文本",
    "services text helper accepts public.plain-text")
  expect(
    textForType("public.text") == "来自服务菜单的文本",
    "services text helper accepts public.text")
  expect(
    textForType("NSStringPboardType") == "来自服务菜单的文本",
    "services text helper keeps legacy NSStringPboardType support")
  expect(
    textForType("NeXT plain ascii pasteboard type", text: "ASCII service text")
      == "ASCII service text",
    "services text helper keeps legacy NeXT ASCII pasteboard support")
  expect(
    textForType("com.apple.traditional-mac-plain-text", text: "MacRoman style text")
      == "MacRoman style text",
    "services text helper accepts traditional mac plain text payloads")
  expect(
    textForType("public.text", text: " \n\t") == nil,
    "services text helper rejects whitespace-only service payloads")

  let legacyDataPasteboard = NSPasteboard(
    name: NSPasteboard.Name("SnapAIServiceLegacyDataTest-\(UUID().uuidString)"))
  legacyDataPasteboard.clearContents()
  legacyDataPasteboard.setData(
    Data("来自 legacy data 的文本".utf8),
    forType: NSPasteboard.PasteboardType("NSStringPboardType"))
  defer { legacyDataPasteboard.releaseGlobally() }
  expect(
    ServicePasteboardText.text(from: legacyDataPasteboard) == "来自 legacy data 的文本",
    "services text helper decodes legacy NSStringPboardType data when property-list reads are unavailable"
  )

  let utf16Pasteboard = NSPasteboard(
    name: NSPasteboard.Name("SnapAIServiceUTF16Test-\(UUID().uuidString)"))
  utf16Pasteboard.clearContents()
  if let utf16Data = "来自 UTF-16 的文本".data(using: .utf16LittleEndian) {
    utf16Pasteboard.setData(
      utf16Data,
      forType: NSPasteboard.PasteboardType("public.utf16-external-plain-text"))
  }
  defer { utf16Pasteboard.releaseGlobally() }
  expect(
    ServicePasteboardText.text(from: utf16Pasteboard) == "来自 UTF-16 的文本",
    "services text helper accepts UTF-16 service text")

  let itemPasteboard = NSPasteboard(
    name: NSPasteboard.Name("SnapAIServiceItemTest-\(UUID().uuidString)"))
  itemPasteboard.clearContents()
  let item = NSPasteboardItem()
  item.setString(
    "来自 pasteboard item 的文本", forType: NSPasteboard.PasteboardType("public.utf8-plain-text"))
  itemPasteboard.writeObjects([item])
  defer { itemPasteboard.releaseGlobally() }
  expect(
    ServicePasteboardText.text(from: itemPasteboard) == "来自 pasteboard item 的文本",
    "services text helper reads text from pasteboard items")

  let rtfPasteboard = NSPasteboard(
    name: NSPasteboard.Name("SnapAIServiceRTFTest-\(UUID().uuidString)"))
  rtfPasteboard.clearContents()
  let attributed = NSAttributedString(string: "来自 RTF 的文本")
  if let rtfData = try? attributed.data(
    from: NSRange(location: 0, length: attributed.length),
    documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf])
  {
    rtfPasteboard.setData(rtfData, forType: NSPasteboard.PasteboardType("public.rtf"))
  }
  defer { rtfPasteboard.releaseGlobally() }
  expect(
    ServicePasteboardText.text(from: rtfPasteboard) == "来自 RTF 的文本",
    "services text helper extracts plain text from RTF service payloads")

  let legacyRTFPasteboard = NSPasteboard(
    name: NSPasteboard.Name("SnapAIServiceLegacyRTFTest-\(UUID().uuidString)"))
  legacyRTFPasteboard.clearContents()
  if let rtfData = try? attributed.data(
    from: NSRange(location: 0, length: attributed.length),
    documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf])
  {
    legacyRTFPasteboard.setData(rtfData, forType: NSPasteboard.PasteboardType("NSRTFPboardType"))
  }
  defer { legacyRTFPasteboard.releaseGlobally() }
  expect(
    ServicePasteboardText.text(from: legacyRTFPasteboard) == "来自 RTF 的文本",
    "services text helper extracts plain text from legacy RTF service payloads")

  let htmlPasteboard = NSPasteboard(
    name: NSPasteboard.Name("SnapAIServiceHTMLTest-\(UUID().uuidString)"))
  htmlPasteboard.clearContents()
  let html = "<html><body>来自 <strong>HTML</strong> 的文本</body></html>"
  htmlPasteboard.setData(Data(html.utf8), forType: NSPasteboard.PasteboardType("public.html"))
  defer { htmlPasteboard.releaseGlobally() }
  expect(
    ServicePasteboardText.text(from: htmlPasteboard)?.contains("来自 HTML 的文本") == true,
    "services text helper extracts plain text from HTML service payloads")

  let legacyHTMLPasteboard = NSPasteboard(
    name: NSPasteboard.Name("SnapAIServiceLegacyHTMLTest-\(UUID().uuidString)"))
  legacyHTMLPasteboard.clearContents()
  legacyHTMLPasteboard.setData(
    Data(html.utf8), forType: NSPasteboard.PasteboardType("Apple HTML pasteboard type"))
  defer { legacyHTMLPasteboard.releaseGlobally() }
  expect(
    ServicePasteboardText.text(from: legacyHTMLPasteboard)?.contains("来自 HTML 的文本") == true,
    "services text helper extracts plain text from legacy HTML service payloads")
}

func testTextCaptureTargetActivationGuards() {
  let currentPID = pid_t(100)
  expect(
    !TextCapture.shouldActivateTargetForCapture(
      targetPID: nil,
      currentPID: currentPID,
      isTerminated: false),
    "does not activate when there is no captured target app")
  expect(
    !TextCapture.shouldActivateTargetForCapture(
      targetPID: 0,
      currentPID: currentPID,
      isTerminated: false),
    "does not activate invalid process identifiers")
  expect(
    !TextCapture.shouldActivateTargetForCapture(
      targetPID: currentPID,
      currentPID: currentPID,
      isTerminated: false),
    "does not activate SnapAI itself as a capture target")
  expect(
    !TextCapture.shouldActivateTargetForCapture(
      targetPID: currentPID + 1,
      currentPID: currentPID,
      isTerminated: true),
    "does not activate a terminated target app")
  expect(
    TextCapture.shouldActivateTargetForCapture(
      targetPID: currentPID + 1,
      currentPID: currentPID,
      isTerminated: false),
    "allows a live external app to be reactivated before clipboard fallback")
  expect(
    !TextCapture.shouldRetryAccessibilityAfterTargetActivation(
      preferAX: false,
      capturedText: nil,
      targetPID: currentPID + 1,
      targetIsTerminated: false,
      currentPID: currentPID),
    "does not retry AX after activation when the user disabled AX-first capture")
  expect(
    !TextCapture.shouldRetryAccessibilityAfterTargetActivation(
      preferAX: true,
      capturedText: "selected",
      targetPID: currentPID + 1,
      targetIsTerminated: false,
      currentPID: currentPID),
    "does not retry AX after activation when AX already captured text")
  expect(
    TextCapture.shouldRetryAccessibilityAfterTargetActivation(
      preferAX: true,
      capturedText: nil,
      targetPID: currentPID + 1,
      targetIsTerminated: false,
      currentPID: currentPID),
    "retries AX after activating a live external target before clipboard fallback")
  expect(
    TextCapture.targetActivationWaitMicroseconds == 120_000,
    "keeps a short focus-settle delay after target app activation")
  expect(
    TextCapture.transientMenuDismissWaitMicroseconds == 60_000,
    "keeps a short transient-menu dismissal delay before clipboard fallback")
  expect(
    TextCapture.clipboardChangePollLimit == 80,
    "allows a longer clipboard fallback wait for context-menu initiated captures")
  expect(
    TextCapture.clipboardCopyAttemptLimit == 3,
    "retries clipboard fallback for apps that update the pasteboard slowly")
  expect(
    TextCapture.clipboardRetryWaitMicroseconds == 70_000,
    "keeps a short pause between clipboard fallback attempts")
  expect(
    TextCapture.focusedAXTraversalDepth >= 4 && TextCapture.targetAXTraversalDepth >= 8
      && TextCapture.maxAXTraversalNodes >= 500,
    "uses a deeper AX traversal budget for complex app accessibility trees")
  expect(
    TextCapture.shouldDismissTransientMenusBeforeCopy(
      targetPID: currentPID + 1,
      frontmostPID: currentPID,
      currentPID: currentPID),
    "dismisses transient menus when capture must return from SnapAI to the target app")
  expect(
    TextCapture.shouldDismissTransientMenusBeforeCopy(
      targetPID: currentPID + 1,
      frontmostPID: currentPID + 2,
      currentPID: currentPID),
    "dismisses transient menus when a system menu app is frontmost before clipboard fallback")
  expect(
    !TextCapture.shouldDismissTransientMenusBeforeCopy(
      targetPID: currentPID + 1,
      frontmostPID: currentPID + 1,
      currentPID: currentPID),
    "does not send escape for direct hotkey capture while the target app is already frontmost")
  expect(
    TextCapture.shouldDismissTransientMenusBeforeCopy(
      targetPID: currentPID + 1,
      frontmostPID: currentPID + 1,
      currentPID: currentPID,
      forceDismissal: true),
    "service fallback can dismiss a context menu even when it belongs to the target app")
  expect(
    !TextCapture.shouldDismissTransientMenusBeforeCopy(
      targetPID: nil,
      frontmostPID: currentPID + 1,
      currentPID: currentPID),
    "does not dismiss menus without a known target app")
  expect(
    !TextCapture.shouldDismissTransientMenusBeforeCopy(
      targetPID: currentPID,
      frontmostPID: currentPID + 1,
      currentPID: currentPID,
      forceDismissal: true),
    "forced transient UI dismissal still refuses to target SnapAI itself")
}

func testCaptureTargetResolverUsesRecentExternalAppWhenSnapAIIsFrontmost() {
  let currentPID = pid_t(100)
  expect(
    CaptureTargetResolver.preferredDeferredSource(
      serviceInvocationPID: 250,
      serviceInvocationIsTerminated: false,
      frontmostPID: currentPID,
      frontmostIsTerminated: false,
      lastExternalPID: 300,
      lastExternalIsTerminated: false,
      currentPID: currentPID) == .serviceInvocation,
    "services fallback keeps the target captured at service invocation time")
  expect(
    CaptureTargetResolver.preferredDeferredSource(
      serviceInvocationPID: 250,
      serviceInvocationIsTerminated: true,
      frontmostPID: currentPID,
      frontmostIsTerminated: false,
      lastExternalPID: 300,
      lastExternalIsTerminated: false,
      currentPID: currentPID) == .lastExternal,
    "services fallback ignores stale invocation targets and uses the latest usable external app")
  expect(
    CaptureTargetResolver.preferredSource(
      frontmostPID: 200,
      frontmostIsTerminated: false,
      lastExternalPID: 300,
      lastExternalIsTerminated: false,
      currentPID: currentPID) == .frontmost,
    "uses the live frontmost external app as the capture target")
  expect(
    CaptureTargetResolver.preferredSource(
      frontmostPID: currentPID,
      frontmostIsTerminated: false,
      lastExternalPID: 300,
      lastExternalIsTerminated: false,
      currentPID: currentPID) == .lastExternal,
    "falls back to the last external app when SnapAI is frontmost")
  expect(
    CaptureTargetResolver.preferredSource(
      frontmostPID: 201,
      frontmostIsTerminated: false,
      frontmostBundleIdentifier: "com.apple.systemuiserver",
      lastExternalPID: 300,
      lastExternalIsTerminated: false,
      currentPID: currentPID) == .lastExternal,
    "falls back to the last external app when a system menu bar process is frontmost")
  expect(
    CaptureTargetResolver.preferredSource(
      frontmostPID: 200,
      frontmostIsTerminated: true,
      lastExternalPID: 300,
      lastExternalIsTerminated: false,
      currentPID: currentPID) == .lastExternal,
    "ignores terminated frontmost apps")
  expect(
    CaptureTargetResolver.preferredSource(
      frontmostPID: currentPID,
      frontmostIsTerminated: false,
      lastExternalPID: 300,
      lastExternalIsTerminated: true,
      currentPID: currentPID) == .none,
    "does not fall back to a terminated last external app")
  expect(
    !CaptureTargetResolver.isUsableExternalApp(
      pid: 201,
      isTerminated: false,
      bundleIdentifier: "com.apple.controlcenter",
      currentPID: currentPID),
    "does not treat Control Center as a text capture target")
}

func testTextCaptureRecoveryGuidePointsToActionablePermissionHelp() {
  expect(
    TextCaptureRecoveryGuide.title == "未检测到选中的文字",
    "text capture recovery guide uses the no-selection alert title")
  expect(
    TextCaptureRecoveryGuide.message.contains("权限健康中心"),
    "text capture recovery guide points to permission health")
  expect(
    TextCaptureRecoveryGuide.message.contains("快捷提问"),
    "text capture recovery guide offers quick input fallback")
  expect(
    TextCaptureRecoveryGuide.message.contains("辅助功能权限"),
    "text capture recovery guide names accessibility permission")
  expect(
    TextCaptureRecoveryGuide.message.contains("剪贴板复制兜底"),
    "text capture recovery guide mentions copy fallback")
  expect(
    TextCaptureRecoveryGuide.quickInputButtonTitle == "打开快捷提问",
    "text capture recovery guide exposes quick input button title")
  expect(
    TextCaptureRecoveryGuide.permissionHealthButtonTitle == "打开权限健康中心",
    "text capture recovery guide exposes permission health button title")
  expect(
    TextCaptureRecoveryGuide.accessibilitySettingsButtonTitle == "打开辅助功能设置",
    "text capture recovery guide exposes accessibility settings button title")
  expect(
    TextCaptureRecoveryGuide.accessibilitySettingsURL.absoluteString.contains(
      "Privacy_Accessibility"),
    "text capture recovery guide opens the accessibility privacy pane")
}

func testTextCaptureDiagnosticSummarizesStateWithoutContent() {
  let captured = TextCaptureDiagnostic.captured(
    accessibilityGranted: true,
    preferAX: true,
    frontmostAppName: "Pages",
    characterCount: 42)
  expect(
    captured.diagnosticSummary.contains("state=captured"),
    "text capture diagnostics report captured state")
  expect(
    captured.diagnosticSummary.contains("accessibility=granted"),
    "text capture diagnostics report accessibility state")
  expect(
    captured.diagnosticSummary.contains("preferAX=yes"),
    "text capture diagnostics report capture preference")
  expect(
    captured.diagnosticSummary.contains("frontmostApp=Pages"),
    "text capture diagnostics report sanitized frontmost app name")
  expect(
    captured.diagnosticSummary.contains("capturedChars=42"),
    "text capture diagnostics report character count")
  expect(
    captured.recoverySuggestion == "无需处理",
    "successful text capture diagnostics need no recovery")
  expect(
    captured.diagnosticSummary.contains("recovery=无需处理"),
    "text capture diagnostics include recovery guidance")

  let failed = TextCaptureDiagnostic.noSelection(
    accessibilityGranted: false,
    preferAX: true,
    frontmostAppName: "Secret sk-live-secret-value-1234567890")
  expect(
    failed.diagnosticSummary.contains("state=no-selection"),
    "text capture diagnostics report no-selection state")
  expect(
    failed.diagnosticSummary.contains("accessibility=missing"),
    "text capture diagnostics report missing accessibility")
  expect(
    failed.diagnosticSummary.contains("capturedChars=0"),
    "text capture diagnostics do not include selected text content")
  expect(
    failed.recoverySuggestion == "授予辅助功能权限后重试; 也可打开快捷提问",
    "text capture diagnostics explain missing accessibility recovery")
  expect(
    failed.diagnosticSummary.contains("recovery=授予辅助功能权限后重试; 也可打开快捷提问"),
    "failed text capture diagnostics include recovery guidance")
  expect(
    !failed.diagnosticSummary.contains("sk-live-secret-value-1234567890"),
    "text capture diagnostics redact sensitive app metadata")

  let clipboardCaptured = TextCaptureDiagnostic.captured(
    accessibilityGranted: true,
    preferAX: true,
    frontmostAppName: "Pages",
    characterCount: 12,
    method: .clipboard,
    clipboardWaitAttempts: 4)
  expect(
    clipboardCaptured.diagnosticSummary.contains("method=clipboard"),
    "text capture diagnostics report clipboard fallback success")
  expect(
    clipboardCaptured.diagnosticSummary.contains("clipboardWaitAttempts=4"),
    "text capture diagnostics report clipboard wait attempts")

  let unsafePasteboard = TextCaptureDiagnostic.noSelection(
    accessibilityGranted: true,
    preferAX: true,
    frontmostAppName: "Pages",
    failureReason: .pasteboardSnapshotUnsafe,
    pasteboardReasonCode: "too-large")
  expect(
    unsafePasteboard.diagnosticSummary.contains("failure=pasteboard-snapshot-unsafe"),
    "text capture diagnostics report unsafe pasteboard fallback")
  expect(
    unsafePasteboard.diagnosticSummary.contains("pasteboard=too-large"),
    "text capture diagnostics include pasteboard protection reason")
  expect(
    unsafePasteboard.recoverySuggestion.contains("保护剪贴板"),
    "unsafe pasteboard text capture recovery explains clipboard protection")

  let axNoSelection = TextCaptureDiagnostic.noSelection(
    accessibilityGranted: true,
    preferAX: true,
    frontmostAppName: "Pages")
  expect(
    axNoSelection.recoverySuggestion == "重新选中文字后重试; 若目标应用不兼容,可打开快捷提问",
    "AX text capture diagnostics explain incompatible target recovery")

  let copyFallbackNoSelection = TextCaptureDiagnostic.noSelection(
    accessibilityGranted: true,
    preferAX: false,
    frontmostAppName: "Pages")
  expect(
    copyFallbackNoSelection.recoverySuggestion == "重新选中文字后重试; 确认目标应用允许复制,也可打开快捷提问",
    "clipboard fallback text capture diagnostics explain copy recovery")
}

func testSelectionSourceContextClassifiesAppsSafely() {
  expect(
    SelectionSourceContext.classify(appName: "Xcode") == .codeEditor,
    "selection source context recognizes code editors")
  expect(
    SelectionSourceContext.classify(appName: "Ghostty") == .terminal,
    "selection source context recognizes terminals")
  expect(
    SelectionSourceContext.classify(appName: "Google Chrome") == .browser,
    "selection source context recognizes browsers")
  expect(
    SelectionSourceContext.classify(appName: "WeChat") == .messaging,
    "selection source context recognizes messaging apps")

  let context = SelectionSourceContext.make(appName: "Secret sk-live-secret-value-1234567890")
  expect(context.kind == .unknown, "unknown apps stay generic")
  expect(
    !context.diagnosticLine.contains("sk-live-secret-value-1234567890"),
    "selection source diagnostics redact sensitive app metadata")
  expect(
    context.promptPrefix.contains("来源类型: 未知应用"),
    "selection source prompt includes coarse source type")
  expect(
    !context.promptPrefix.contains("Secret"),
    "selection source prompt does not send raw app names")
}

func testSystemPrivacySettingsBuildsStablePaneURLs() {
  expect(
    SystemPrivacySettings.accessibilityURL.absoluteString
      == "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility",
    "system privacy settings opens accessibility pane")
  expect(
    SystemPrivacySettings.screenCaptureURL.absoluteString
      == "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture",
    "system privacy settings opens screen recording pane")
  expect(
    SystemPrivacySettings.url(for: .accessibility) == SystemPrivacySettings.accessibilityURL,
    "system privacy settings reuses accessibility helper")
  expect(
    SystemPrivacySettings.url(for: .screenCapture) == SystemPrivacySettings.screenCaptureURL,
    "system privacy settings reuses screen recording helper")
}

func testPasteboardRestoreDecisionProtectsUserChanges() {
  expect(
    TextCapture.shouldRestorePasteboard(
      expectedChangeCount: 42,
      currentChangeCount: 42),
    "restores the previous pasteboard when SnapAI's injected pasteboard item is still current")
  expect(
    !TextCapture.shouldRestorePasteboard(
      expectedChangeCount: 42,
      currentChangeCount: 43),
    "does not restore when the pasteboard changed after SnapAI injected text")

  let limits = PasteboardSnapshotLimits(
    maxItemCount: 2,
    maxTypeCount: 3,
    maxTotalByteCount: 10)
  expect(
    TextCapture.pasteboardSnapshotRejectionReason(
      itemCount: 2,
      typeCount: 3,
      totalByteCount: 10,
      limits: limits) == nil,
    "allows pasteboard snapshots at the configured safety boundary")
  expect(
    TextCapture.pasteboardSnapshotRejectionReason(
      itemCount: 3,
      typeCount: 1,
      totalByteCount: 1,
      limits: limits) == "too-many-items",
    "rejects pasteboard snapshots with too many items")
  expect(
    TextCapture.pasteboardSnapshotRejectionReason(
      itemCount: 1,
      typeCount: 4,
      totalByteCount: 1,
      limits: limits) == "too-many-types",
    "rejects pasteboard snapshots with too many data types")
  expect(
    TextCapture.pasteboardSnapshotRejectionReason(
      itemCount: 1,
      typeCount: 1,
      totalByteCount: 11,
      limits: limits) == "too-large",
    "rejects pasteboard snapshots that exceed the byte budget")

  let incomplete = PasteboardSnapshot.incomplete(
    reasonCode: "too-large",
    totalByteCount: 11,
    itemCount: 1,
    typeCount: 1)
  expect(
    !incomplete.canRestore,
    "incomplete pasteboard snapshots are not considered safe to restore")
  expect(
    incomplete.recoveryMessage.contains("已取消自动粘贴"),
    "incomplete pasteboard snapshots explain that automatic paste was cancelled")
  expect(
    incomplete.undoRecoveryMessage.contains("已取消自动撤销"),
    "incomplete pasteboard snapshots explain that automatic undo was cancelled")
}

func testTextCaptureValidatesAXCoreFoundationTypes() {
  let element = AXUIElementCreateSystemWide()
  expect(TextCapture.isAXUIElementRef(element), "accepts AXUIElement Core Foundation values")
  expect(!TextCapture.isAXValueRef(element), "does not confuse AXUIElement with AXValue")

  var range = CFRange(location: 1, length: 2)
  guard let axValue = AXValueCreate(.cfRange, &range) else {
    expect(false, "creates AXValue range fixture")
    return
  }
  expect(TextCapture.isAXValueRef(axValue), "accepts AXValue Core Foundation values")
  expect(!TextCapture.isAXUIElementRef(axValue), "does not confuse AXValue with AXUIElement")
}

func testAutomationWriteBackPolicyRequiresCapturedSelection() {
  let urlReplace = AutomationWriteBackPolicy.urlRun(
    options: AutomationRunOptions(replaceByDefault: true)
  )
  expect(
    !urlReplace.autoReplaceEnabled,
    "URL automation never enables automatic write-back without a trusted selection context")

  var replacingAction = AIAction.defaults()[2]
  replacingAction.replaceByDefault = true
  expect(
    AutomationWriteBackPolicy.capturedSelection(action: replacingAction).autoReplaceEnabled,
    "captured selection actions can enter replacement confirmation")

  var plainAction = AIAction.defaults()[0]
  plainAction.replaceByDefault = false
  expect(
    !AutomationWriteBackPolicy.capturedSelection(action: plainAction).autoReplaceEnabled,
    "captured selection respects actions that do not request replacement")
}

func testResultCommandFactoryIncludesResultWriteBackAndRegenerateCommands() {
  let state = ResultCommandState(
    hasResult: true,
    hasDiagnostics: true,
    canWriteBack: true,
    isStreaming: false,
    hasSourceText: true)
  let descriptors = ResultCommandFactory.descriptors(state: state)

  expect(
    descriptors.map(\.id) == [
      "result-copy",
      "result-copy-markdown",
      "result-export",
      "result-copy-brief-diagnostics",
      "result-copy-diagnostics",
      "result-open-ai-settings",
      "result-replace",
      "result-append",
      "result-regenerate",
    ], "result commands appear in stable command palette order")
  expect(
    descriptors.map(\.action) == [
      .copyOutput,
      .copyMarkdown,
      .exportConversation,
      .copyBriefDiagnostics,
      .copyDiagnostics,
      .openAISettings,
      .replaceOriginal,
      .appendToDocument,
      .regenerate,
    ], "result commands carry the expected actions")
  expect(
    descriptors[3].title == ResultDiagnosticsCommand.briefTitle,
    "brief diagnostics command reuses the shared diagnostics label")
  expect(
    descriptors[4].title == ResultDiagnosticsCommand.title,
    "full diagnostics command reuses the shared diagnostics label")
  expect(
    descriptors[5].title == ResultRecoveryCommand.openAISettingsTitle,
    "AI settings recovery command reuses the shared recovery label")
  expect(
    descriptors[5].subtitle == ResultRecoveryCommand.openAISettingsSubtitle,
    "AI settings recovery command explains provider troubleshooting")
  expect(
    descriptors[5].keywords.contains("api key") && descriptors[5].keywords.contains("修复"),
    "AI settings recovery command is searchable by request failure terms")
  expect(
    descriptors[6].subtitle == "先展示差异预览",
    "replace command explains the diff preview")
  expect(
    descriptors[8].keywords.contains("retry"),
    "regenerate command is searchable by retry")
  expect(
    ResultCommandFactory.isEnabled(.copyOutput, in: state), "copy output is enabled with a result")
  expect(
    ResultCommandFactory.isEnabled(.copyMarkdown, in: state),
    "copy markdown is enabled with a result")
  expect(
    ResultCommandFactory.isEnabled(.exportConversation, in: state),
    "export is enabled with a result")
  expect(
    ResultCommandFactory.isEnabled(.copyBriefDiagnostics, in: state),
    "brief diagnostics is enabled when diagnostics exist")
  expect(
    ResultCommandFactory.isEnabled(.copyDiagnostics, in: state),
    "diagnostics is enabled when diagnostics exist")
  expect(
    ResultCommandFactory.isEnabled(.openAISettings, in: state),
    "AI settings recovery is enabled when diagnostics exist")
  expect(
    ResultCommandFactory.isEnabled(.replaceOriginal, in: state),
    "replace is enabled when writeback is available")
  expect(
    ResultCommandFactory.isEnabled(.appendToDocument, in: state),
    "append is enabled when writeback is available")
  expect(
    ResultCommandFactory.isEnabled(.regenerate, in: state),
    "regenerate is enabled after a non-streaming source request")
  expect(!ResultCommandFactory.isEnabled(.stop, in: state), "stop is disabled when not streaming")
}

func testResultPersistenceAndWriteBackCoordinator() {
  let metrics = ResultPersistence.completionMetrics(
    startTime: Date(timeIntervalSince1970: 10),
    outputText: "结果",
    now: Date(timeIntervalSince1970: 12.5)
  )
  expect(metrics.elapsed == 2.5, "result persistence computes elapsed time")
  expect(metrics.characterCount == 2, "result persistence computes output character count")

  let export = ResultPersistence.conversationExport(
    actionName: "总结",
    sourceText: "原文",
    outputText: "结果",
    providerName: "Provider",
    modelName: "",
    fallbackModelName: "fallback-model",
    elapsed: 1,
    diagnosticsText: "",
    protectsContent: false,
    date: Date(timeIntervalSince1970: 0)
  )
  expect(
    export.markdown.contains("Provider / fallback-model"),
    "result persistence uses fallback model name when active route model is empty")

  var replaced: (String, String)?
  ResultWriteBackCoordinator.replace(
    original: "旧",
    replacement: "新",
    handler: { replaced = ($0, $1) })
  expect(
    replaced?.0 == "旧" && replaced?.1 == "新",
    "writeback coordinator forwards replace requests")

  var appended: String?
  ResultWriteBackCoordinator.append(
    text: "追加",
    handler: { appended = $0 })
  expect(appended == "追加", "writeback coordinator forwards append requests")
  expect(
    ResultWriteBackCoordinator.shouldAutoReplace(
      recordUsage: true,
      autoReplaceEnabled: true,
      replaceByDefault: true,
      outputText: "结果",
      errorMessage: nil),
    "writeback coordinator allows successful configured auto-replace")
  expect(
    !ResultWriteBackCoordinator.shouldAutoReplace(
      recordUsage: true,
      autoReplaceEnabled: true,
      replaceByDefault: true,
      outputText: "结果",
      errorMessage: "failed"),
    "writeback coordinator blocks auto-replace after errors")
}
