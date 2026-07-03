import Foundation

struct AIRequestRoute: Identifiable, Equatable {
    var providerID: String
    var providerName: String
    var modelName: String
    var reason: String
    var isLocalEndpoint: Bool = false

    var id: String { "\(providerID)::\(modelName)" }

    var diagnosticProviderName: String {
        AIRequestDiagnosticText.metadata(providerName,
                                         fallback: "未知供应商",
                                         maxLength: 80)
    }

    var diagnosticModelName: String {
        AIRequestDiagnosticText.metadata(modelName,
                                         fallback: "未知模型",
                                         maxLength: 120)
    }

    var diagnosticReason: String {
        AIRequestDiagnosticText.metadata(reason,
                                         fallback: "未说明",
                                         maxLength: 80)
    }

    var displayRouteNote: String {
        diagnosticReason
    }

    var fallbackSwitchNote: String {
        "\(diagnosticProviderName) / \(diagnosticModelName) 失败,正在切换备用模型"
    }
}

enum AIRequestRouter {
    static func candidates(settings: AppSettings,
                           action: AIAction,
                           sourceText: String,
                           hasImage: Bool,
                           routingTextCharacterCount: Int? = nil,
                           routingMetrics: RoutingMetricsTable = .empty) -> [AIRequestRoute] {
        let enabledProviders = settings.providers.filter { $0.isEnabled }
        guard !enabledProviders.isEmpty else { return [] }
        let requestReadyProviders = enabledProviders.filter { isProviderRequestReady($0) }
        let textLength = routingTextLength(sourceText: sourceText,
                                           routingTextCharacterCount: routingTextCharacterCount)

        var routes: [AIRequestRoute] = []
        var seen = Set<String>()

        func append(provider: AIProvider, model: String, reason: String) {
            guard !model.isEmpty else { return }
            let key = "\(provider.id)::\(model)"
            guard !seen.contains(key) else { return }
            seen.insert(key)
            routes.append(AIRequestRoute(providerID: provider.id,
                                         providerName: provider.name,
                                         modelName: model,
                                         reason: reason,
                                         isLocalEndpoint: provider.isLocalEndpoint))
        }

        let allRoutes = requestReadyProviders.flatMap { provider in
            provider.enabledModelNames.map { model in
                AIRequestRoute(providerID: provider.id,
                               providerName: provider.name,
                               modelName: model,
                               reason: routeReason(model: model,
                                                   provider: provider,
                                                   textLength: textLength,
                                                   hasImage: hasImage,
                                                   action: action,
                                                   prefersLocalRoutes: settings.prefersLocalModelRoutes,
                                                   preference: settings.routingPreference,
                                                   routingMetrics: routingMetrics),
                               isLocalEndpoint: provider.isLocalEndpoint)
            }
        }
        let hasFittingReadyRoute = allRoutes.contains {
            contextFitStatus(modelName: $0.modelName,
                             providerName: $0.providerName,
                             textLength: textLength) != "over-limit"
        }
        let hasVisionReadyRoute = !hasImage || allRoutes.contains {
            modelSupportsImageInput(modelName: $0.modelName,
                                    providerName: $0.providerName)
        }
        let hasReasoningReadyRoute = !action.thinkingMode || allRoutes.contains {
            modelSupportsReasoning(modelName: $0.modelName,
                                   providerName: $0.providerName)
        }
        let hasLocalReadyRoute = allRoutes.contains { $0.isLocalEndpoint }

        func shouldPinExplicit(provider: AIProvider, model: String) -> Bool {
            guard settings.autoRouteEnabled else {
                return true
            }
            if settings.prefersLocalModelRoutes,
               hasLocalReadyRoute,
               !provider.isLocalEndpoint {
                return false
            }
            if action.thinkingMode,
               hasReasoningReadyRoute,
               !modelSupportsReasoning(modelName: model,
                                       providerName: provider.name) {
                return false
            }
            if hasImage,
               hasVisionReadyRoute,
               !modelSupportsImageInput(modelName: model,
                                        providerName: provider.name) {
                return false
            }
            if hasFittingReadyRoute,
               contextFitStatus(modelName: model,
                                providerName: provider.name,
                                textLength: textLength) == "over-limit" {
                return false
            }
            return true
        }

        if let actionProviderID = action.providerID,
           let provider = enabledProviders.first(where: { $0.id == actionProviderID }) {
            let names = provider.enabledModelNames
            if let override = action.modelOverride,
               names.contains(override) {
                if shouldPinExplicit(provider: provider, model: override) {
                    append(provider: provider, model: override, reason: "动作专属模型")
                }
            } else if let first = names.first,
                      shouldPinExplicit(provider: provider, model: first) {
                append(provider: provider, model: first, reason: "动作专属供应商")
            }
        }

        if let active = settings.activeProvider {
            let currentModel = settings.model
            if shouldPinExplicit(provider: active, model: currentModel) {
                let reason = currentModel == settings.activeModel ? "当前模型" : "当前可用模型"
                append(provider: active, model: currentModel, reason: reason)
            }
        }

        let providerOrder = Dictionary(uniqueKeysWithValues: requestReadyProviders.enumerated().map { ($0.element.id, $0.offset) })
        let modelOrder = Dictionary(uniqueKeysWithValues: requestReadyProviders.flatMap { provider in
            provider.enabledModelNames.enumerated().map { ("\(provider.id)::\($0.element)", $0.offset) }
        })
        let sorted = allRoutes.sorted {
            routePrecedes($0,
                          $1,
                          settings: settings,
                          action: action,
                          textLength: textLength,
                          hasImage: hasImage,
                          providerOrder: providerOrder,
                          modelOrder: modelOrder,
                          routingMetrics: routingMetrics)
        }

        if settings.autoRouteEnabled {
            for route in sorted {
                guard let provider = enabledProviders.first(where: { $0.id == route.providerID }) else { continue }
                append(provider: provider, model: route.modelName, reason: route.reason)
            }
        }

        if settings.fallbackEnabled {
            for route in sorted {
                guard let provider = enabledProviders.first(where: { $0.id == route.providerID }) else { continue }
                append(provider: provider, model: route.modelName, reason: route.reason)
            }
        }

        return routes
    }

