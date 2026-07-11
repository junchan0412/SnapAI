import Combine

public struct ResultDiagnosticTextSnapshot: Equatable {
    public var fullText: String
    public var briefText: String

    public init(fullText: String = "", briefText: String = "") {
        self.fullText = fullText
        self.briefText = briefText
    }

    public static let empty = ResultDiagnosticTextSnapshot()
}

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
