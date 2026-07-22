import Foundation
import SnapAILogic

@MainActor
extension ResultViewModel {

    func dismissIncompleteResultNotice() {
        incompleteResultReason = nil
    }

    func showTransientNotice(_ message: String, autoDismiss: TimeInterval = 3.0) {
        transientNoticeWork?.cancel()
        transientNotice = message
        let work = DispatchWorkItem { [weak self] in self?.transientNotice = nil }
        transientNoticeWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + autoDismiss, execute: work)
    }

    func dismissTransientNotice() {
        transientNoticeWork?.cancel()
        transientNotice = nil
    }
}
