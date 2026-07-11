import Foundation

public enum ResultContentRenderMode: Equatable {
    case empty
    case waiting
    case streamingText
    case markdown

    public static func resolve(text: String,
                               isStreaming: Bool) -> ResultContentRenderMode {
        if text.isEmpty {
            return isStreaming ? .waiting : .empty
        }
        return isStreaming ? .streamingText : .markdown
    }
}

public enum ResultAutoScrollPolicy {
    public static let streamingMinimumInterval: TimeInterval = 1.0 / 30.0

    public static func shouldScroll(lastScrollTime: TimeInterval,
                                    currentTime: TimeInterval,
                                    isStreaming: Bool) -> Bool {
        guard isStreaming else { return true }
        return max(0, currentTime - lastScrollTime) >= streamingMinimumInterval
    }
}