    static func routingTextLength(sourceText: String,
                                  routingTextCharacterCount: Int?) -> Int {
        max(0, routingTextCharacterCount ?? sourceText.count)
    }

    static func contextFitStatus(modelName: String,
                                 providerName: String,
                                 textLength: Int) -> String {
        let capability = ModelCapabilityRegistry.capability(for: modelName,
                                                            providerName: providerName)
        let estimatedTokens = AIRequestPayloadDiagnostic.estimatedTextTokens(forCharacterCount: textLength)
        return AIRequestPayloadDiagnostic.contextFitStatus(estimatedTextTokens: estimatedTokens,
                                                           contextTokens: capability.contextTokens)
    }

    static func modelSupportsImageInput(modelName: String,
                                        providerName: String) -> Bool {
        ModelCapabilityRegistry.capability(for: modelName,
                                           providerName: providerName).supportsVision
    }

    static func modelSupportsReasoning(modelName: String,
                                       providerName: String) -> Bool {
        ModelCapabilityRegistry.capability(for: modelName,
                                           providerName: providerName).supportsReasoning
    }

    enum ProviderReadiness: Equatable, Hashable {
        case ready
        case disabled
        case missingAPIKey
        case noEnabledModels
        case invalidBaseURL
        case remoteHTTP

        var isReady: Bool { self == .ready }

        var diagnosticCode: String {
            switch self {
            case .ready: return "ready"
            case .disabled: return "disabled"
            case .missingAPIKey: return "missing-api-key"
            case .noEnabledModels: return "no-enabled-models"
            case .invalidBaseURL: return "invalid-base-url"
            case .remoteHTTP: return "remote-http"
            }
        }

        var displayText: String {
            switch self {
            case .ready: return "可请求"
            case .disabled: return "供应商未启用"
            case .missingAPIKey: return "缺少 API Key"
            case .noEnabledModels: return "没有启用模型"
            case .invalidBaseURL: return "Base URL 无效"
            case .remoteHTTP: return "远程 HTTP 不安全"
            }
        }

