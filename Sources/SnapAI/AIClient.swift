import Foundation

/// 一条对话消息
struct ChatMessage {
    enum Role: String { case system, user, assistant }
    var role: Role
    var content: String
    var imageData: Data? = nil        // #3 图片内容(base64 后发给 API)
    var imageMimeType: String = "image/png"
}

/// 把 ChatMessage 转成 OpenAI 格式的字典(自动处理图片)
private func openAIMessageDict(_ msg: ChatMessage) -> [String: Any] {
    if let img = msg.imageData {
        let b64 = img.base64EncodedString()
        let content: [[String: Any]] = [
            ["type": "text", "text": msg.content],
            ["type": "image_url", "image_url": ["url": "data:\(msg.imageMimeType);base64,\(b64)"]]
        ]
        return ["role": msg.role.rawValue, "content": content]
    }
    return ["role": msg.role.rawValue, "content": msg.content]
}

/// 把 ChatMessage 转成 Anthropic 格式的字典(自动处理图片)
private func anthropicMessageDict(_ msg: ChatMessage) -> [String: Any] {
    if let img = msg.imageData {
        let b64 = img.base64EncodedString()
        let content: [[String: Any]] = [
            ["type": "image", "source": ["type": "base64", "media_type": msg.imageMimeType, "data": b64]],
            ["type": "text", "text": msg.content]
        ]
        return ["role": msg.role.rawValue, "content": content]
    }
    return ["role": msg.role.rawValue, "content": msg.content]
}

/// 统一的 AI 流式客户端,支持 OpenAI 兼容协议与 Anthropic 原生协议。
/// 通过 URLSession 的 bytes(for:) 逐行解析 SSE。
final class AIClient {

    enum AIError: LocalizedError {
        case missingAPIKey
        case missingProvider
        case missingModel
        case badResponse(Int, String)
        case streamError(String)
        case insecureHTTPHost(String)
        case invalidURL
        case imageTooLarge(Int)
        case encodedImageTooLarge(encodedBytes: Int, limitBytes: Int)
        var errorDescription: String? {
            switch self {
            case .missingAPIKey: return "未配置 API Key,请在设置中填写。"
            case .missingProvider: return "没有可用的 AI 供应商,请在设置中启用至少一个供应商。"
            case .missingModel: return "未选择可用模型,请在设置中启用或添加模型。"
            case .badResponse(let code, let body): return "请求失败 (HTTP \(code)): \(body)"
            case .streamError(let body): return "流式响应错误: \(body)"
            case .insecureHTTPHost(let host): return "HTTP 明文端点仅允许用于本机地址。当前主机 \(host) 不安全,请改用 HTTPS。"
            case .invalidURL: return "Base URL 无效。"
            case .imageTooLarge(let bytes): return "图片过大(\(bytes / 1024 / 1024) MB),请压缩后重试。"
            case .encodedImageTooLarge(let encodedBytes, let limitBytes):
                return "图片编码后的请求体过大(\(encodedBytes / 1024 / 1024) MB),已超过 \(limitBytes / 1024 / 1024) MB 限制,请压缩或裁剪后重试。"
            }
        }
    }

    static let maxImageBytes = 5_000_000
    static let maxEncodedImagePayloadBytes = 6_700_000
    static let defaultMaxTokens = 2048
    static let defaultRequestTimeout: Double = 60
    static let thinkingOutputTokenMargin = 1_024
    private let settings: AppSettings
    private var task: Task<Void, Never>?

    init(settings: AppSettings) {
        self.settings = settings
    }

    /// 取消正在进行的流式请求
    func cancel() {
        task?.cancel()
        task = nil
    }

    /// 实际使用的 temperature
    private var effectiveTemperature: Double {
        Self.effectiveTemperature(settings: settings)
    }

    /// 实际使用的 max_tokens
    private var effectiveMaxTokens: Int {
        Self.effectiveMaxTokens(settings: settings)
    }

    /// 实际超时(秒),优先用供应商配置(#13)
    private var effectiveTimeout: Double {
        Self.effectiveTimeout(settings: settings)
    }

    static func effectiveTemperature(settings: AppSettings) -> Double {
        let raw = settings.activeProvider?.temperature ?? settings.temperature
        return AppSettings.clampedTemperature(raw)
    }

