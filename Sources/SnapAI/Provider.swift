import Foundation

/// 供应商下的一个模型条目,可单独启用/关闭
struct AIModelEntry: Codable, Identifiable, Equatable {
    var name: String
    var enabled: Bool = true
    var id: String { name }
}

enum OutputTokenParameterMode: String, Codable, CaseIterable, Identifiable {
    case maxTokens = "max_tokens"
    case maxCompletionTokens = "max_completion_tokens"
    case omitted = "omitted"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .maxTokens:
            return "max_tokens"
        case .maxCompletionTokens:
            return "max_completion_tokens"
        case .omitted:
            return "不发送"
        }
    }

    var parameterKey: String? {
        switch self {
        case .maxTokens:
            return "max_tokens"
        case .maxCompletionTokens:
            return "max_completion_tokens"
        case .omitted:
            return nil
        }
    }
}

/// 一个 AI 供应商配置:协议 + 端点 + Key + 模型列表
struct AIProvider: Codable, Identifiable, Equatable {
    var id: String = UUID().uuidString
    var name: String = "新供应商"
    var apiProtocol: APIProtocol = .openAI
    var baseURL: String = ""
    /// API Key。注意:不写入 JSON(由 Keychain 持久化),仅运行时驻留。
    var apiKey: String = ""
    var models: [AIModelEntry] = []
    var isEnabled: Bool = true
    /// 每供应商可选覆盖参数。nil 表示沿用全局设置。
    var temperature: Double? = nil
    var maxTokens: Int? = nil
    var outputTokenParameterMode: OutputTokenParameterMode = .maxTokens
    var requestTimeout: Double? = nil   // #13 nil = 默认 60s

    /// 已启用的模型名(用于菜单栏快速切换)
    var enabledModelNames: [String] {
        models.filter { $0.enabled }.map { $0.name }
    }

    /// 是否指向本机模型服务。用于隐私模式下优先选择不离开本机的路由。
    var isLocalEndpoint: Bool {
        let normalizedBase = AIClient.normalizedBase(baseURL, proto: apiProtocol)
        guard let url = URL(string: normalizedBase),
              let host = url.host else {
            return false
        }
        let normalizedHost = host.trimmingCharacters(in: CharacterSet(charactersIn: "[]")).lowercased()
        return normalizedHost == "localhost" || normalizedHost == "127.0.0.1" || normalizedHost == "::1"
    }

    // apiKey 不参与编解码,改由 Keychain 管理
    enum CodingKeys: String, CodingKey {
        case id, name, apiProtocol, baseURL, models, isEnabled, temperature, maxTokens, outputTokenParameterMode, requestTimeout
    }

    init(id: String = UUID().uuidString,
         name: String = "新供应商",
         apiProtocol: APIProtocol = .openAI,
         baseURL: String = "",
         apiKey: String = "",
         models: [AIModelEntry] = [],
         isEnabled: Bool = true,
         temperature: Double? = nil,
         maxTokens: Int? = nil,
         outputTokenParameterMode: OutputTokenParameterMode = .maxTokens,
         requestTimeout: Double? = nil) {
        self.id = id
        self.name = name
        self.apiProtocol = apiProtocol
        self.baseURL = baseURL
        self.apiKey = apiKey
        self.models = models
        self.isEnabled = isEnabled
        self.temperature = temperature
        self.maxTokens = maxTokens
        self.outputTokenParameterMode = outputTokenParameterMode
        self.requestTimeout = requestTimeout
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decode(String.self, forKey: .id)) ?? UUID().uuidString
        name = (try? c.decode(String.self, forKey: .name)) ?? "新供应商"
        apiProtocol = (try? c.decode(APIProtocol.self, forKey: .apiProtocol)) ?? .openAI
        baseURL = (try? c.decode(String.self, forKey: .baseURL)) ?? ""
        apiKey = ""
        models = (try? c.decode([AIModelEntry].self, forKey: .models)) ?? []
        isEnabled = (try? c.decode(Bool.self, forKey: .isEnabled)) ?? true
        temperature = try? c.decode(Double.self, forKey: .temperature)
        maxTokens = try? c.decode(Int.self, forKey: .maxTokens)
        outputTokenParameterMode = (try? c.decode(OutputTokenParameterMode.self, forKey: .outputTokenParameterMode)) ?? .maxTokens
        requestTimeout = try? c.decode(Double.self, forKey: .requestTimeout)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(name, forKey: .name)
        try c.encode(apiProtocol, forKey: .apiProtocol)
        try c.encode(baseURL, forKey: .baseURL)
        try c.encode(models, forKey: .models)
        try c.encode(isEnabled, forKey: .isEnabled)
        try c.encodeIfPresent(temperature, forKey: .temperature)
        try c.encodeIfPresent(maxTokens, forKey: .maxTokens)
        try c.encode(outputTokenParameterMode, forKey: .outputTokenParameterMode)
        try c.encodeIfPresent(requestTimeout, forKey: .requestTimeout)
    }

    /// 合并新拉取的模型名:保留已存在条目的启用状态,新模型默认关闭(避免列表过长逐个关)
    mutating func mergeModels(_ names: [String]) {
        let existing = Dictionary(models.map { ($0.name, $0) }, uniquingKeysWith: { a, _ in a })
        var merged: [AIModelEntry] = []
        for name in names {
            if let old = existing[name] {
                merged.append(old)
            } else {
                merged.append(AIModelEntry(name: name, enabled: false))
            }
        }
        // 保留那些手动添加、但本次拉取未返回的模型
        for m in models where !names.contains(m.name) {
            merged.append(m)
        }
        models = merged
    }

    /// 内置预设(不预置模型,由用户「获取模型」后自行启用)
    static func preset(_ kind: Preset) -> AIProvider {
        switch kind {
        case .openAI:
            return AIProvider(name: "OpenAI", apiProtocol: .openAI,
                              baseURL: "https://api.openai.com/v1", apiKey: "", models: [])
        case .deepseek:
            return AIProvider(name: "DeepSeek", apiProtocol: .openAI,
                              baseURL: "https://api.deepseek.com/v1", apiKey: "", models: [])
        case .anthropic:
            return AIProvider(name: "Anthropic", apiProtocol: .anthropic,
                              baseURL: "https://api.anthropic.com/v1", apiKey: "", models: [])
        case .ollama:
            return AIProvider(name: "Ollama 本地", apiProtocol: .openAI,
                              baseURL: "http://localhost:11434/v1", apiKey: "ollama", models: [])
        case .lmStudio:
            return AIProvider(name: "LM Studio 本地", apiProtocol: .openAI,
                              baseURL: "http://localhost:1234/v1", apiKey: "lm-studio", models: [])
        case .blank:
            return AIProvider()
        }
    }

    enum Preset: String, CaseIterable, Identifiable {
        case openAI = "OpenAI"
        case deepseek = "DeepSeek"
        case anthropic = "Anthropic"
        case ollama = "Ollama 本地"
        case lmStudio = "LM Studio 本地"
        case blank = "空白"
        var id: String { rawValue }
    }
}
