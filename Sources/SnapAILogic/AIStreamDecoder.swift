import Foundation

package enum AIStreamDecodingError: LocalizedError, Equatable {
    case invalidEvent
    case eventTooLarge
    case interrupted
    case emptyResponse
    case outputLimitReached
    case contentFiltered
    case unsupportedToolCall

    package var errorDescription: String? {
        switch self {
        case .invalidEvent: return "服务返回了无法解析的流式数据，请重试。"
        case .eventTooLarge: return "服务返回的单个流式事件过大，已停止接收。"
        case .interrupted: return "连接在服务确认完成前中断，请重试。"
        case .emptyResponse: return "服务没有返回可显示的文本，请检查模型设置后重试。"
        case .outputLimitReached: return "输出已达到模型的 token 上限，当前为部分结果。可提高输出上限后重试。"
        case .contentFiltered: return "服务中止了这次输出，当前内容可能不完整。"
        case .unsupportedToolCall: return "模型请求了工具调用，但当前动作仅支持文本输出。请更换模型后重试。"
        }
    }
}

package struct ServerSentEvent: Equatable {
    package var name: String?
    package var data: String
}

/// AsyncBytes.lines 会跳过 SSE 的空行分隔符，因此在 UTF-8 字节层保留事件边界。
package struct ServerSentEventParser {
    package static let maximumEventBytes = 1_048_576

    private var line: [UInt8] = []
    private var dataLines: [String] = []
    private var eventName: String?
    private var eventByteCount = 0
    private var previousWasCarriageReturn = false
    private var isFirstLine = true

    package mutating func append(_ byte: UInt8) throws -> ServerSentEvent? {
        if previousWasCarriageReturn {
            previousWasCarriageReturn = false
            if byte == 0x0A { return nil }
        }
        if byte == 0x0D || byte == 0x0A {
            previousWasCarriageReturn = byte == 0x0D
            return try consumeLine()
        }
        guard line.count < Self.maximumEventBytes else {
            throw AIStreamDecodingError.eventTooLarge
        }
        line.append(byte)
        return nil
    }

    package mutating func finish() throws -> ServerSentEvent? {
        if !line.isEmpty, let event = try consumeLine() { return event }
        return dispatchEvent()
    }

    private mutating func consumeLine() throws -> ServerSentEvent? {
        defer { line.removeAll(keepingCapacity: true) }
        guard var value = String(bytes: line, encoding: .utf8) else {
            throw AIStreamDecodingError.invalidEvent
        }
        if isFirstLine {
            isFirstLine = false
            if value.hasPrefix("\u{FEFF}") { value.removeFirst() }
        }
        if value.isEmpty { return dispatchEvent() }
        if value.hasPrefix(":") { return nil }

        let separator = value.firstIndex(of: ":") ?? value.endIndex
        let field = value[..<separator]
        var content = separator == value.endIndex ? ""[...] : value[value.index(after: separator)...]
        if content.first == " " { content = content.dropFirst() }
        switch field {
        case "data":
            let addedBytes = content.utf8.count + 1
            guard addedBytes <= Self.maximumEventBytes - eventByteCount else {
                throw AIStreamDecodingError.eventTooLarge
            }
            eventByteCount += addedBytes
            dataLines.append(String(content))
        case "event":
            eventName = content.isEmpty ? nil : String(content)
        default:
            break
        }
        return nil
    }

    private mutating func dispatchEvent() -> ServerSentEvent? {
        defer {
            dataLines.removeAll(keepingCapacity: true)
            eventName = nil
            eventByteCount = 0
        }
        guard !dataLines.isEmpty else { return nil }
        return ServerSentEvent(name: eventName, data: dataLines.joined(separator: "\n"))
    }
}

package struct AIStreamDelta: Equatable {
    package var content = ""
    package var thinking = ""

    package var isEmpty: Bool { content.isEmpty && thinking.isEmpty }
}

package struct AIStreamDecoder {
    package let apiProtocol: APIProtocol
    package private(set) var isFinished = false
    private var hasContent = false
    private var stopReason: String?

    package init(apiProtocol: APIProtocol) {
        self.apiProtocol = apiProtocol
    }

    package mutating func decode(_ event: ServerSentEvent) throws -> AIStreamDelta {
        guard !isFinished else { return AIStreamDelta() }
        let payload = event.data.trimmingCharacters(in: .whitespacesAndNewlines)
        if payload.isEmpty { return AIStreamDelta() }
        if event.name == "ping" { return AIStreamDelta() }
        if event.name == "error" {
            throw AIClient.AIError.streamError(AIClient.sanitizedResponseBody(payload, fallback: "服务返回了流式错误"))
        }
        if apiProtocol == .openAI, payload == "[DONE]" {
            isFinished = true
            return AIStreamDelta()
        }
        guard let data = payload.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw AIStreamDecodingError.invalidEvent
        }

        let delta: AIStreamDelta
        switch apiProtocol {
        case .openAI:
            if let message = AIClient.openAIStreamErrorMessage(from: json) {
                throw AIClient.AIError.streamError(message)
            }
            delta = decodeOpenAI(json)
        case .anthropic:
            if let message = AIClient.anthropicStreamErrorMessage(from: json) {
                throw AIClient.AIError.streamError(message)
            }
            delta = decodeAnthropic(json, eventName: event.name)
        }
        if !hasContent, !delta.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            hasContent = true
        }
        return delta
    }

    package func validateCompletion() throws {
        guard isFinished else { throw AIStreamDecodingError.interrupted }
        switch stopReason {
        case "length", "max_tokens": throw AIStreamDecodingError.outputLimitReached
        case "content_filter", "refusal": throw AIStreamDecodingError.contentFiltered
        case "tool_calls", "function_call", "tool_use": throw AIStreamDecodingError.unsupportedToolCall
        default: break
        }
        guard hasContent else { throw AIStreamDecodingError.emptyResponse }
    }

    private mutating func decodeOpenAI(_ json: [String: Any]) -> AIStreamDelta {
        guard let choices = json["choices"] as? [[String: Any]],
              let choice = choices.first else { return AIStreamDelta() }
        if let reason = choice["finish_reason"] as? String, !reason.isEmpty {
            stopReason = reason
            // 部分兼容服务只发送 finish_reason，不另发 [DONE]。
            isFinished = true
        }
        guard let delta = choice["delta"] as? [String: Any] else { return AIStreamDelta() }
        return AIStreamDelta(content: delta["content"] as? String ?? "",
                             thinking: (delta["reasoning_content"] as? String)
                                ?? (delta["reasoning"] as? String) ?? "")
    }

    private mutating func decodeAnthropic(_ json: [String: Any], eventName: String?) -> AIStreamDelta {
        let type = json["type"] as? String ?? eventName
        switch type {
        case "content_block_start":
            guard let block = json["content_block"] as? [String: Any] else { return AIStreamDelta() }
            return AIStreamDelta(content: block["text"] as? String ?? "",
                                 thinking: block["thinking"] as? String ?? "")
        case "content_block_delta":
            guard let delta = json["delta"] as? [String: Any] else { return AIStreamDelta() }
            return AIStreamDelta(content: delta["text"] as? String ?? "",
                                 thinking: delta["thinking"] as? String ?? "")
        case "message_delta":
            if let reason = (json["delta"] as? [String: Any])?["stop_reason"] as? String {
                stopReason = reason
            }
        case "message_stop":
            isFinished = true
        default:
            break
        }
        return AIStreamDelta()
    }
}
