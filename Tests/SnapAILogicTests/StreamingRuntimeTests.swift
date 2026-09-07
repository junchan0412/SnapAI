import Foundation
#if !SNAPAI_MANUAL_TEST_MAIN
@testable import SnapAILogic
#endif

private func runtimeEvents(_ text: String) throws -> [ServerSentEvent] {
    var parser = ServerSentEventParser()
    var events: [ServerSentEvent] = []
    for byte in text.utf8 {
        if let event = try parser.append(byte) { events.append(event) }
    }
    if let event = try parser.finish() { events.append(event) }
    return events
}

private func expectStreamFailure(_ expected: AIStreamDecodingError,
                                 _ message: String,
                                 operation: () throws -> Void) {
    do {
        try operation()
        expect(false, message)
    } catch {
        expect(error as? AIStreamDecodingError == expected, message)
    }
}

func testServerSentEventParserPreservesFramingAndUnicode() {
    do {
        let events = try runtimeEvents("\u{FEFF}: keepalive\r\nevent: content_block_delta\r\ndata: {\r\ndata: \"text\":\"你好 🌏\"}\r\n\r\n: ping\ndata:   spaced\n\ndata: [DONE]")
        expect(events == [ServerSentEvent(name: "content_block_delta", data: "{\n\"text\":\"你好 🌏\"}"),
                          ServerSentEvent(name: nil, data: "  spaced"),
                          ServerSentEvent(name: nil, data: "[DONE]")],
               "SSE preserves multiline data, UTF-8, CRLF boundaries, event names and trailing EOF data")
        let carriageReturnEvents = try runtimeEvents("event: unused\r\rdata: first\r\rdata: second\r\r")
        expect(carriageReturnEvents == [
            ServerSentEvent(name: nil, data: "first"), ServerSentEvent(name: nil, data: "second")
        ], "SSE supports lone CR and clears event names even when an event contains no data")
    } catch {
        expect(false, "valid SSE fixtures decode successfully")
    }
}

func testServerSentEventParserBoundsMalformedPayloads() {
    expectStreamFailure(.invalidEvent, "SSE rejects malformed UTF-8 without exposing the body") {
        var parser = ServerSentEventParser()
        _ = try parser.append(0xFF)
        _ = try parser.append(0x0A)
    }
    expectStreamFailure(.eventTooLarge, "SSE bounds a single line before unbounded allocation") {
        var parser = ServerSentEventParser()
        for _ in 0...ServerSentEventParser.maximumEventBytes { _ = try parser.append(0x61) }
    }
    expectStreamFailure(.eventTooLarge, "SSE bounds aggregate data across many lines") {
        _ = try runtimeEvents(String(repeating: "data: " + String(repeating: "x", count: 300_000) + "\n", count: 4))
    }
}

