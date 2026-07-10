import SnapAILogic

extension TextWriteBackOperation {
    var writeBackCommandOperation: WriteBackCommandOperation {
        switch self {
        case .replace:
            return .replace
        case .append:
            return .append
        }
    }
}

extension TextWriteBackRecord {
    var writeBackCommandInput: WriteBackCommandInput {
        WriteBackCommandInput(
            undoTitle: undoTitle,
            operation: operation.writeBackCommandOperation,
            diagnosticSummary: diagnosticSummary,
            isUndoAvailable: isUndoAvailable
        )
    }
}
