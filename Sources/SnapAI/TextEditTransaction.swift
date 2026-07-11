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

  init(
    targetApp: NSRunningApplication?,
    operation: TextWriteBackOperation = .replace,
    originalText: String,
    replacementText: String,
    createdAt: Date = Date()
  ) {
    self.targetApp = targetApp
    self.operation = operation
    self.originalText = originalText
    self.replacementText = replacementText
    self.createdAt = createdAt
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
  var diagnosticSummary: String { logicState.diagnosticSummary }
  var recoverySuggestion: String { logicState.recoverySuggestion }
}

@MainActor
struct TextEditTransaction {
  var targetApp: NSRunningApplication?
  var selectionSnapshot: TextSelectionSnapshot?
  var assumeSelectionIsPreserved = false
  var focusDelay: TimeInterval = 0.18
  var restoreDelay: TimeInterval = 0.35

  func replace(
    original: String,
    with text: String,
    completion: (() -> Void)? = nil,
    failure: ((PasteboardSnapshot) -> Void)? = nil
  ) {
    paste(text) {
      let hasAccessibleSelection = TextCapture.selectedTextViaAX()?.isEmpty == false
      let restoredSnapshot =
        hasAccessibleSelection ? false : selectionSnapshot?.restoreSelection() == true
      return TextEditTiming.replacementPreparationDelay(
        hasAccessibleSelection: hasAccessibleSelection,
        restoredSnapshot: restoredSnapshot,
        assumeSelectionIsPreserved: assumeSelectionIsPreserved
      )
    } completion: {
      completion?()
    } failure: { snapshot in
      failure?(snapshot)
    }
  }

  func append(
    _ text: String,
    completion: (() -> Void)? = nil,
    failure: ((PasteboardSnapshot) -> Void)? = nil
  ) {
    paste(TextWriteBackPayload.appendPayload(for: text)) {
      TextCapture.sendRightArrow()
      return 0.05
    } completion: {
      completion?()
    } failure: { snapshot in
      failure?(snapshot)
    }
  }

  private func paste(
    _ text: String,
    beforePaste: (() -> TimeInterval)? = nil,
    completion: (() -> Void)? = nil,
    failure: ((PasteboardSnapshot) -> Void)? = nil
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
      let pasteDelay = beforePaste?() ?? 0
      DispatchQueue.main.asyncAfter(deadline: .now() + pasteDelay) {
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
