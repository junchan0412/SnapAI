import Foundation

public enum FollowUpReturnKeyBehavior: String, Equatable {
    case submit
    case insertNewline
}

public enum FollowUpInputBehavior {
    public static let placeholder = "追问…"
    public static let accessibilityLabel = "追问输入框"
    public static let helpText = "Return 发送追问; Shift+Return 或 Option+Return 换行"
    public static let minHeight: Double = 34
    public static let maxHeight: Double = 88

    public static func returnKeyBehavior(shift: Bool,
                                         option: Bool) -> FollowUpReturnKeyBehavior {
        (shift || option) ? .insertNewline : .submit
    }

    public static func shouldBrowseHistory(currentText: String) -> Bool {
        currentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
