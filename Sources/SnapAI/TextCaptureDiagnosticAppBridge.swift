import Foundation
import SnapAILogic

extension TextCaptureMethod {
    var diagnosticMethod: TextCaptureDiagnosticMethod {
        switch self {
        case .accessibility:
            return .accessibility
        case .clipboard:
            return .clipboard
        case .service:
            return .service
        }
    }
}

extension TextCaptureFailureReason {
    var diagnosticFailureReason: TextCaptureDiagnosticFailureReason {
        switch self {
        case .accessibilityEmptySelection:
            return .accessibilityEmptySelection
        case .pasteboardSnapshotUnsafe:
            return .pasteboardSnapshotUnsafe
        case .clipboardUnchanged:
            return .clipboardUnchanged
        case .clipboardEmpty:
            return .clipboardEmpty
        }
    }
}

extension Optional where Wrapped == TextCaptureMethod {
    var diagnosticMethod: TextCaptureDiagnosticMethod? {
        map(\.diagnosticMethod)
    }
}

extension Optional where Wrapped == TextCaptureFailureReason {
    var diagnosticFailureReason: TextCaptureDiagnosticFailureReason? {
        map(\.diagnosticFailureReason)
    }
}