    static func effectiveMaxTokens(settings: AppSettings, minimum: Int? = nil) -> Int {
        let configured = AppSettings.sanitizedImportedMaxTokens(settings.activeProvider?.maxTokens) ?? defaultMaxTokens
        guard let minimum else { return configured }
        return min(max(configured, minimum), AppSettings.importedMaxTokensRange.upperBound)
    }

    static func effectiveTimeout(settings: AppSettings) -> Double {
        AppSettings.sanitizedImportedRequestTimeout(settings.activeProvider?.requestTimeout) ?? defaultRequestTimeout
    }

    static func openAIOutputTokenParameter(settings: AppSettings,
                                           value: Int? = nil) -> (key: String, value: Int)? {
        let mode = settings.activeProvider?.outputTokenParameterMode ?? .maxTokens
        guard let key = mode.parameterKey else { return nil }
        let tokenValue = value ?? effectiveMaxTokens(settings: settings)
        return (key, max(1, tokenValue))
    }

    static func effectiveThinkingBudget(action: AIAction) -> Int {
        AIAction.sanitizedThinkingBudget(action.thinkingBudget)
    }

    static func sanitizedResponseBody(_ body: String,
                                      limit: Int = 500,
                                      fallback: String = "响应体为空") -> String {
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return fallback }
        if let structured = structuredResponseErrorMessage(from: trimmed,
                                                           limit: limit,
                                                           fallback: fallback) {
            return structured
        }
        let sanitized = SensitiveTextSanitizer.sanitizedMessage(body, limit: limit)
        return sanitized.isEmpty ? fallback : sanitized
    }

    static func openAIStreamErrorMessage(from json: [String: Any]) -> String? {
        guard let error = json["error"], !(error is NSNull) else { return nil }
        return streamErrorMessage(from: error, envelope: json, fallback: "OpenAI 兼容服务返回了流式错误")
    }

    static func anthropicStreamErrorMessage(from json: [String: Any]) -> String? {
        if let error = json["error"], !(error is NSNull) {
            return streamErrorMessage(from: error, envelope: json, fallback: "Anthropic 返回了流式错误")
        }
        guard (json["type"] as? String) == "error" else { return nil }
        return streamErrorMessage(from: json, envelope: json, fallback: "Anthropic 返回了流式错误")
    }

    private static func structuredResponseErrorMessage(from body: String,
                                                       limit: Int,
                                                       fallback: String) -> String? {
        guard let data = body.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) else {
            return nil
        }

        if let dict = json as? [String: Any] {
            let payload = (dict["error"].map { $0 is NSNull ? dict : $0 }) ?? dict
            return streamErrorMessage(from: payload,
                                      envelope: dict,
                                      fallback: fallback,
                                      limit: limit)
        }

        if let array = json as? [Any],
           let serialized = compactJSONString(array) {
            return SensitiveTextSanitizer.sanitizedMessage(serialized, limit: limit)
        }

        return nil
    }

    private static func streamErrorMessage(from payload: Any,
                                           envelope: [String: Any],
                                           fallback: String,
                                           limit: Int = 300) -> String {
        var message = ""
        var metadata: [String] = []

        if let dict = payload as? [String: Any] {
            message = firstString(in: dict, keys: ["message", "error", "detail", "details"])
            metadata = ["type", "code", "param"]
                .compactMap { key in
                    guard let value = dict[key] as? String,
                          !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                        return nil
                    }
                    return value
                }
        } else if let string = payload as? String {
            message = string
        }

        if message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            message = firstString(in: envelope, keys: ["message", "error", "detail", "details"])
        }
        if message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           let serialized = compactJSONString(payload) {
            message = serialized
        }
        if message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            message = fallback
        }

        let prefix = metadata.isEmpty ? "" : metadata.joined(separator: ", ") + ": "
        return SensitiveTextSanitizer.sanitizedMessage(prefix + message, limit: limit)
    }

    private static func firstString(in dict: [String: Any], keys: [String]) -> String {
        for key in keys {
            if let value = dict[key] as? String,
               !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return value
            }
        }
        return ""
    }

    private static func compactJSONString(_ object: Any) -> String? {
        guard JSONSerialization.isValidJSONObject(object),
              let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]),
              let text = String(data: data, encoding: .utf8) else {
            return nil
        }
        return text
    }

    // MARK: - URL 规范化

    /// 把用户填写的端点地址规范化为 API 根地址(含版本段)。
    /// 用户可以只填:
    ///   - api.openai.com               -> https://api.openai.com/v1
    ///   - https://api.deepseek.com     -> https://api.deepseek.com/v1
    ///   - http://localhost:11434       -> http://localhost:11434/v1
    ///   - https://x.com/v1/            -> https://x.com/v1
    ///   - https://x.com/v1/chat/completions -> https://x.com/v1   (剥掉具体方法)
    /// 已包含版本段(/v1、/v3、/api/v1 等)的地址保持不变。
    static func normalizedBase(_ raw: String, proto: APIProtocol) -> String {
        var s = raw.trimmingCharacters(in: .whitespaces)
        guard !s.isEmpty else { return s }

        // 补协议头
        let lower = s.lowercased()
        if !lower.hasPrefix("http://") && !lower.hasPrefix("https://") {
            s = "https://" + s
        }
        // 去尾部斜杠
        s = s.replacingOccurrences(of: "/+$", with: "", options: .regularExpression)

        // 若用户把完整方法路径也填进来了,剥掉它
        for suffix in ["/chat/completions", "/completions", "/messages"] {
            if s.hasSuffix(suffix) {
                s = String(s.dropLast(suffix.count))
                s = s.replacingOccurrences(of: "/+$", with: "", options: .regularExpression)
            }
        }

        // 已经带版本段就不再追加(匹配 /v\d+ 结尾,如 /v1 /v3 /api/v1)
        let hasVersion = s.range(of: "/v[0-9]+$", options: .regularExpression) != nil
        if !hasVersion {
            // OpenAI 兼容与 Anthropic 都使用 /v1
            s += "/v1"
        }
        return s
    }

    /// 拼接具体方法路径
    private func endpoint(_ path: String) throws -> URL {
        let base = Self.normalizedBase(settings.baseURL, proto: settings.apiProtocol)
        guard let url = URL(string: base + path),
              let scheme = url.scheme?.lowercased(),
              let host = url.host, !host.isEmpty else {
            throw AIError.invalidURL
        }
        if scheme == "http" && !Self.isLocalHTTPHost(host) {
            throw AIError.insecureHTTPHost(host)
        }
        guard scheme == "http" || scheme == "https" else { throw AIError.invalidURL }
        return url
    }

    private static func isLocalHTTPHost(_ host: String) -> Bool {
        let h = host.trimmingCharacters(in: CharacterSet(charactersIn: "[]")).lowercased()
        return h == "localhost" || h == "127.0.0.1" || h == "::1"
    }

    private func validateReady(requireModel: Bool) throws {
        guard settings.activeProvider != nil else { throw AIError.missingProvider }
        guard !settings.apiKey.isEmpty else { throw AIError.missingAPIKey }
        if requireModel && settings.model.isEmpty {
            throw AIError.missingModel
        }
    }

    // MARK: - 连接测试

    /// 测试当前激活供应商的连通性:发一条极小的非流式请求,成功返回 true。
    /// 失败时抛出可读错误。
    func testConnection() async throws {
        try validateReady(requireModel: true)
        let proto = settings.apiProtocol
        let url: URL
        var req: URLRequest
        switch proto {
        case .openAI:
            url = try endpoint("/chat/completions")
            req = URLRequest(url: url)
            req.setValue("Bearer \(settings.apiKey)", forHTTPHeaderField: "Authorization")
            var body: [String: Any] = [
                "model": settings.model,
                "messages": [["role": "user", "content": "hi"]]
            ]
            if let outputTokens = Self.openAIOutputTokenParameter(settings: settings, value: 1) {
                body[outputTokens.key] = outputTokens.value
            }
            req.httpBody = try JSONSerialization.data(withJSONObject: body)
        case .anthropic:
            url = try endpoint("/messages")
            req = URLRequest(url: url)
            req.setValue(settings.apiKey, forHTTPHeaderField: "x-api-key")
            req.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
            let body: [String: Any] = [
                "model": settings.model,
                "max_tokens": 1,
                "messages": [["role": "user", "content": "hi"]]
            ]
            req.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.timeoutInterval = 20

        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse else {
            throw AIError.badResponse(0, "无响应")
        }
        if !(200...299).contains(http.statusCode) {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw AIError.badResponse(http.statusCode, Self.sanitizedResponseBody(body, limit: 300))
        }
    }

    // MARK: - 模型列表

    /// 拉取可用模型列表(GET /models)。两种协议都兼容该端点。
    /// 返回模型 id 数组(已排序去重)。失败时抛错。
    func listModels() async throws -> [String] {
        try validateReady(requireModel: false)
        let url = try endpoint("/models")

        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.timeoutInterval = 20
        switch settings.apiProtocol {
        case .openAI:
            req.setValue("Bearer \(settings.apiKey)", forHTTPHeaderField: "Authorization")
        case .anthropic:
            req.setValue(settings.apiKey, forHTTPHeaderField: "x-api-key")
            req.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        }

        let (data, response) = try await URLSession.shared.data(for: req)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw AIError.badResponse(http.statusCode, Self.sanitizedResponseBody(body, limit: 500))
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw AIError.badResponse(0, "返回格式无法解析")
        }
        // OpenAI: { "data": [ {"id": "..."} ] }   Anthropic: { "data": [ {"id": "..."} ] }
        let arr = (json["data"] as? [[String: Any]]) ?? (json["models"] as? [[String: Any]]) ?? []
        let ids = arr.compactMap { ($0["id"] as? String) ?? ($0["name"] as? String) }
        let unique = Array(Set(ids)).sorted()
        if unique.isEmpty { throw AIError.badResponse(0, "未返回任何模型") }
        return unique
    }

    /// 发起流式对话。
    /// - action: 当前动作(用于 thinking 模式、per-action provider)
    /// - onToken: 主文本增量回调(主线程)
    /// - onThinking: 推理/thinking 文本回调(主线程,Anthropic 专用)
    /// - onComplete: 结束回调(主线程)
    func stream(messages: [ChatMessage],
                action: AIAction? = nil,
                onToken: @escaping (String) -> Void,
                onThinking: ((String) -> Void)? = nil,
                onComplete: @escaping (Error?) -> Void) {
        cancel()
        let proto = settings.apiProtocol
        task = Task {
            do {
                try validateImagePayloads(messages)
                switch proto {
                case .openAI:
                    try await streamOpenAI(messages: messages, action: action, onToken: onToken)
                case .anthropic:
                    try await streamAnthropic(messages: messages, action: action,
                                              onToken: onToken, onThinking: onThinking)
                }
                if !Task.isCancelled {
                    await MainActor.run { onComplete(nil) }
                }
            } catch {
                if !Task.isCancelled {
                    await MainActor.run { onComplete(error) }
                }
            }
        }
    }

    private func validateImagePayloads(_ messages: [ChatMessage]) throws {
        for message in messages {
            guard let imageData = message.imageData else { continue }
            if imageData.count > Self.maxImageBytes {
                throw AIError.imageTooLarge(imageData.count)
            }
            let encodedBytes = Self.encodedImagePayloadByteCount(dataByteCount: imageData.count,
                                                                 mimeType: message.imageMimeType)
            if encodedBytes > Self.maxEncodedImagePayloadBytes {
                throw AIError.encodedImageTooLarge(encodedBytes: encodedBytes,
                                                   limitBytes: Self.maxEncodedImagePayloadBytes)
            }
        }
    }

    static func encodedImagePayloadByteCount(dataByteCount: Int, mimeType: String) -> Int {
        let base64ByteCount = ((max(0, dataByteCount) + 2) / 3) * 4
        return "data:\(mimeType);base64,".utf8.count + base64ByteCount
    }

    // MARK: - OpenAI 兼容

    private func streamOpenAI(messages: [ChatMessage], action: AIAction?,
                               onToken: @escaping (String) -> Void) async throws {
        try validateReady(requireModel: true)
        let url = try endpoint("/chat/completions")

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.timeoutInterval = effectiveTimeout
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(settings.apiKey)", forHTTPHeaderField: "Authorization")

        var body: [String: Any] = [
            "model": settings.model,
            "temperature": effectiveTemperature,
            "stream": true,
            "messages": messages.map { openAIMessageDict($0) }
        ]
        if let outputTokens = Self.openAIOutputTokenParameter(settings: settings) {
            body[outputTokens.key] = outputTokens.value
        }
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (bytes, response) = try await URLSession.shared.bytes(for: req)
        try await checkStatus(response, bytes: bytes)

        for try await line in bytes.lines {
            if Task.isCancelled { return }
            guard line.hasPrefix("data:") else { continue }
            let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
            if payload == "[DONE]" { break }
            guard let data = payload.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }
            if let errorMessage = Self.openAIStreamErrorMessage(from: json) {
                throw AIError.streamError(errorMessage)
            }
            guard let choices = json["choices"] as? [[String: Any]],
                  let delta = choices.first?["delta"] as? [String: Any],
                  let content = delta["content"] as? String else { continue }
            await MainActor.run { onToken(content) }
        }
    }

    // MARK: - Anthropic 原生

    private func streamAnthropic(messages: [ChatMessage], action: AIAction?,
                                  onToken: @escaping (String) -> Void,
                                  onThinking: ((String) -> Void)?) async throws {
        try validateReady(requireModel: true)
        let url = try endpoint("/messages")

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.timeoutInterval = effectiveTimeout
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(settings.apiKey, forHTTPHeaderField: "x-api-key")
        req.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        if action?.thinkingMode == true {
            req.setValue("interleaved-thinking-2025-05-14", forHTTPHeaderField: "anthropic-beta")
        }

        let systemText = messages.filter { $0.role == .system }.map { $0.content }.joined(separator: "\n")
        let convo = messages.filter { $0.role != .system }.map { anthropicMessageDict($0) }

        let thinkingBudget: Int?
        if let action, action.thinkingMode {
            thinkingBudget = Self.effectiveThinkingBudget(action: action)
        } else {
            thinkingBudget = nil
        }
        let maxTokens = thinkingBudget.map {
            Self.effectiveMaxTokens(settings: settings, minimum: $0 + Self.thinkingOutputTokenMargin)
        } ?? effectiveMaxTokens

        var body: [String: Any] = [
            "model": settings.model,
            "max_tokens": maxTokens,
            "temperature": effectiveTemperature,
            "stream": true,
            "messages": convo
        ]
        if !systemText.isEmpty { body["system"] = systemText }
        // #2 Anthropic extended thinking
        if let thinkingBudget {
            body["thinking"] = ["type": "enabled", "budget_tokens": thinkingBudget]
            body.removeValue(forKey: "temperature")   // thinking 模式不支持 temperature
        }
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (bytes, response) = try await URLSession.shared.bytes(for: req)
        try await checkStatus(response, bytes: bytes)

        for try await line in bytes.lines {
            if Task.isCancelled { return }
            guard line.hasPrefix("data:") else { continue }
            let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
            guard let data = payload.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }
            if let errorMessage = Self.anthropicStreamErrorMessage(from: json) {
                throw AIError.streamError(errorMessage)
            }
            let evtType = json["type"] as? String
            if evtType == "content_block_delta",
               let delta = json["delta"] as? [String: Any] {
                let deltaType = delta["type"] as? String
                if deltaType == "thinking_delta", let t = delta["thinking"] as? String {
                    await MainActor.run { onThinking?(t) }
                } else if let text = delta["text"] as? String {
                    await MainActor.run { onToken(text) }
                }
            } else if evtType == "message_stop" {
                break
            }
        }
    }

    // MARK: - 工具

    /// 检查 HTTP 状态码,非 2xx 时读取错误体抛出
    private func checkStatus(_ response: URLResponse, bytes: URLSession.AsyncBytes) async throws {
        guard let http = response as? HTTPURLResponse else { return }
        guard !(200...299).contains(http.statusCode) else { return }
        var errBody = ""
        for try await line in bytes.lines {
            errBody += line
            if errBody.count > 800 { break }
        }
        throw AIError.badResponse(http.statusCode, Self.sanitizedResponseBody(errBody, limit: 800))
    }
}
