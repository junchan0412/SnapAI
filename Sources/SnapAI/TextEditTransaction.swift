import AppKit
import SnapAILogic

/// AppKit 运行对象与纯写回状态之间的窄桥接。
struct TextWriteBackRecord {
  static let expirationInterval = TextWriteBackRecordState.expirationInterval

  let targetApp: NSRunningApplication?
  let operation: TextWriteBackOperation
  let originalText: String
  let replacementText: String
  let createdAt: Date
  let selectionSnapshot: TextSelectionSnapshot?
  let sourceWasVerified: Bool

  init(
    targetApp: NSRunningApplication?,
    operation: TextWriteBackOperation = .replace,
    originalText: String,
    replacementText: String,
    createdAt: Date = Date(),
    selectionSnapshot: TextSelectionSnapshot? = nil,
    sourceWasVerified: Bool = true
  ) {
    self.targetApp = targetApp
    self.operation = operation
    self.originalText = originalText
    self.replacementText = replacementText
    self.createdAt = createdAt
    self.selectionSnapshot = selectionSnapshot
    self.sourceWasVerified = sourceWasVerified
  }

  var logicState: TextWriteBackRecordState {
    TextWriteBackRecordState(
      targetName: targetApp?.localizedName,
      targetState: targetState,
      operation: operation,
      originalText: originalText,
      replacementText: replacementText,
      createdAt: createdAt
    )
  }

  var isUndoAvailable: Bool { logicState.isUndoAvailable }
  var targetState: TextWriteBackTargetState {
    Self.resolvedTargetState(
      processIdentifier: targetApp?.processIdentifier,
      isTerminated: targetApp?.isTerminated ?? false)
  }

  static func resolvedTargetState(
    processIdentifier: pid_t?,
    isTerminated: Bool,
    currentProcessIdentifier: pid_t = ProcessInfo.processInfo.processIdentifier
  ) -> TextWriteBackTargetState {
    TextWriteBackStateResolver.targetState(
      processIdentifier: processIdentifier,
      isTerminated: isTerminated,
      currentProcessIdentifier: currentProcessIdentifier
    )
  }

  func undoState(at date: Date = Date()) -> TextWriteBackUndoState {
    logicState.undoState(at: date)
  }

  var undoTitle: String { logicState.undoTitle }
  var diagnosticSummary: String {
    let validation = operation == .append ? "not-applicable"
      : (sourceWasVerified ? "verified" : "unverified-confirmed")
    return logicState.diagnosticSummary + ", sourceValidation=\(validation)"
  }
  var recoverySuggestion: String { logicState.recoverySuggestion }
}

@MainActor
struct TextEditTransaction {
  var targetApp: NSRunningApplication?
  var selectionSnapshot: TextSelectionSnapshot?
  var allowsUnverifiedReplacement = false
  var confirmedTargetSnapshot: TextWriteBackTargetSnapshot?
  var additionalTargetValidation: (() -> TextWriteBackValidationFailure?)? = nil
  var focusDelay: TimeInterval = 0.18
  var restoreDelay: TimeInterval = 0.35

  func replace(
    original: String,
    with text: String,
    completion: (() -> Void)? = nil,
    failure: ((PasteboardSnapshot) -> Void)? = nil,
    validationFailure: ((TextWriteBackValidationFailure) -> Void)? = nil
  ) {
    paste(text) {
      if let failure = replacementValidationFailure(original: original, restoresSelection: true) {
        return .failure(failure)
      }
      return .success(0.08)
    } validateBeforePaste: {
      replacementValidationFailure(original: original, restoresSelection: false)
    } completion: {
      completion?()
    } failure: { snapshot in
      failure?(snapshot)
    } validationFailure: { reason in
      validationFailure?(reason)
    }
  }

