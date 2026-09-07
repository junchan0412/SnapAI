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

        let input = bufferedTagFragment.isEmpty ? token : bufferedTagFragment + token
        var remaining = input[...]
        bufferedTagFragment = ""
        var visibleText = ""

        while !remaining.isEmpty {
            let marker = inThinkTag ? "</think>" : "<think>"
            if let range = remaining.range(of: marker) {
                append(remaining[..<range.lowerBound], visibleText: &visibleText)
                remaining = remaining[range.upperBound...]
                inThinkTag.toggle()
            } else {
                let fragmentLength = remaining.partialSuffixLength(matchingPrefixOf: marker)
                let split = remaining.index(remaining.endIndex, offsetBy: -fragmentLength)
                append(remaining[..<split], visibleText: &visibleText)
                bufferedTagFragment = String(remaining[split...])
                break
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

    private mutating func append(_ text: Substring, visibleText: inout String) {
        if inThinkTag {
            thinkingText.append(contentsOf: text)
        } else {
            outputText.append(contentsOf: text)
            visibleText.append(contentsOf: text)
        }
    }
}

private extension Substring {
    func partialSuffixLength(matchingPrefixOf marker: String) -> Int {
        let maxLength = marker.count - 1
        for length in stride(from: maxLength, through: 1, by: -1) {
            if hasSuffix(marker.prefix(length)) {
                return length
            }
        }
        return 0
    }
}
