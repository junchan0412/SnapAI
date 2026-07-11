import SnapAILogic

extension TextWriteBackRecord {
  var writeBackCommandInput: WriteBackCommandInput {
    WriteBackCommandInput(
      undoTitle: undoTitle,
      operation: operation,
      diagnosticSummary: diagnosticSummary,
      isUndoAvailable: isUndoAvailable
    )
  }
}