  private func replacementValidationFailure(original: String,
                                            restoresSelection: Bool) -> TextWriteBackValidationFailure? {
    guard let targetApp else { return .targetChanged }
    let targetPID = targetApp.processIdentifier
    let targetFailure = confirmedTargetSnapshot?.validationFailure(targetPID: targetPID)
    if let targetFailure, targetFailure != .unavailable { return targetFailure }
    let sourceFailure: TextWriteBackValidationFailure?
    if let selectionSnapshot {
      sourceFailure = restoresSelection
        ? selectionSnapshot.restoreSelection(original: original, targetPID: targetPID)
        : selectionSnapshot.validationFailure(original: original, targetPID: targetPID)
    } else {
      sourceFailure = .unavailable
    }
    if let sourceFailure, sourceFailure != .unavailable { return sourceFailure }
    let failure = targetFailure ?? sourceFailure
    if failure == .unavailable {
      let currentFailure = TextCapture.unanchoredReplacementValidationFailure(
        original: original, targetPID: targetPID)
      switch currentFailure {
      case .unavailable: break
      default: return currentFailure
      }
    }
    return TextWriteBackSourceValidation.requiresBlocking(
      failure, allowsUnverifiedReplacement: allowsUnverifiedReplacement) ? failure : nil
  }

  func append(
    _ text: String,
    completion: (() -> Void)? = nil,
    failure: ((PasteboardSnapshot) -> Void)? = nil,
    validationFailure: ((TextWriteBackValidationFailure) -> Void)? = nil
  ) {
    paste(TextWriteBackPayload.appendPayload(for: text)) {
      TextCapture.sendRightArrow()
      return .success(0.05)
    } completion: {
      completion?()
    } failure: { snapshot in
      failure?(snapshot)
    } validationFailure: { reason in
      validationFailure?(reason)
    }
  }

  private func paste(
    _ text: String,
    beforePaste: (() -> Result<TimeInterval, TextWriteBackValidationFailure>)? = nil,
    validateBeforePaste: (() -> TextWriteBackValidationFailure?)? = nil,
    completion: (() -> Void)? = nil,
    failure: ((PasteboardSnapshot) -> Void)? = nil,
    validationFailure: ((TextWriteBackValidationFailure) -> Void)? = nil
  ) {
    let pasteboard = NSPasteboard.general
    let previousSnapshot = TextCapture.snapshotPasteboard(pasteboard)
    guard previousSnapshot.canRestore else {
      failure?(previousSnapshot)
      return
    }
    pasteboard.clearContents()
    pasteboard.setString(text, forType: .string)
    let injectedChangeCount = pasteboard.changeCount

    targetApp?.activate()
    DispatchQueue.main.asyncAfter(deadline: .now() + focusDelay) {
      let abort: (TextWriteBackValidationFailure) -> Void = { reason in
        let reportedReason = TextWriteBackSourceValidation.pasteboardFailure(
          expectedChangeCount: injectedChangeCount, currentChangeCount: pasteboard.changeCount) ?? reason
        TextCapture.restorePasteboardIfUnchanged(
          pasteboard,
          snapshot: previousSnapshot,
          expectedChangeCount: injectedChangeCount)
        TextCapture.clearRecentSelectionSnapshot()
        validationFailure?(reportedReason)
      }
      guard let targetApp,
        !targetApp.isTerminated,
        NSWorkspace.shared.frontmostApplication?.processIdentifier == targetApp.processIdentifier
      else {
        abort(.targetChanged)
        return
      }
      if let reason = additionalTargetValidation?() {
        abort(reason)
        return
      }
      let pasteDelay: TimeInterval
      switch beforePaste?() ?? .success(0) {
      case .success(let delay): pasteDelay = delay
      case .failure(let reason):
        abort(reason)
        return
      }
      DispatchQueue.main.asyncAfter(deadline: .now() + pasteDelay) {
        guard !targetApp.isTerminated,
          NSWorkspace.shared.frontmostApplication?.processIdentifier == targetApp.processIdentifier
        else {
          abort(.targetChanged)
          return
        }
        if let reason = additionalTargetValidation?() {
          abort(reason)
          return
        }
        if let reason = validateBeforePaste?() {
          abort(reason)
          return
        }
        if let reason = TextWriteBackSourceValidation.pasteboardFailure(
          expectedChangeCount: injectedChangeCount, currentChangeCount: pasteboard.changeCount) {
          abort(reason)
          return
        }
        TextCapture.sendCmdV()
        DispatchQueue.main.asyncAfter(deadline: .now() + restoreDelay) {
          TextCapture.restorePasteboardIfUnchanged(
            pasteboard,
            snapshot: previousSnapshot,
            expectedChangeCount: injectedChangeCount
          )
          TextCapture.clearRecentSelectionSnapshot()
          completion?()
        }
      }
    }
  }
}
