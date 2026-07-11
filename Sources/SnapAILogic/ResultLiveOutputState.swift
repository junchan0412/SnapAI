import Combine

public final class ResultOutputState: ObservableObject {
    @Published public private(set) var text: String

    public init(text: String = "") {
        self.text = text
    }

    @discardableResult
    public func replace(with text: String) -> Bool {
        guard self.text != text else { return false }
        self.text = text
        return true
    }
}

public final class ResultThinkingState: ObservableObject {
    @Published public private(set) var text: String

    public init(text: String = "") {
        self.text = text
    }

    @discardableResult
    public func replace(with text: String) -> Bool {
        guard self.text != text else { return false }
        self.text = text
        return true
    }
}
