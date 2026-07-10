import Foundation

public struct StreamingAccumulator: Equatable {
    public var outputText: String
    public var thinkingText: String

    private var inThinkTag = false
    private var bufferedTagFragment = ""

    public init(outputText: String = "", thinkingText: String = "") {
        self.outputText = outputText
        self.thinkingText = thinkingText
    }

    @discardableResult
    public mutating func appendContentToken(_ token: String, extractsThinkTags: Bool) -> String {
        guard extractsThinkTags else {
            outputText += token
            return token
        }

        var remaining = bufferedTagFragment + token
        bufferedTagFragment = ""
        var visibleText = ""

        while !remaining.isEmpty {
            if inThinkTag {
                consumeThinkingText(from: &remaining)
            } else {
                consumeOutputText(from: &remaining, visibleText: &visibleText)
            }
        }
        return visibleText
    }

    public mutating func appendExternalThinking(_ text: String) {
        thinkingText += text
    }

    @discardableResult
    public mutating func finish() -> String {
        guard !bufferedTagFragment.isEmpty else { return "" }
        let visibleText: String
        if inThinkTag {
            thinkingText += bufferedTagFragment
            visibleText = ""
        } else {
            outputText += bufferedTagFragment
            visibleText = bufferedTagFragment
        }
        bufferedTagFragment = ""
        return visibleText
    }

    public mutating func resetForFallback() {
        outputText = ""
        thinkingText = ""
        inThinkTag = false
        bufferedTagFragment = ""
    }

    private mutating func consumeOutputText(from remaining: inout String,
                                            visibleText: inout String) {
        let startTag = "<think>"
        if let start = remaining.range(of: startTag) {
            let text = String(remaining[remaining.startIndex..<start.lowerBound])
            outputText += text
            visibleText += text
            remaining = String(remaining[start.upperBound...])
            inThinkTag = true
            return
        }

        if let length = remaining.partialSuffixLength(matchingPrefixOf: startTag) {
            let split = remaining.index(remaining.endIndex, offsetBy: -length)
            let text = String(remaining[..<split])
            outputText += text
            visibleText += text
            bufferedTagFragment = String(remaining[split...])
            remaining = ""
            return
        }

        outputText += remaining
        visibleText += remaining
        remaining = ""
    }

    private mutating func consumeThinkingText(from remaining: inout String) {
        let endTag = "</think>"
        if let end = remaining.range(of: endTag) {
            thinkingText += String(remaining[remaining.startIndex..<end.lowerBound])
            remaining = String(remaining[end.upperBound...])
            inThinkTag = false
            return
        }

        if let length = remaining.partialSuffixLength(matchingPrefixOf: endTag) {
            let split = remaining.index(remaining.endIndex, offsetBy: -length)
            thinkingText += String(remaining[..<split])
            bufferedTagFragment = String(remaining[split...])
            remaining = ""
            return
        }

        thinkingText += remaining
        remaining = ""
    }
}

private extension String {
    func partialSuffixLength(matchingPrefixOf marker: String) -> Int? {
        let maxLength = min(count, marker.count - 1)
        guard maxLength > 0 else { return nil }
        for length in stride(from: maxLength, through: 1, by: -1) {
            let markerPrefixEnd = marker.index(marker.startIndex, offsetBy: length)
            let markerPrefix = String(marker[..<markerPrefixEnd])
            if hasSuffix(markerPrefix) {
                return length
            }
        }
        return nil
    }
}
