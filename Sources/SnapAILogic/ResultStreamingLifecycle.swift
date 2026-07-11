public enum ResultStreamingDrain: Equatable {
    case waiting
    case chunk(String)
    case finished
}

/// 统一管理流式文本解析、打字机待展示队列和结束状态。
public struct ResultStreamingLifecycle {
    private var accumulator = StreamingAccumulator()
    private var typewriterBuffer = TypewriterBuffer()
    private var streamFinished = false

    public init() {}

    public var completeText: String { accumulator.outputText }
    public var thinkingText: String { accumulator.thinkingText }

    public mutating func reset() {
        accumulator.resetForFallback()
        typewriterBuffer.removeAll()
        streamFinished = false
    }

    /// 返回无需打字机时应立即展示的可见增量；启用打字机时只入队并返回 nil。
    public mutating func appendContentToken(_ token: String,
                                            extractsThinkTags: Bool,
                                            usesTypewriter: Bool) -> String? {
        let visibleText = accumulator.appendContentToken(token,
                                                         extractsThinkTags: extractsThinkTags)
        if usesTypewriter {
            typewriterBuffer.enqueue(visibleText)
            return nil
        }
        return visibleText
    }

    @discardableResult
    public mutating func appendExternalThinking(_ text: String) -> String {
        accumulator.appendExternalThinking(text)
        return accumulator.thinkingText
    }

    /// 标记 provider stream 已结束，并冲刷可能残留的半截 think tag。
    public mutating func finish(usesTypewriter: Bool) -> String? {
        let finalVisibleText = accumulator.finish()
        streamFinished = true
        if usesTypewriter {
            typewriterBuffer.enqueue(finalVisibleText)
            return nil
        }
        return finalVisibleText
    }

    public mutating func dequeue(maxCharacters: Int) -> ResultStreamingDrain {
        let chunk = typewriterBuffer.dequeue(maxCharacters: maxCharacters)
        if !chunk.isEmpty {
            return .chunk(chunk)
        }
        if streamFinished && typewriterBuffer.isEmpty {
            return .finished
        }
        return .waiting
    }

    /// 取消或失败时丢弃尚未逐字展示的队列，调用方可直接展示 completeText。
    public mutating func discardPendingPresentation() {
        typewriterBuffer.removeAll()
        streamFinished = false
    }
}
