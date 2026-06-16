import Foundation

/// 供应商下的一个模型条目,可单独启用/关闭
struct AIModelEntry: Codable, Identifiable, Equatable {
    var name: String
    var enabled: Bool = true
    var id: String { name }
}

/// 一个 AI 供应商配置:协议 + 端点 + Key + 模型列表
struct AIProvider: Codable, Identifiable, Equatable {
    var id: String = UUID().uuidString
    var name: String = "新供应商"
    var apiProtocol: APIProtocol = .openAI
    var baseURL: String = ""
    var apiKey: String = ""
    var models: [AIModelEntry] = []
    var isEnabled: Bool = true

    /// 已启用的模型名(用于菜单栏快速切换)
    var enabledModelNames: [String] {
        models.filter { $0.enabled }.map { $0.name }
    }

    /// 合并新拉取的模型名:保留已存在条目的启用状态,新模型默认启用
    mutating func mergeModels(_ names: [String]) {
        let existing = Dictionary(models.map { ($0.name, $0) }, uniquingKeysWith: { a, _ in a })
        var merged: [AIModelEntry] = []
        for name in names {
            if let old = existing[name] {
                merged.append(old)
            } else {
                merged.append(AIModelEntry(name: name, enabled: true))
            }
        }
        // 保留那些手动添加、但本次拉取未返回的模型
        for m in models where !names.contains(m.name) {
            merged.append(m)
        }
        models = merged
    }

    /// 内置预设
    static func preset(_ kind: Preset) -> AIProvider {
        switch kind {
        case .openAI:
            return AIProvider(name: "OpenAI", apiProtocol: .openAI,
                              baseURL: "https://api.openai.com/v1", apiKey: "",
                              models: [AIModelEntry(name: "gpt-4o-mini")])
        case .deepseek:
            return AIProvider(name: "DeepSeek", apiProtocol: .openAI,
                              baseURL: "https://api.deepseek.com/v1", apiKey: "",
                              models: [AIModelEntry(name: "deepseek-chat")])
        case .anthropic:
            return AIProvider(name: "Anthropic", apiProtocol: .anthropic,
                              baseURL: "https://api.anthropic.com/v1", apiKey: "",
                              models: [AIModelEntry(name: "claude-sonnet-4-6")])
        case .ollama:
            return AIProvider(name: "Ollama 本地", apiProtocol: .openAI,
                              baseURL: "http://localhost:11434/v1", apiKey: "ollama",
                              models: [])
        case .blank:
            return AIProvider()
        }
    }

    enum Preset: String, CaseIterable, Identifiable {
        case openAI = "OpenAI"
        case deepseek = "DeepSeek"
        case anthropic = "Anthropic"
        case ollama = "Ollama 本地"
        case blank = "空白"
        var id: String { rawValue }
    }
}
