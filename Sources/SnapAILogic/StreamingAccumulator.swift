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

    public mutating func appendContentToken(_ token: String, extractsThinkTags: Bool) {
        guard extractsThinkTags else {
            outputText += token
            return
        }

        var remaining = bufferedTagFragment + token
        bufferedTagFragment = ""

        while !remaining.isEmpty {
            if inThinkTag {
                consumeThinkingText(from: &remaining)
            } else {
                consumeOutputText(from: &remaining)
            }
        }
    }

    public mutating func appendExternalThinking(_ text: String) {
        thinkingText += text
    }

    public mutating func finish() {
        guard !bufferedTagFragment.isEmpty else { return }
        if inThinkTag {
            thinkingText += bufferedTagFragment
        } else {
            outputText += bufferedTagFragment
        }
        bufferedTagFragment = ""
    }

    public mutating func resetForFallback() {
        outputText = ""
        thinkingText = ""
        inThinkTag = false
        bufferedTagFragment = ""
    }

    private mutating func consumeOutputText(from remaining: inout String) {
        let startTag = "<think>"
        if let start = remaining.range(of: startTag) {
            outputText += String(remaining[remaining.startIndex..<start.lowerBound])
            remaining = String(remaining[start.upperBound...])
            inThinkTag = true
            return
        }

        if let length = remaining.partialSuffixLength(matchingPrefixOf: startTag) {
            let split = remaining.index(remaining.endIndex, offsetBy: -length)
            outputText += String(remaining[..<split])
            bufferedTagFragment = String(remaining[split...])
            remaining = ""
            return
        }

        outputText += remaining
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
