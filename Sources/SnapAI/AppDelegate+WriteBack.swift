import AppKit
import SnapAILogic

@MainActor
extension AppDelegate {
  /// 把结果替换回原文位置(#3)
  func replaceSelection(original: String, with replacement: String) {
    defer {
      previousSelectionSnapshot = nil
      previousCaptureMethod = nil
      TextCapture.clearRecentSelectionSnapshot()
    }
    let decision = DiffPreviewWindowController.present(
      original: original,
      revised: replacement,
      actionName: resultVM.action.name)
    switch decision {
    case .replace:
      guard let writeBackTarget = validatedWriteBackTarget() else {
        copyWriteBackFallback(
          text: replacement,
          operation: .replace,
          originalCharacterCount: original.count,
          title: "无法自动替换",
          reason: writeBackTargetUnavailableReason())
        return
      }
      performReplacement(
        original: original,
        replacement: replacement,
        targetApp: writeBackTarget,
        selectionSnapshot: previousSelectionSnapshot)
    case .copy:
      NSPasteboard.general.clearContents()
      NSPasteboard.general.setString(replacement, forType: .string)
    case .cancel:
      break
    }
  }

  private func performReplacement(
    original: String,
    replacement: String,
    targetApp: NSRunningApplication,
    selectionSnapshot: TextSelectionSnapshot?,
    allowsUnverifiedReplacement: Bool = false,
    confirmedTargetSnapshot: TextWriteBackTargetSnapshot? = nil
  ) {
    panelController.hide()
    TextEditTransaction(
      targetApp: targetApp,
      selectionSnapshot: selectionSnapshot,
      allowsUnverifiedReplacement: allowsUnverifiedReplacement,
      confirmedTargetSnapshot: confirmedTargetSnapshot
    )
    .replace(original: original, with: replacement) { [weak self] in
      self?.recordWriteBack(
        targetApp: targetApp,
        original: original,
        replacement: replacement,
        selectionSnapshot: selectionSnapshot?.snapshotAfterReplacement(
          replacement, targetPID: targetApp.processIdentifier),
        sourceWasVerified: !allowsUnverifiedReplacement)
    } failure: { [weak self] snapshot in
      self?.handleUnsafePasteboardWriteBack(
        operation: .replace,
        originalCharacterCount: original.count,
        payloadCharacterCount: replacement.count,
        snapshot: snapshot)
    } validationFailure: { [weak self] reason in
      guard let self else { return }
      if reason == .unavailable, !allowsUnverifiedReplacement {
        let confirmationTarget = TextCapture.writeBackTargetSnapshot(targetPID: targetApp.processIdentifier)
        let alert = NSAlert()
        alert.messageText = "无法核验原文，请重新选取并确认"
        let targetName = targetApp.localizedName ?? "原应用"
        alert.informativeText = "当前控件未提供足够的选区信息。请切回「\(targetName)」核对最新原文并重新选中要替换的内容，再回到此提示确认。\n\n继续后将向该应用当前选区粘贴；SnapAI 无法保证它仍是首次取词的位置，也无法核验原文是否已变化。"
        alert.alertStyle = .warning
        alert.addButton(withTitle: "复制结果")
        alert.addButton(withTitle: "已重新选取，继续替换")
        alert.addButton(withTitle: "取消")
        NSApp.activate(ignoringOtherApps: true)
        switch alert.runModal() {
        case .alertSecondButtonReturn:
          self.performReplacement(original: original,
                                  replacement: replacement,
                                  targetApp: targetApp,
                                  selectionSnapshot: selectionSnapshot,
                                  allowsUnverifiedReplacement: true,
                                  confirmedTargetSnapshot: confirmationTarget)
        case .alertFirstButtonReturn:
          self.copyWriteBackFallback(text: replacement,
                                     operation: .replace,
                                     originalCharacterCount: original.count,
                                     title: "结果已复制",
                                     reason: reason.recoveryMessage)
        default:
          self.lastWriteBackStatusSummary = "state=cancelled, sourceValidation=unavailable"
        }
        return
      }
      if reason == .pasteboardChanged {
        self.lastWriteBackStatusSummary = "state=blocked, reason=\(reason.rawValue), copiedToPasteboard=no"
        self.presentWriteBackNotice(title: "已取消自动写回", message: reason.recoveryMessage)
        return
      }
      self.copyWriteBackFallback(
        text: replacement,
        operation: .replace,
        originalCharacterCount: original.count,
        title: "已取消自动替换",
        reason: reason.recoveryMessage)
    }
  }

