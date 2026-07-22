import Foundation
import SnapAILogic

@MainActor
extension ResultViewModel {
    /// #5 浏览追问历史
    func followUpHistoryUp() {
        if FollowUpInputBehavior.shouldBrowseHistory(currentText: followUp) {
            followUpHistory.resetNavigation()
        }
        guard let previous = followUpHistory.previous() else { return }
        followUp = previous
    }

    func followUpHistoryDown() {
        guard let next = followUpHistory.next() else { return }
        followUp = next
    }

    func shouldHandleFollowUpHistoryNavigation(currentText: String,
                                               direction: FollowUpHistoryNavigationDirection) -> Bool {
        followUpHistory.shouldHandleNavigation(currentText: currentText,
                                               direction: direction)
    }
}
