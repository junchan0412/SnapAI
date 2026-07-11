public struct ResultCompletionLifecycle: Equatable {
    public private(set) var isFinished = false
    public private(set) var isHistorySaved = false

    public init() {}

    public mutating func reset() {
        isFinished = false
        isHistorySaved = false
    }

    @discardableResult
    public mutating func beginCompletion() -> Bool {
        guard !isFinished else { return false }
        isFinished = true
        return true
    }

    public mutating func updateHistorySaved(_ saved: Bool) {
        isHistorySaved = isHistorySaved || saved
    }
}
