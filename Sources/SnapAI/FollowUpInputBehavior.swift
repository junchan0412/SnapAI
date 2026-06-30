import Foundation

enum FollowUpReturnKeyBehavior: String, Equatable {
    case submit
    case insertNewline
}

enum FollowUpInputBehavior {
    static let placeholder = "追问…"
    static let accessibilityLabel = "追问输入框"
    static let helpText = "Return 发送追问; Shift+Return 或 Option+Return 换行"
    static let minHeight: Double = 34
    static let maxHeight: Double = 88

    static func returnKeyBehavior(shift: Bool,
                                  option: Bool) -> FollowUpReturnKeyBehavior {
        (shift || option) ? .insertNewline : .submit
    }

    static func shouldBrowseHistory(currentText: String) -> Bool {
        currentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
