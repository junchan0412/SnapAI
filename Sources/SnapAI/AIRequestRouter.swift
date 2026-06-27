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
        probe.contextProfiles = settings.contextProfiles
        probe.activeContextProfileID = settings.activeContextProfileID
        return probe
    }

    private static func routeReason(model: String, textLength: Int, hasImage: Bool, action: AIAction) -> String {
        let capability = ModelCapabilityRegistry.capability(for: model)
        if hasImage && capability.supportsVision { return "图片输入优先" }
        if textLength > 8_000 && capability.supportsLongContext { return "长文本优先" }
        if action.thinkingMode && capability.supportsReasoning { return "推理任务优先" }
        if isCodeAction(action) && capability.isCodeCapable { return "代码任务优先" }
        if action.isTranslation && capability.isFast { return "翻译/速度优先" }
        if capability.isFast || capability.isEconomical { return "速度/成本优先" }
        return "备用模型"
    }

    private static func score(route: AIRequestRoute,
                              settings: AppSettings,
                              action: AIAction,
                              textLength: Int,
                              hasImage: Bool) -> Int {
        let capability = ModelCapabilityRegistry.capability(for: route.modelName,
                                                            providerName: route.providerName)
        var value = 0
        if route.providerID == action.providerID { value += 500 }
        if route.providerID == settings.activeProviderID && route.modelName == settings.activeModel { value += 200 }
        if hasImage { value += capability.supportsVision ? 80 : -40 }
        if textLength > 8_000 { value += capability.supportsLongContext ? 60 : -20 }
        if action.thinkingMode { value += capability.supportsReasoning ? 60 : -10 }
        if isCodeAction(action) { value += capability.isCodeCapable ? 35 : -10 }
        if action.isTranslation { value += capability.isFast ? 20 : 0 }
        if !hasImage && textLength < 2_000 && (capability.isFast || capability.isEconomical) { value += 25 }
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