  /// 把结果追加到光标后(#8):先发 → 键移到选区末尾,再粘贴 "\n" + result
  func appendSelection(with text: String) {
    guard let writeBackTarget = validatedWriteBackTarget() else {
      copyWriteBackFallback(
        text: text,
        operation: .append,
        originalCharacterCount: 0,
        title: "无法自动追加",
        reason: writeBackTargetUnavailableReason())
      return
    }
    let insertedText = TextWriteBackPayload.appendPayload(for: text)
    TextEditTransaction(targetApp: writeBackTarget).append(text) { [weak self] in
      self?.recordWriteBack(
        targetApp: writeBackTarget,
        operation: .append,
        original: "",
        replacement: insertedText)
    } failure: { [weak self] snapshot in
      self?.handleUnsafePasteboardWriteBack(
        operation: .append,
        originalCharacterCount: 0,
        payloadCharacterCount: insertedText.count,
        snapshot: snapshot)
    } validationFailure: { [weak self] reason in
      if reason == .pasteboardChanged {
        self?.lastWriteBackStatusSummary = "state=blocked, reason=\(reason.rawValue), copiedToPasteboard=no"
        self?.presentWriteBackNotice(title: "已取消自动写回", message: reason.recoveryMessage)
        return
      }
      self?.copyWriteBackFallback(
        text: text,
        operation: .append,
        originalCharacterCount: 0,
        title: "已取消自动追加",
        reason: "写入前未能保持原应用的焦点。请回到目标编辑区后手动粘贴。 reason=\(reason.rawValue)")
    }
  }

  func validatedWriteBackTarget() -> NSRunningApplication? {
    guard let target = previousApp,
      !target.isTerminated,
      target.processIdentifier != ProcessInfo.processInfo.processIdentifier
    else {
      return nil
    }
    return target
  }

  func writeBackTargetUnavailableReason() -> String {
    guard let target = previousApp else {
      return "没有可信的原应用目标。"
    }
    let appName = MarkdownExportSafety.metadata(
      target.localizedName,
      fallback: "原应用",
      maxLength: 80)
    if target.isTerminated {
      return "\(appName) 已退出。"
    }
    if target.processIdentifier == ProcessInfo.processInfo.processIdentifier {
      return "当前目标是 SnapAI 自身。"
    }
    return "\(appName) 暂不可用。"
  }

  func copyWriteBackFallback(
    text: String,
    operation: TextWriteBackOperation,
    originalCharacterCount: Int,
    title: String,
    reason: String
  ) {
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(text, forType: .string)
    let diagnostic = TextWriteBackFallbackDiagnostic(
      operation: operation,
      targetState: TextWriteBackRecord.resolvedTargetState(
        processIdentifier: previousApp?.processIdentifier,
        isTerminated: previousApp?.isTerminated ?? false
      ),
      targetName: previousApp?.localizedName,
      reason: reason,
      copiedToPasteboard: true,
      originalCharacterCount: originalCharacterCount,
      payloadCharacterCount: text.count)
    lastWriteBackStatusSummary = diagnostic.diagnosticSummary
    presentWriteBackNotice(
      title: title,
      message: diagnostic.noticeMessage,
      showsDiagnosticsButton: true)
  }

