import Foundation

/// 一条对话消息
struct ChatMessage {
    enum Role: String { case system, user, assistant }
    var role: Role
    var content: String
}

/// 统一的 AI 流式客户端,支持 OpenAI 兼容协议与 Anthropic 原生协议。
/// 通过 URLSession 的 bytes(for:) 逐行解析 SSE。
final class AIClient {

    enum AIError: LocalizedError {
        case missingAPIKey
        case badResponse(Int, String)
        case invalidURL
        var errorDescription: String? {
            switch self {
            case .missingAPIKey: return "未配置 API Key,请在设置中填写。"
            case .badResponse(let code, let body): return "请求失败 (HTTP \(code)): \(body)"
            case .invalidURL: return "Base URL 无效。"
            }
        }
    }

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
        if !s.hasPrefix("http://") && !s.hasPrefix("https://") {
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
        guard let url = URL(string: base + path) else { throw AIError.invalidURL }
        return url
    }

    // MARK: - 模型列表

    /// 拉取可用模型列表(GET /models)。两种协议都兼容该端点。
    /// 返回模型 id 数组(已排序去重)。失败时抛错。
    func listModels() async throws -> [String] {
        guard !settings.apiKey.isEmpty else { throw AIError.missingAPIKey }
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
            throw AIError.badResponse(http.statusCode, String(body.prefix(500)))
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
    /// - onToken: 每收到一段增量文本回调(主线程)
    /// - onComplete: 结束回调,error 非空表示失败(主线程)
    func stream(messages: [ChatMessage],
                onToken: @escaping (String) -> Void,
                onComplete: @escaping (Error?) -> Void) {
        cancel()
        let proto = settings.apiProtocol
        task = Task {
            do {
                switch proto {
                case .openAI:
                    try await streamOpenAI(messages: messages, onToken: onToken)
                case .anthropic:
                    try await streamAnthropic(messages: messages, onToken: onToken)
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

    // MARK: - OpenAI 兼容

    private func streamOpenAI(messages: [ChatMessage], onToken: @escaping (String) -> Void) async throws {
        guard !settings.apiKey.isEmpty else { throw AIError.missingAPIKey }
        let url = try endpoint("/chat/completions")

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(settings.apiKey)", forHTTPHeaderField: "Authorization")

        let body: [String: Any] = [
            "model": settings.model,
            "temperature": settings.temperature,
            "stream": true,
            "messages": messages.map { ["role": $0.role.rawValue, "content": $0.content] }
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (bytes, response) = try await URLSession.shared.bytes(for: req)
        try await checkStatus(response, bytes: bytes)

        for try await line in bytes.lines {
            if Task.isCancelled { return }
            guard line.hasPrefix("data:") else { continue }
            let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
            if payload == "[DONE]" { break }
            guard let data = payload.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let choices = json["choices"] as? [[String: Any]],
                  let delta = choices.first?["delta"] as? [String: Any],
                  let content = delta["content"] as? String else { continue }
            await MainActor.run { onToken(content) }
        }
    }

    // MARK: - Anthropic 原生

    private func streamAnthropic(messages: [ChatMessage], onToken: @escaping (String) -> Void) async throws {
        guard !settings.apiKey.isEmpty else { throw AIError.missingAPIKey }
        let url = try endpoint("/messages")

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(settings.apiKey, forHTTPHeaderField: "x-api-key")
        req.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")

        // Anthropic 把 system 单列,user/assistant 放 messages
        let systemText = messages.filter { $0.role == .system }.map { $0.content }.joined(separator: "\n")
        let convo = messages.filter { $0.role != .system }
            .map { ["role": $0.role.rawValue, "content": $0.content] }

        var body: [String: Any] = [
            "model": settings.model,
            "max_tokens": 2048,
            "temperature": settings.temperature,
            "stream": true,
            "messages": convo
        ]
        if !systemText.isEmpty { body["system"] = systemText }
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (bytes, response) = try await URLSession.shared.bytes(for: req)
        try await checkStatus(response, bytes: bytes)

        for try await line in bytes.lines {
            if Task.isCancelled { return }
            guard line.hasPrefix("data:") else { continue }
            let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
            guard let data = payload.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }
            let type = json["type"] as? String
            if type == "content_block_delta",
               let delta = json["delta"] as? [String: Any],
               let text = delta["text"] as? String {
                await MainActor.run { onToken(text) }
            } else if type == "message_stop" {
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
        throw AIError.badResponse(http.statusCode, errBody)
    }
}