func testAIStreamDecoderDetectsIncompleteAndLimitedResponses() {
    do {
        var interrupted = AIStreamDecoder(apiProtocol: .openAI)
        let partial = try interrupted.decode(ServerSentEvent(data: #"{"choices":[{"delta":{"content":"partial"}}]}"#))
        expect(partial.content == "partial", "an interrupted response preserves text received before EOF")
        expectStreamFailure(.interrupted, "EOF without a provider completion marker is a failure") {
            try interrupted.validateCompletion()
        }
        _ = try interrupted.decode(ServerSentEvent(data: #"{"choices":[{"delta":{},"finish_reason":"stop"}]}"#))
        try interrupted.validateCompletion()
        expect(interrupted.isFinished, "compatible providers can finish without a redundant DONE event")

        var empty = AIStreamDecoder(apiProtocol: .openAI)
        _ = try empty.decode(ServerSentEvent(data: "[DONE]"))
        expectStreamFailure(.emptyResponse, "empty provider success is not treated as a usable answer") {
            try empty.validateCompletion()
        }

        var limited = AIStreamDecoder(apiProtocol: .openAI)
        let tail = try limited.decode(ServerSentEvent(data: #"{"choices":[{"delta":{"content":"last token"},"finish_reason":"length"}]}"#))
        expect(tail.content == "last token", "the final token is delivered before reporting output truncation")
        expectStreamFailure(.outputLimitReached, "token-limited output cannot trigger successful write-back") {
            try limited.validateCompletion()
        }

        var malformed = AIStreamDecoder(apiProtocol: .openAI)
        expectStreamFailure(.invalidEvent, "malformed events are not silently skipped") {
            _ = try malformed.decode(ServerSentEvent(data: "{broken"))
        }
        do {
            _ = try malformed.decode(ServerSentEvent(name: "error", data: #"{"message":"Overloaded"}"#))
            expect(false, "named SSE errors must fail the request")
        } catch {
            expect(error.localizedDescription.contains("Overloaded"),
                   "named SSE errors preserve a sanitized provider explanation")
        }
    } catch {
        expect(false, "completion marker fixtures decode successfully")
    }
}

func testAIStreamDecoderPreservesProtocolDeltas() {
    do {
        var openAI = AIStreamDecoder(apiProtocol: .openAI)
        let ping = try openAI.decode(ServerSentEvent(name: "ping", data: "keepalive"))
        expect(ping.isEmpty, "named keepalive events need no JSON payload")
        let reason = try openAI.decode(ServerSentEvent(data: #"{"choices":[{"delta":{"reasoning_content":"推理"}}]}"#))
        expect(reason == AIStreamDelta(content: "", thinking: "推理"),
               "OpenAI-compatible reasoning deltas are preserved separately")
        let events = try runtimeEvents("data: {\ndata: \"choices\": [{\"delta\": {\"content\": \"答案\"}}]}\n\ndata: [DONE]\n\n")
        let content = try events.map { try openAI.decode($0).content }.joined()
        expect(content == "答案", "multiline JSON event data produces a complete content delta")
        try openAI.validateCompletion()

        var anthropic = AIStreamDecoder(apiProtocol: .anthropic)
        let first = try anthropic.decode(ServerSentEvent(name: "content_block_start", data: #"{"content_block":{"type":"text","text":"开始"}}"#))
        let thinking = try anthropic.decode(ServerSentEvent(data: #"{"type":"content_block_delta","delta":{"type":"thinking_delta","thinking":"分析"}}"#))
        let next = try anthropic.decode(ServerSentEvent(data: #"{"type":"content_block_delta","delta":{"type":"text_delta","text":"结束"}}"#))
        _ = try anthropic.decode(ServerSentEvent(data: #"{"type":"message_delta","delta":{"stop_reason":"end_turn"}}"#))
        expectStreamFailure(.interrupted, "Anthropic requires message_stop before confirming completion") {
            try anthropic.validateCompletion()
        }
        _ = try anthropic.decode(ServerSentEvent(data: #"{"type":"message_stop"}"#))
        expect(first.content + next.content == "开始结束" && thinking.thinking == "分析",
               "Anthropic preserves both initial block content and incremental text/thinking")
        try anthropic.validateCompletion()

        var limited = AIStreamDecoder(apiProtocol: .anthropic)
        _ = try limited.decode(ServerSentEvent(data: #"{"type":"content_block_delta","delta":{"text":"部分"}}"#))
        _ = try limited.decode(ServerSentEvent(data: #"{"type":"message_delta","delta":{"stop_reason":"max_tokens"}}"#))
        _ = try limited.decode(ServerSentEvent(data: #"{"type":"message_delta","delta":{},"usage":{"output_tokens":2048}}"#))
        _ = try limited.decode(ServerSentEvent(data: #"{"type":"message_stop"}"#))
        expectStreamFailure(.outputLimitReached, "Anthropic max_tokens also marks partial output") {
            try limited.validateCompletion()
        }
    } catch {
        expect(false, "valid protocol delta fixtures decode successfully")
    }
}

func testStreamingAccumulatorHandlesEveryTagSplit() {
    let input = "前👨‍👩‍👧‍👦<think>分析 e\u{301}</think>中<think>继续</think>尾 <thi"
    for offset in 0...input.count {
        let split = input.index(input.startIndex, offsetBy: offset)
        var accumulator = StreamingAccumulator()
        let first = accumulator.appendContentToken(String(input[..<split]), extractsThinkTags: true)
        let second = accumulator.appendContentToken(String(input[split...]), extractsThinkTags: true)
        let final = accumulator.finish()
        expect(first + second + final == "前👨‍👩‍👧‍👦中尾 <thi",
               "think-tag extraction preserves visible Unicode at every possible token boundary")
        expect(accumulator.thinkingText == "分析 e\u{301}继续",
               "think-tag extraction preserves hidden Unicode at every possible token boundary")
    }
    var many = StreamingAccumulator()
    let repetitions = 2_000
    _ = many.appendContentToken(String(repeating: "答<think>想</think>", count: repetitions), extractsThinkTags: true)
    expect(many.outputText == String(repeating: "答", count: repetitions) &&
           many.thinkingText == String(repeating: "想", count: repetitions),
           "many think spans in one network chunk preserve text without tail rebuilding")
}

func testResultStreamingLifecycleSleepsWhileIdle() {
    var lifecycle = ResultStreamingLifecycle()
    expect(!lifecycle.needsPresentationTick, "a request waiting for its first token needs no timer")
    _ = lifecycle.appendContentToken("<think>分析</think>", extractsThinkTags: true, usesTypewriter: true)
    expect(!lifecycle.needsPresentationTick, "thinking-only tokens do not wake the typewriter")
    _ = lifecycle.appendContentToken("答案", extractsThinkTags: true, usesTypewriter: true)
    expect(lifecycle.needsPresentationTick, "visible output schedules presentation")
    expect(lifecycle.dequeue(maxCharacters: 4) == .chunk("答案"), "typewriter drains its visible queue")
    expect(!lifecycle.needsPresentationTick, "an empty queue sleeps while the provider is still streaming")
    _ = lifecycle.finish(usesTypewriter: true)
    expect(lifecycle.needsPresentationTick, "finish schedules one asynchronous completion even without pending text")
    expect(lifecycle.dequeue(maxCharacters: 4) == .finished, "finish is delivered after the last chunk")
    expect(!lifecycle.needsPresentationTick && lifecycle.dequeue(maxCharacters: 4) == .waiting,
           "completion is delivered once and does not leave the timer running")
    lifecycle.reset()
    expect(!lifecycle.needsPresentationTick, "fallback reset returns to the idle state")
}

func testMarkdownPresentationPreservesFenceBoundariesAndPlainText() {
    let markdown = "````markdown\r\n```swift\r\nlet value = 1\r\n```\r\n````\r\n\r\n~~~text\r\n尾部\r\n~~~"
    let result = MarkdownPresentationBuilder.build(markdown)
    expect(result.blocks == [.code("```swift\nlet value = 1\n```", language: "markdown"),
                             .code("尾部", language: "text")],
           "Markdown preserves nested fences, tilde fences and Windows line endings")
    let plain = "普通文本 👨‍👩‍👧‍👦 e\u{301}\n保留换行"
    expect(MarkdownPresentationBuilder.build(plain).blocks == [.paragraph(AttributedString(plain))],
           "plain-text fast path preserves whitespace and extended grapheme clusters")
    let formatted = MarkdownPresentationBuilder.build("**加粗** 与 &amp; 和 [链接](https://example.com)")
    if case .paragraph(let text)? = formatted.blocks.first {
        expect(String(text.characters) == "加粗 与 & 和 链接", "inline markup still uses the Markdown parser")
    } else {
        expect(false, "formatted Markdown produces a paragraph")
    }
}
