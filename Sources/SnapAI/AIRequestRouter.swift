import Foundation

struct AIRequestRoute: Identifiable, Equatable {
    var providerID: String
    var providerName: String
    var modelName: String
    var reason: String

    var id: String { "\(providerID)::\(modelName)" }
}

enum AIRequestRouter {
    static func candidates(settings: AppSettings,
                           action: AIAction,
                           sourceText: String,
                           hasImage: Bool) -> [AIRequestRoute] {
        let enabledProviders = settings.providers.filter { $0.isEnabled }
        guard !enabledProviders.isEmpty else { return [] }

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
                                         reason: reason))
        }

        if let actionProviderID = action.providerID,
           let provider = enabledProviders.first(where: { $0.id == actionProviderID }) {
            let names = provider.enabledModelNames
            if let override = action.modelOverride,
               names.contains(override) {
                append(provider: provider, model: override, reason: "动作专属模型")
            } else if let first = names.first {
                append(provider: provider, model: first, reason: "动作专属供应商")
            }
        }

        if let active = settings.activeProvider {
            append(provider: active, model: settings.activeModel, reason: "当前模型")
        }

        let allRoutes = enabledProviders.flatMap { provider in
            provider.enabledModelNames.map { model in
                AIRequestRoute(providerID: provider.id,
                               providerName: provider.name,
                               modelName: model,
                               reason: routeReason(model: model,
                                                   textLength: sourceText.count,
                                                   hasImage: hasImage,
                                                   action: action))
            }
        }

        let sorted = allRoutes.sorted {
            score(route: $0, settings: settings, action: action, textLength: sourceText.count, hasImage: hasImage)
                > score(route: $1, settings: settings, action: action, textLength: sourceText.count, hasImage: hasImage)
        }

        if settings.autoRouteEnabled {
            for route in sorted {
                guard let provider = enabledProviders.first(where: { $0.id == route.providerID }) else { continue }
                append(provider: provider, model: route.modelName, reason: route.reason)
            }
        }

        if settings.fallbackEnabled {
            for route in allRoutes {
                guard let provider = enabledProviders.first(where: { $0.id == route.providerID }) else { continue }
                append(provider: provider, model: route.modelName, reason: route.reason)
            }
        }

        return routes
    }

    static func scopedSettings(from settings: AppSettings, route: AIRequestRoute) -> AppSettings? {
        guard let provider = settings.providers.first(where: { $0.id == route.providerID && $0.isEnabled }) else {
            return nil
        }
        let probe = AppSettings()
        probe.providers = [provider]
        probe.activeProviderID = provider.id
        probe.activeModel = route.modelName
        probe.temperature = settings.temperature
        probe.systemPrompt = settings.systemPrompt
        return probe
    }

    private static func routeReason(model: String, textLength: Int, hasImage: Bool, action: AIAction) -> String {
        let lower = model.lowercased()
        if hasImage && looksVisionCapable(lower) { return "图片输入优先" }
        if textLength > 8_000 && looksLongContextCapable(lower) { return "长文本优先" }
        if action.thinkingMode || looksReasoningCapable(lower) { return "推理任务优先" }
        if looksFastOrEconomical(lower) { return "速度/成本优先" }
        return "备用模型"
    }

    private static func score(route: AIRequestRoute,
                              settings: AppSettings,
                              action: AIAction,
                              textLength: Int,
                              hasImage: Bool) -> Int {
        let lower = route.modelName.lowercased()
        var value = 0
        if route.providerID == action.providerID { value += 500 }
        if route.providerID == settings.activeProviderID && route.modelName == settings.activeModel { value += 200 }
        if hasImage { value += looksVisionCapable(lower) ? 80 : -40 }
        if textLength > 8_000 { value += looksLongContextCapable(lower) ? 60 : -20 }
        if action.thinkingMode { value += looksReasoningCapable(lower) ? 60 : -10 }
        if !hasImage && textLength < 2_000 && looksFastOrEconomical(lower) { value += 25 }
        return value
    }

    private static func looksVisionCapable(_ model: String) -> Bool {
        model.contains("vision") ||
        model.contains("gpt-4o") ||
        model.contains("omni") ||
        model.contains("claude") ||
        model.contains("sonnet") ||
        model.contains("gemini")
    }

    private static func looksLongContextCapable(_ model: String) -> Bool {
        model.contains("long") ||
        model.contains("128k") ||
        model.contains("200k") ||
        model.contains("1m") ||
        model.contains("claude") ||
        model.contains("sonnet") ||
        model.contains("gemini") ||
        model.contains("gpt-4o")
    }

    private static func looksReasoningCapable(_ model: String) -> Bool {
        model.contains("reason") ||
        model.contains("r1") ||
        model.contains("o1") ||
        model.contains("o3") ||
        model.contains("thinking")
    }

    private static func looksFastOrEconomical(_ model: String) -> Bool {
        model.contains("mini") ||
        model.contains("flash") ||
        model.contains("haiku") ||
        model.contains("chat") ||
        model.contains("lite")
    }
}