  func handleUnsafePasteboardWriteBack(
    operation: TextWriteBackOperation,
    originalCharacterCount: Int,
    payloadCharacterCount: Int,
    snapshot: PasteboardSnapshot
  ) {
    let diagnostic = TextWriteBackFallbackDiagnostic(
      operation: operation,
      targetState: TextWriteBackRecord.resolvedTargetState(
        processIdentifier: previousApp?.processIdentifier,
        isTerminated: previousApp?.isTerminated ?? false
      ),
      targetName: previousApp?.localizedName,
      reason:
        "\(snapshot.recoveryMessage) reason=\(snapshot.reasonCode), bytes=\(snapshot.totalByteCount), items=\(snapshot.itemCount), types=\(snapshot.typeCount)",
      copiedToPasteboard: false,
      originalCharacterCount: originalCharacterCount,
      payloadCharacterCount: payloadCharacterCount,
      recoveryOverride: snapshot.recoveryMessage)
    lastWriteBackStatusSummary = diagnostic.diagnosticSummary
    presentWriteBackNotice(
      title: "已取消自动写回",
      message: diagnostic.noticeMessage,
      showsDiagnosticsButton: true)
  }

  func presentWriteBackNotice(
    title: String,
    message: String,
    showsDiagnosticsButton: Bool = false
  ) {
    let alert = NSAlert()
    alert.messageText = title
    alert.informativeText = message
    alert.alertStyle = .informational
    alert.addButton(withTitle: "好")
    if showsDiagnosticsButton {
      alert.addButton(withTitle: "打开权限健康中心")
    }
    NSApp.activate(ignoringOtherApps: true)
    if alert.runModal() == .alertSecondButtonReturn,
      showsDiagnosticsButton
    {
      openPermissionHealth()
    }
  }

  func recordWriteBack(
    targetApp: NSRunningApplication?,
    operation: TextWriteBackOperation = .replace,
    original: String,
    replacement: String,
    selectionSnapshot: TextSelectionSnapshot? = nil,
    sourceWasVerified: Bool = true
  ) {
    lastWriteBackRecord = TextWriteBackRecord(
      targetApp: targetApp,
      operation: operation,
      originalText: original,
      replacementText: replacement,
      selectionSnapshot: selectionSnapshot,
      sourceWasVerified: sourceWasVerified)
    lastWriteBackStatusSummary = lastWriteBackRecord?.diagnosticSummary
    buildMenu()
    installMainMenu()
  }

  func currentWriteBackStatusSummary() -> String? {
    WriteBackCommandFactory.statusSummary(
      for: lastWriteBackRecord?.writeBackCommandInput,
      fallback: lastWriteBackStatusSummary)
  }

  func recordTextCaptureOutcome(_ outcome: TextCaptureOutcome) {
    let characterCount = outcome.usableText?.count ?? 0
    let diagnostic =
      characterCount > 0
      ? TextCaptureDiagnostic.captured(
        accessibilityGranted: TextCapture.hasAccessibilityPermission(),
        preferAX: settings.useAXFirst,
        frontmostAppName: previousApp?.localizedName,
        characterCount: characterCount,
        method: outcome.method.diagnosticMethod,
        clipboardWaitAttempts: outcome.clipboardWaitAttempts)
      : TextCaptureDiagnostic.noSelection(
        accessibilityGranted: TextCapture.hasAccessibilityPermission(),
        preferAX: settings.useAXFirst,
        frontmostAppName: previousApp?.localizedName,
        failureReason: outcome.failureReason.diagnosticFailureReason,
        pasteboardReasonCode: outcome.pasteboardReasonCode,
        clipboardWaitAttempts: outcome.clipboardWaitAttempts)
    lastTextCaptureStatusSummary = diagnostic.diagnosticSummary
  }

  func currentTextCaptureStatusSummary() -> String? {
    lastTextCaptureStatusSummary
  }

