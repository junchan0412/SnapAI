import Foundation

enum LocalModelServiceKind: String, Equatable {
    case ollama = "Ollama"
    case lmStudio = "LM Studio"
    case localOpenAI = "本地 OpenAI 兼容服务"
}

struct LocalModelHealth: Equatable {
    var serviceKind: LocalModelServiceKind
    var baseURL: String

    var displayName: String {
        serviceKind.rawValue
    }

    var serviceStartHint: String {
        switch serviceKind {
        case .ollama:
            return "确认 Ollama 正在运行,必要时执行 ollama serve"
        case .lmStudio:
            return "确认 LM Studio 已启动 Local Server"
        case .localOpenAI:
            return "确认本地 OpenAI 兼容服务正在监听该端口"
        }
    }

    var modelSetupHint: String {
        switch serviceKind {
        case .ollama:
            return "在 Ollama 中拉取模型,例如 ollama pull llama3.1,然后在 SnapAI 启用该模型"
        case .lmStudio:
            return "在 LM Studio 中加载模型并启动 Local Server,然后在 SnapAI 启用该模型"
        case .localOpenAI:
            return "在本地服务中加载模型,然后在 SnapAI 添加并启用模型名"
        }
    }

    var apiKeyHint: String {
        switch serviceKind {
        case .ollama:
            return "Ollama 通常可填写 ollama 作为占位 API Key"
        case .lmStudio:
            return "LM Studio 通常可填写 lm-studio 作为占位 API Key"
        case .localOpenAI:
            return "若本地服务不校验密钥,可填写 local 作为占位 API Key"
        }
    }

    func recoverySuggestion(for readiness: AIRequestRouter.ProviderReadiness) -> String? {
        switch readiness {
        case .missingAPIKey:
            return "\(apiKeyHint); \(serviceStartHint)"
        case .noEnabledModels:
            return "\(modelSetupHint); \(serviceStartHint)"
        case .invalidBaseURL:
            return "检查本地 Base URL,当前为 \(baseURL); \(serviceStartHint)"
        case .ready, .disabled, .remoteHTTP:
            return nil
        }
    }

    static func make(provider: AIProvider) -> LocalModelHealth? {
        guard provider.isLocalEndpoint else { return nil }
        let base = AIClient.normalizedBase(provider.baseURL, proto: provider.apiProtocol)
        let lowered = "\(provider.name) \(base)".lowercased()
        let kind: LocalModelServiceKind
        if lowered.contains("ollama") || lowered.contains(":11434") {
            kind = .ollama
        } else if lowered.contains("lm studio") || lowered.contains("lmstudio") || lowered.contains(":1234") {
            kind = .lmStudio
        } else {
            kind = .localOpenAI
        }
        return LocalModelHealth(serviceKind: kind, baseURL: base)
    }
}
