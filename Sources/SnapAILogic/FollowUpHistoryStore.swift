import Foundation

public enum FollowUpHistoryNavigationDirection: Equatable {
    case up
    case down
}

public struct FollowUpHistoryStore: Equatable {
    public static let defaultLimit = 50
    public static let maxEntryCharacters = 4_000
    private static let truncationMarker = "..."

    public private(set) var entries: [String] = []
    public private(set) var selectedIndex: Int?
    public var limit: Int = defaultLimit

    public init(limit: Int = defaultLimit) {
        self.limit = limit
    }

    public var count: Int { entries.count }
    public var effectiveLimit: Int { max(1, limit) }

    public var selectedText: String? {
        guard let selectedIndex,
              entries.indices.contains(selectedIndex) else {
            return nil
        }
        return entries[selectedIndex]
    }

    public mutating func record(_ rawText: String) {
        let text = Self.normalizedForStorage(rawText)
        guard !text.isEmpty else { return }
        entries.removeAll { $0 == text }
        entries.append(text)
        enforceLimit()
        selectedIndex = nil
    }

    public mutating func previous() -> String? {
        guard !entries.isEmpty else { return nil }
        if let selectedIndex {
            self.selectedIndex = max(entries.startIndex, selectedIndex - 1)
        } else {
            selectedIndex = entries.index(before: entries.endIndex)
        }
        return selectedText
    }

    public mutating func next() -> String? {
        guard let selectedIndex else { return nil }
        if selectedIndex < entries.index(before: entries.endIndex) {
            self.selectedIndex = selectedIndex + 1
            return selectedText
        }
        self.selectedIndex = nil
        return ""
    }

    public mutating func resetNavigation() {
        selectedIndex = nil
    }

    public func shouldHandleNavigation(currentText: String,
                                       direction: FollowUpHistoryNavigationDirection) -> Bool {
        guard !entries.isEmpty else { return false }
        let isBlank = FollowUpInputBehavior.shouldBrowseHistory(currentText: currentText)
        if isBlank {
            return direction == .up
        }
        guard let selectedText else { return false }
        return currentText == selectedText
    }

    private mutating func enforceLimit() {
        let safeLimit = effectiveLimit
        if entries.count > safeLimit {
            entries.removeFirst(entries.count - safeLimit)
        }
    }

    private static func normalizedForStorage(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > maxEntryCharacters else { return trimmed }
        let visibleLimit = max(0, maxEntryCharacters - truncationMarker.count)
        return String(trimmed.prefix(visibleLimit)) + truncationMarker
    }
}