        var recoverySuggestion: String {
            switch self {
            case .ready:
                return "无需处理"
            case .disabled:
                return "在 AI 设置中启用该供应商"
            case .missingAPIKey:
                return "在 AI 设置中重新填写 API Key"
            case .noEnabledModels:
                return "在 AI 设置中启用至少一个模型"
            case .invalidBaseURL:
                return "检查 Base URL,例如 https://api.example.com/v1"
            case .remoteHTTP:
                return "远程端点请改用 HTTPS;HTTP 仅允许 localhost"
            }
        }
    }

    static func providerReadiness(_ provider: AIProvider) -> ProviderReadiness {
        guard provider.isEnabled else { return .disabled }
        guard !provider.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return .missingAPIKey
        }
        guard !provider.enabledModelNames.isEmpty else { return .noEnabledModels }

        let normalizedBase = AIClient.normalizedBase(provider.baseURL, proto: provider.apiProtocol)
        guard let url = URL(string: normalizedBase),
              let scheme = url.scheme?.lowercased(),
              let host = url.host,
              !host.isEmpty else {
            return .invalidBaseURL
        }
        if scheme == "http" {
            return isLocalHTTPHost(host) ? .ready : .remoteHTTP
        }
        return scheme == "https" ? .ready : .invalidBaseURL
    }

    static func providerRecoverySuggestion(_ provider: AIProvider) -> String {
        let readiness = providerReadiness(provider)
        if let local = LocalModelHealth.make(provider: provider),
           let suggestion = local.recoverySuggestion(for: readiness) {
            return suggestion
        }
        return readiness.recoverySuggestion
    }

    static func providerRecoverySuggestion(providers: [AIProvider],
                                           readiness: ProviderReadiness) -> String {
        let matchingProviders = providers.filter { providerReadiness($0) == readiness }
        if let localSuggestion = matchingProviders.compactMap({ provider -> String? in
            guard LocalModelHealth.make(provider: provider) != nil else { return nil }
            return providerRecoverySuggestion(provider)
        }).first {
            return localSuggestion
        }
        return readiness.recoverySuggestion
    }

    static func isProviderRequestReady(_ provider: AIProvider) -> Bool {
        providerReadiness(provider).isReady
    }

    static func scopedSettings(from settings: AppSettings, route: AIRequestRoute) -> AppSettings? {
        guard let provider = settings.providers.first(where: { $0.id == route.providerID && $0.isEnabled }) else {
            return nil
        }
        guard provider.enabledModelNames.contains(route.modelName) else {
            return nil
        }
        let probe = AppSettings()
        probe.providers = [provider]
        probe.activeProviderID = provider.id
        probe.activeModel = route.modelName
        probe.temperature = settings.temperature
        probe.systemPrompt = settings.systemPrompt
        probe.contextProfiles = settings.contextProfiles
        probe.activeContextProfileID = settings.activeContextProfileID
        return probe
    }

    private static func isLocalHTTPHost(_ host: String) -> Bool {
        let normalized = host.trimmingCharacters(in: CharacterSet(charactersIn: "[]")).lowercased()
        return normalized == "localhost" || normalized == "127.0.0.1" || normalized == "::1"
    }

    private static func routeReason(model: String,
                                    provider: AIProvider,
                                    textLength: Int,
                                    hasImage: Bool,
                                    action: AIAction,
                                    prefersLocalRoutes: Bool,
                                    preference: AIRoutingPreference,
                                    routingMetrics: RoutingMetricsTable = .empty) -> String {
        let capability = ModelCapabilityRegistry.capability(for: model, providerName: provider.name)
        if let reason = routingMetrics.preferredReason(providerID: provider.id, modelName: model) {
            return reason
        }
        if prefersLocalRoutes {
            return provider.isLocalEndpoint ? "本地隐私优先" : "云端备用模型"
        }
        if hasImage && capability.supportsVision { return "图片输入优先" }
        if textLength > 8_000 && capability.supportsLongContext { return "长文本优先" }
        if action.thinkingMode && capability.supportsReasoning { return "推理任务优先" }
        if isCodeAction(action) && capability.isCodeCapable { return "代码任务优先" }
        if action.isTranslation && capability.isFast { return "翻译/速度优先" }
        if preference == .fastest && (capability.isFast || capability.isEconomical) { return "速度偏好优先" }
        if preference == .quality && qualityScore(for: capability) >= 2 { return "质量偏好优先" }
        if capability.isFast || capability.isEconomical { return "速度/成本优先" }
        return "备用模型"
    }

    private static func score(route: AIRequestRoute,
                              settings: AppSettings,
                              action: AIAction,
                              textLength: Int,
                              hasImage: Bool,
                              routingMetrics: RoutingMetricsTable = .empty) -> Int {
        let capability = ModelCapabilityRegistry.capability(for: route.modelName,
                                                            providerName: route.providerName)
        var value = 0
        if route.providerID == action.providerID { value += 500 }
        if route.providerID == settings.activeProviderID && route.modelName == settings.activeModel { value += 200 }
        if settings.prefersLocalModelRoutes {
            value += route.isLocalEndpoint ? 180 : -40
        }
        if hasImage { value += capability.supportsVision ? 120 : -300 }
        if textLength > 8_000 { value += capability.supportsLongContext ? 60 : -20 }
        let fitStatus = AIRequestPayloadDiagnostic.contextFitStatus(
            estimatedTextTokens: AIRequestPayloadDiagnostic.estimatedTextTokens(forCharacterCount: textLength),
            contextTokens: capability.contextTokens
        )
        if fitStatus == "over-limit" {
            value -= 1_000
        } else if fitStatus == "near-limit" {
            value -= 80
        }
        if action.thinkingMode { value += capability.supportsReasoning ? 120 : -240 }
        if isCodeAction(action) { value += capability.isCodeCapable ? 35 : -10 }
        if action.isTranslation { value += capability.isFast ? 20 : 0 }
        if !hasImage && textLength < 2_000 && (capability.isFast || capability.isEconomical) { value += 25 }
        switch settings.routingPreference {
        case .fastest:
            if capability.isFast { value += 70 }
            if capability.isEconomical { value += 35 }
            if !capability.isFast && !capability.isEconomical { value -= 20 }
        case .balanced:
            break
        case .quality:
            value += qualityScore(for: capability) * 30
            if capability.isFast && capability.isEconomical { value -= 15 }
        }
        value += routingMetrics.scoreAdjustment(for: route)
        return value
    }

    private static func routePrecedes(_ lhs: AIRequestRoute,
                                      _ rhs: AIRequestRoute,
                                      settings: AppSettings,
                                      action: AIAction,
                                      textLength: Int,
                                      hasImage: Bool,
                                      providerOrder: [String: Int],
                                      modelOrder: [String: Int],
                                      routingMetrics: RoutingMetricsTable = .empty) -> Bool {
        let lhsScore = score(route: lhs,
                             settings: settings,
                             action: action,
                             textLength: textLength,
                             hasImage: hasImage,
                             routingMetrics: routingMetrics)
        let rhsScore = score(route: rhs,
                             settings: settings,
                             action: action,
                             textLength: textLength,
                             hasImage: hasImage,
                             routingMetrics: routingMetrics)
        if lhsScore != rhsScore { return lhsScore > rhsScore }

        let lhsProviderOrder = providerOrder[lhs.providerID] ?? Int.max
        let rhsProviderOrder = providerOrder[rhs.providerID] ?? Int.max
        if lhsProviderOrder != rhsProviderOrder {
            return lhsProviderOrder < rhsProviderOrder
        }

        let lhsModelOrder = modelOrder[lhs.id] ?? Int.max
        let rhsModelOrder = modelOrder[rhs.id] ?? Int.max
        if lhsModelOrder != rhsModelOrder {
            return lhsModelOrder < rhsModelOrder
        }

        return lhs.id < rhs.id
    }

    private static func qualityScore(for capability: ModelCapability) -> Int {
        var value = 0
        if capability.supportsLongContext { value += 1 }
        if capability.supportsReasoning { value += 1 }
        if capability.isCodeCapable { value += 1 }
        if capability.contextTokens >= 200_000 { value += 1 }
        return value
    }

    private static func isCodeAction(_ action: AIAction) -> Bool {
        let text = "\(action.name) \(action.prompt)".lowercased()
        return text.contains("代码") ||
        text.contains("code") ||
        text.contains("program") ||
        text.contains("函数") ||
        text.contains("bug")
    }
}