  func undoWriteBackMenuTitle() -> String {
    WriteBackCommandFactory.undoMenuTitle(for: lastWriteBackRecord?.writeBackCommandInput)
  }

  @objc func undoLastWriteBackFromMenu(_ sender: Any?) {
    undoLastWriteBack()
  }

  func undoLastWriteBack() {
    guard let record = lastWriteBackRecord else {
      lastWriteBackRecord = nil
      buildMenu()
      installMainMenu()
      return
    }
    guard record.isUndoAvailable else {
      lastWriteBackStatusSummary = record.diagnosticSummary
      lastWriteBackRecord = nil
      buildMenu()
      installMainMenu()
      return
    }
    lastWriteBackRecord = nil
    buildMenu()
    installMainMenu()
    guard let target = validatedUndoTarget(for: record) else {
      let reason = undoTargetUnavailableReason(for: record)
      let copiedOriginal = record.operation == .replace && !record.originalText.isEmpty
      if copiedOriginal {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(record.originalText, forType: .string)
      }
      let diagnostic = TextWriteBackUndoFallbackDiagnostic(
        record: record.logicState,
        reason: reason,
        copiedOriginalToPasteboard: copiedOriginal)
      lastWriteBackStatusSummary = diagnostic.diagnosticSummary
      presentWriteBackNotice(
        title: "无法自动撤销写回",
        message: diagnostic.noticeMessage)
      return
    }
    TextEditTransaction(targetApp: target, selectionSnapshot: record.selectionSnapshot)
      .replace(original: record.replacementText, with: record.originalText) { [weak self] in
        self?.lastWriteBackStatusSummary =
          "state=undo-completed, operation=\(record.operation.diagnosticName)"
      } failure: { [weak self] snapshot in
        self?.handleUnsafePasteboardUndo(
          record: record,
          snapshot: snapshot)
      } validationFailure: { [weak self] reason in
        self?.lastWriteBackStatusSummary = "state=undo-blocked, reason=\(reason.rawValue)"
        self?.presentWriteBackNotice(
          title: "已取消自动撤销写回",
          message: "\(reason.recoveryMessage)\n\n请在原应用使用系统撤销，或从历史记录中找回替换前内容。")
      }
  }

  func handleUnsafePasteboardUndo(
    record: TextWriteBackRecord,
    snapshot: PasteboardSnapshot
  ) {
    let diagnostic = TextWriteBackUndoFallbackDiagnostic(
      record: record.logicState,
      reason:
        "\(snapshot.undoRecoveryMessage) reason=\(snapshot.reasonCode), bytes=\(snapshot.totalByteCount), items=\(snapshot.itemCount), types=\(snapshot.typeCount)",
      copiedOriginalToPasteboard: false,
      recoveryOverride: snapshot.undoRecoveryMessage
    )
    lastWriteBackStatusSummary = diagnostic.diagnosticSummary
    presentWriteBackNotice(
      title: "已取消自动撤销写回",
      message: diagnostic.noticeMessage,
      showsDiagnosticsButton: true)
  }

  func validatedUndoTarget(for record: TextWriteBackRecord) -> NSRunningApplication? {
    guard record.isUndoAvailable,
      let target = record.targetApp,
      !target.isTerminated,
      target.processIdentifier != ProcessInfo.processInfo.processIdentifier
    else {
      return nil
    }
    return target
  }

  func undoTargetUnavailableReason(for record: TextWriteBackRecord) -> String {
    switch record.undoState() {
    case .expired:
      return "上次写回记录已过期。"
    case .missingOriginal:
      return "缺少可恢复的原文。"
    case .missingReplacement:
      return "缺少上次写回内容。"
    case .targetTerminated:
      return "原应用已退出。"
    case .targetIsCurrentApp:
      return "目标应用是 SnapAI 自身。"
    case .available:
      return "原应用目标不可用。"
    }
  }
}
