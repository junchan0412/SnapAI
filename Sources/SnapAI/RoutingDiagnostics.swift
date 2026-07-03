import Foundation

enum AIRequestAttemptStatus: String, Equatable, Hashable {
    case running = "running"
    case succeeded = "succeeded"
    case failed = "failed"
    case skipped = "skipped"

    var displayName: String {
        switch self {
        case .running: return "进行中"
        case .succeeded: return "成功"
        case .failed: return "失败"
        case .skipped: return "跳过"
        }
    }
}

struct AIRequestAttemptDiagnostic: Equatable {
    var route: AIRequestRoute
    var status: AIRequestAttemptStatus
    var message: String?
    var elapsedMilliseconds: Int? = nil
    var outputCharacterCount: Int? = nil
    var fallbackDecision: AIRequestFallbackDecision? = nil

    var summaryLine: String {
        summaryLine(includeMessage: true)
    }

    func summaryLine(includeMessage: Bool) -> String {
        let duration = elapsedMilliseconds.map { " · 耗时 \(Self.formattedDuration(milliseconds: $0))" } ?? ""
        let output = outputCharacterCount.map { " · 输出 \(max(0, $0)) 字" } ?? ""
        let fallback = fallbackDecision.map { " · Fallback \($0.diagnosticCode)" } ?? ""
        let base = "\(route.diagnosticProviderName) / \(route.diagnosticModelName) (\(route.diagnosticReason)) -> \(status.displayName)\(duration)\(output)\(fallback)"
        guard includeMessage, let message, !message.isEmpty else { return base }
        return "\(base): \(Self.sanitizedMessage(message))"
    }

    static func sanitizedMessage(_ message: String, limit: Int = 180) -> String {
        SensitiveTextSanitizer.sanitizedMessage(message, limit: limit)
    }

    static func elapsedMilliseconds(since start: Date,
                                    now: Date = Date()) -> Int {
        max(0, Int((now.timeIntervalSince(start) * 1_000).rounded()))
    }

    static func formattedDuration(milliseconds: Int) -> String {
        let safe = max(0, milliseconds)
        if safe < 1_000 {
            return "\(safe)ms"
        }
        let seconds = Double(safe) / 1_000
        if seconds < 10 {
            return String(format: "%.1fs", seconds)
        }
        return "\(Int(seconds.rounded()))s"
    }
}

struct AIRequestFallbackDecision: Equatable {
    enum Reason: String, Equatable {
        case willTryNext = "will-try-next"
        case fallbackDisabled = "disabled"
        case noNextRoute = "no-next-route"
        case partialOutput = "partial-output"
        case cloudFallbackRequiresConfirmation = "cloud-confirmation-required"
    }

    var reason: Reason

    var shouldTryNext: Bool {
        reason == .willTryNext
    }

    var diagnosticCode: String {
        reason.rawValue
    }

    var userNote: String? {
        switch reason {
        case .willTryNext:
            return "正在切换备用模型"
        case .cloudFallbackRequiresConfirmation:
            return "本地模型失败;改用云端备用模型前需要确认"
        case .partialOutput:
            return "已收到部分输出，未自动切换"
        case .fallbackDisabled, .noNextRoute:
            return nil
        }
    }

    static func decide(fallbackEnabled: Bool,
                       hasNextRoute: Bool,
                       outputCharacterCount: Int,
                       requiresCloudFallbackConfirmation: Bool = false) -> AIRequestFallbackDecision {
        guard fallbackEnabled else {
            return AIRequestFallbackDecision(reason: .fallbackDisabled)
        }
        guard hasNextRoute else {
            return AIRequestFallbackDecision(reason: .noNextRoute)
        }
        guard outputCharacterCount <= 0 else {
            return AIRequestFallbackDecision(reason: .partialOutput)
        }
        if requiresCloudFallbackConfirmation {
            return AIRequestFallbackDecision(reason: .cloudFallbackRequiresConfirmation)
        }
        return AIRequestFallbackDecision(reason: .willTryNext)
    }
}

struct AIRequestRecoveryHint: Equatable {
    var code: String
    var suggestion: String
}

struct AIRequestContextDiagnostic: Equatable {
    var contextProfileCount: Int = 0
    var usableContextProfileCount: Int = 0
    var activeContextCharacterCount: Int = 0
    var globalSystemPromptCharacterCount: Int = 0
    var effectiveSystemPromptCharacterCount: Int = 0

    var summaryLines: [String] {
        [
            "Context Profiles: \(contextProfileCount) (usable \(usableContextProfileCount))",
            "Active Context: \(activeContextCharacterCount > 0 ? "set" : "none")",
            "Active Context Characters: \(activeContextCharacterCount)",
            "Global System Prompt Characters: \(globalSystemPromptCharacterCount)",
            "Effective System Prompt Characters: \(effectiveSystemPromptCharacterCount)"
        ]
    }

    static func make(settings: AppSettings) -> AIRequestContextDiagnostic {
        let summary = settings.contextStatusSummary
        return AIRequestContextDiagnostic(
            contextProfileCount: summary.profileCount,
            usableContextProfileCount: summary.usableProfileCount,
            activeContextCharacterCount: summary.activeContextCharacterCount,
            globalSystemPromptCharacterCount: summary.globalSystemPromptCharacterCount,
            effectiveSystemPromptCharacterCount: summary.effectiveSystemPromptCharacterCount
        )
    }
}

struct AIRequestPayloadDiagnostic: Equatable {
    var messageCount: Int = 0
    var textCharacterCount: Int = 0
    var estimatedTextTokens: Int = 0
    var imageAttachmentCount: Int = 0

    var summaryLines: [String] {
        [
            "Request Messages: \(messageCount)",
            "Request Text Characters: \(textCharacterCount)",
            "Estimated Text Tokens: \(estimatedTextTokens)",
            "Image Attachments: \(imageAttachmentCount)"
        ]
    }

    static func make(messages: [ChatMessage],
                     explicitHasImage: Bool = false) -> AIRequestPayloadDiagnostic {
        let textCharacters = messages.reduce(0) { $0 + $1.content.count }
        let embeddedImageCount = messages.reduce(0) { $0 + ($1.imageData == nil ? 0 : 1) }
        let imageCount = max(embeddedImageCount, explicitHasImage ? 1 : 0)
        return AIRequestPayloadDiagnostic(
            messageCount: messages.count,
            textCharacterCount: textCharacters,
            estimatedTextTokens: estimatedTextTokens(forCharacterCount: textCharacters),
            imageAttachmentCount: imageCount
        )
    }

    static func estimatedTextTokens(forCharacterCount characterCount: Int) -> Int {
        let safeCount = max(0, characterCount)
        guard safeCount > 0 else { return 0 }
        return max(1, Int((Double(safeCount) / 4.0).rounded(.up)))
    }

    func contextFitSummary(for route: AIRequestRoute) -> String {
        Self.contextFitSummary(estimatedTextTokens: estimatedTextTokens,
                               modelName: route.modelName,
                               providerName: route.providerName)
    }

    func imageFitSummary(for route: AIRequestRoute,
                         hasImage: Bool) -> String {
        Self.imageFitSummary(hasImage: hasImage,
                             modelName: route.modelName,
                             providerName: route.providerName)
    }

    func reasoningFitSummary(for route: AIRequestRoute,
                             requiresReasoning: Bool) -> String {
        Self.reasoningFitSummary(requiresReasoning: requiresReasoning,
                                 modelName: route.modelName,
                                 providerName: route.providerName)
    }

    static func contextFitSummary(estimatedTextTokens: Int,
                                  modelName: String,
                                  providerName: String = "") -> String {
        let capability = ModelCapabilityRegistry.capability(for: modelName,
                                                            providerName: providerName)
        let contextTokens = max(0, capability.contextTokens)
        guard contextTokens > 0 else { return "context unknown" }
        let safeEstimate = max(0, estimatedTextTokens)
        return "context \(safeEstimate)/\(contextTokens) tokens \(contextFitStatus(estimatedTextTokens: safeEstimate, contextTokens: contextTokens))"
    }

    static func contextFitStatus(estimatedTextTokens: Int,
                                 contextTokens: Int) -> String {
        let safeEstimate = max(0, estimatedTextTokens)
        let safeContext = max(0, contextTokens)
        guard safeContext > 0 else { return "unknown" }
        if safeEstimate > safeContext { return "over-limit" }
        if Double(safeEstimate) >= Double(safeContext) * 0.85 { return "near-limit" }
        return "ok"
    }

    static func imageFitSummary(hasImage: Bool,
                                modelName: String,
                                providerName: String = "") -> String {
        guard hasImage else { return "image not-required" }
        let supportsVision = ModelCapabilityRegistry.capability(for: modelName,
                                                                providerName: providerName).supportsVision
        return supportsVision ? "image supported" : "image unsupported"
    }

    static func reasoningFitSummary(requiresReasoning: Bool,
                                    modelName: String,
                                    providerName: String = "") -> String {
        guard requiresReasoning else { return "reasoning not-required" }
        let supportsReasoning = ModelCapabilityRegistry.capability(for: modelName,
                                                                   providerName: providerName).supportsReasoning
        return supportsReasoning ? "reasoning supported" : "reasoning unsupported"
    }

    func candidateFitIssueSummary(routes: [AIRequestRoute],
                                  hasImage: Bool,
                                  requiresReasoning: Bool) -> String {
        Self.candidateFitIssueSummary(routes: routes,
                                      estimatedTextTokens: estimatedTextTokens,
                                      hasImage: hasImage,
                                      requiresReasoning: requiresReasoning)
    }

    static func candidateFitIssueSummary(routes: [AIRequestRoute],
                                         estimatedTextTokens: Int,
                                         hasImage: Bool,
                                         requiresReasoning: Bool) -> String {
        guard !routes.isEmpty else { return "none" }
        var contextOverLimit = 0
        var contextNearLimit = 0
        var imageUnsupported = 0
        var reasoningUnsupported = 0

        for route in routes {
            let capability = ModelCapabilityRegistry.capability(for: route.modelName,
                                                                providerName: route.providerName)
            let contextFit = contextFitStatus(estimatedTextTokens: estimatedTextTokens,
                                              contextTokens: capability.contextTokens)
            if contextFit == "over-limit" {
                contextOverLimit += 1
            } else if contextFit == "near-limit" {
                contextNearLimit += 1
            }
            if hasImage && !capability.supportsVision {
                imageUnsupported += 1
            }
            if requiresReasoning && !capability.supportsReasoning {
                reasoningUnsupported += 1
            }
        }

        let parts = [
            contextOverLimit > 0 ? "context-over-limit=\(contextOverLimit)" : nil,
            contextNearLimit > 0 ? "context-near-limit=\(contextNearLimit)" : nil,
            imageUnsupported > 0 ? "image-unsupported=\(imageUnsupported)" : nil,
            reasoningUnsupported > 0 ? "reasoning-unsupported=\(reasoningUnsupported)" : nil
        ].compactMap { $0 }
        return parts.isEmpty ? "all-ok" : parts.joined(separator: "; ")
    }

    func candidateHardIssueSummary(routes: [AIRequestRoute],
                                   hasImage: Bool) -> String {
        Self.candidateHardIssueSummary(routes: routes,
                                       estimatedTextTokens: estimatedTextTokens,
                                       hasImage: hasImage)
    }

    static func candidateHardIssueSummary(routes: [AIRequestRoute],
                                          estimatedTextTokens: Int,
                                          hasImage: Bool) -> String {
        guard !routes.isEmpty else { return "none" }
        var contextOverLimit = 0
        var imageUnsupported = 0

        for route in routes {
            let capability = ModelCapabilityRegistry.capability(for: route.modelName,
                                                                providerName: route.providerName)
            let contextFit = contextFitStatus(estimatedTextTokens: estimatedTextTokens,
                                              contextTokens: capability.contextTokens)
            if contextFit == "over-limit" {
                contextOverLimit += 1
            }
            if hasImage && !capability.supportsVision {
                imageUnsupported += 1
            }
        }

        let parts = [
            contextOverLimit > 0 ? "context-over-limit=\(contextOverLimit)" : nil,
            imageUnsupported > 0 ? "image-unsupported=\(imageUnsupported)" : nil
        ].compactMap { $0 }
        return parts.isEmpty ? "all-ok" : parts.joined(separator: "; ")
    }
}

struct AIRequestDiagnostics: Equatable {
    static let preflightSkippedRouteDisplayLimit = 5
    static let suppressedVisibleRecoverySuggestions = Set(["无需处理", "等待请求开始", "等待当前模型返回"])
    static let suppressedVisibleRecoveryCodes = Set(["none", "pending", "waiting-current-route", "fallback-will-try-next"])

    var actionName: String
    var actionRequiresReasoning: Bool = false
    var sourceCharacterCount: Int
    var hasImage: Bool
    var fallbackEnabled: Bool
    var autoRouteEnabled: Bool = false
    var routingPreference: AIRoutingPreference
    var candidateCount: Int
    var actionPipeline: ActionPipelineDiagnostic = .empty
    var context: AIRequestContextDiagnostic = AIRequestContextDiagnostic()
    var payload: AIRequestPayloadDiagnostic = AIRequestPayloadDiagnostic()
    var submissionPrivacy: PrivacySubmissionDiagnostic? = nil
    var candidateRoutes: [AIRequestRoute] = []
    var candidateUnavailabilitySummary: String = "not-checked"
    var candidateUnavailabilityRecoverySuggestion: String = ""
    var attempts: [AIRequestAttemptDiagnostic] = []

    var summaryText: String {
        summaryText(includeAttemptMessages: true)
    }

    var briefSummaryText: String {
        summaryText(includeAttemptMessages: false)
    }

    var recommendedRouteSummary: String {
        guard let route = candidateRoutes.first else { return "none" }
        let routeSummary = "\(route.diagnosticProviderName) / \(route.diagnosticModelName)"
        let fitSummary = candidateFitSummary(for: route)
        return "\(routeSummary) - \(route.diagnosticReason) · \(fitSummary)"
    }

    var recommendedRouteIssueSummary: String {
        guard let route = candidateRoutes.first else { return "none" }
        return routeIssueSummary(for: route)
    }

    var firstRequestRouteSummary: String {
        guard let route = firstRequestRoute else { return "none" }
        let routeSummary = "\(route.diagnosticProviderName) / \(route.diagnosticModelName)"
        let fitSummary = candidateFitSummary(for: route)
        return "\(routeSummary) - \(route.diagnosticReason) · \(fitSummary)"
    }

    var firstRequestRouteIssueSummary: String {
        guard let route = firstRequestRoute else { return "none" }
        return routeIssueSummary(for: route)
    }

    var visibleRouteExplanation: String {
        if candidateCount <= 0 {
            let recovery = candidateUnavailabilityRecoverySuggestion.trimmingCharacters(in: .whitespacesAndNewlines)
            return recovery.isEmpty ? "没有可用模型,请检查供应商、API Key 和模型启用状态" : recovery
        }

        var parts: [String] = []
        if let route = firstRequestRoute {
            let routeName = "\(route.diagnosticProviderName) / \(route.diagnosticModelName)"
            parts.append("\(autoRouteEnabled ? "将优先使用" : "将使用") \(routeName)")
            parts.append(route.diagnosticReason)
        }
        parts.append(autoRouteEnabled ? "自动路由: \(routingPreference.rawValue)" : "固定当前模型")
        if fallbackEnabled { parts.append("失败时可 fallback") }
        if context.activeContextCharacterCount > 0 {
            parts.append("已合并上下文 \(context.activeContextCharacterCount) 字")
        }
        if payload.estimatedTextTokens > 0 {
            parts.append("约 \(payload.estimatedTextTokens) tokens")
        }
        if hasImage { parts.append("包含图片输入") }
        let skippedCount = preflightSkippedRoutes.count
        if skippedCount > 0 {
            parts.append("预检跳过 \(skippedCount) 个不适配模型")
        }
        return parts.joined(separator: " · ")
    }

    var visibleRouteStatusTitle: String {
        if candidateCount <= 0 { return "无可用模型" }
        if !autoRouteEnabled { return "固定模型" }
        return fallbackEnabled ? "自动路由 + Fallback" : "自动路由"
    }

    var preflightSkippedRouteSummary: String {
        preflightSkippedRouteSummary(limit: Self.preflightSkippedRouteDisplayLimit)
    }

    var attemptStatusSummary: String {
        guard !attempts.isEmpty else { return "none" }
        let counts = Dictionary(grouping: attempts, by: \.status).mapValues(\.count)
        var parts = ["total=\(attempts.count)"]
        for status in [AIRequestAttemptStatus.running, .skipped, .failed, .succeeded] {
            if let count = counts[status], count > 0 {
                parts.append("\(status.rawValue)=\(count)")
            }
        }
        return parts.joined(separator: "; ")
    }

    func latestAttemptSummary(includeMessage: Bool = false) -> String {
        guard let latest = attempts.last else { return "none" }
        return attemptSummaryLine(latest, includeMessage: includeMessage)
    }

    var requestOutcomeSummary: String {
        guard let latest = attempts.last else {
            return candidateCount <= 0 ? "blocked; no-candidate-routes" : "pending"
        }
        switch latest.status {
        case .running:
            return "running"
        case .succeeded:
            return "succeeded"
        case .skipped:
            return "skipped"
        case .failed:
            guard let fallbackDecision = latest.fallbackDecision else { return "failed" }
            return "failed; fallback=\(fallbackDecision.diagnosticCode)"
        }
    }

    var requestRecoverySuggestion: String {
        guard let latest = attempts.last else {
            if candidateCount <= 0 {
                let recovery = candidateUnavailabilityRecoverySuggestion.trimmingCharacters(in: .whitespacesAndNewlines)
                return recovery.isEmpty ? "在 AI 设置中启用供应商、模型并填写 API Key" : recovery
            }
            return "等待请求开始"
        }
        switch latest.status {
        case .running:
            return "等待当前模型返回"
        case .succeeded:
            return "无需处理"
        case .skipped:
            return skippedAttemptRecoverySuggestion(latest)
        case .failed:
            let errorRecovery = Self.recoveryHint(forErrorMessage: latest.message)?.suggestion
            switch latest.fallbackDecision?.reason {
            case .willTryNext:
                return "等待备用模型尝试"
            case .cloudFallbackRequiresConfirmation:
                return "本地模型失败;如需改用云端模型,请手动选择云端模型或关闭严格本地优先后重试"
            case .fallbackDisabled:
                return errorRecovery ?? "开启 fallback 或切换可用模型后重试"
            case .noNextRoute:
                return errorRecovery ?? "启用备用供应商或模型后重试"
            case .partialOutput:
                return "已收到部分输出;可复制结果或手动重试"
            case nil:
                return errorRecovery ?? "检查 API Key、网络、模型能力或复制完整请求诊断"
            }
        }
    }

    var requestRecoveryCode: String {
        guard let latest = attempts.last else {
            return candidateCount <= 0 ? "no-candidate-routes" : "pending"
        }
        switch latest.status {
        case .running:
            return "waiting-current-route"
        case .succeeded:
            return "none"
        case .skipped:
            return skippedAttemptRecoveryCode(latest)
        case .failed:
            if let hint = Self.recoveryHint(forErrorMessage: latest.message) {
                return hint.code
            }
            switch latest.fallbackDecision?.reason {
            case .willTryNext:
                return "fallback-will-try-next"
            case .cloudFallbackRequiresConfirmation:
                return "fallback-cloud-confirmation-required"
            case .fallbackDisabled:
                return "fallback-disabled"
            case .noNextRoute:
                return "fallback-no-next-route"
            case .partialOutput:
                return "fallback-partial-output"
            case nil:
                return "generic-failure"
            }
        }
    }

    static func visibleErrorRecoverySuggestion(diagnostics: AIRequestDiagnostics?,
                                               errorMessage: String?) -> String? {
        guard let visibleError = errorMessage?.trimmingCharacters(in: .whitespacesAndNewlines),
              !visibleError.isEmpty else {
            return nil
        }

        if let errorRecovery = recoveryHint(forErrorMessage: visibleError)?.suggestion,
           !suppressedVisibleRecoverySuggestions.contains(errorRecovery) {
            return errorRecovery
        }

        guard let suggestion = diagnostics?.requestRecoverySuggestion.trimmingCharacters(in: .whitespacesAndNewlines),
              !suggestion.isEmpty else {
            return nil
        }
        return suppressedVisibleRecoverySuggestions.contains(suggestion) ? nil : suggestion
    }

    static func visibleErrorRecoveryCode(diagnostics: AIRequestDiagnostics?,
                                         errorMessage: String?) -> String? {
        guard let visibleError = errorMessage?.trimmingCharacters(in: .whitespacesAndNewlines),
              !visibleError.isEmpty else {
            return nil
        }

        if let code = recoveryHint(forErrorMessage: visibleError)?.code,
           !suppressedVisibleRecoveryCodes.contains(code) {
            return code
        }

        guard let code = diagnostics?.requestRecoveryCode.trimmingCharacters(in: .whitespacesAndNewlines),
              !code.isEmpty,
              !suppressedVisibleRecoveryCodes.contains(code) else {
            return nil
        }
        return code
    }

    static func recoverySuggestion(forErrorMessage errorMessage: String?) -> String? {
        recoveryHint(forErrorMessage: errorMessage)?.suggestion
    }

    static func recoveryCode(forErrorMessage errorMessage: String?) -> String? {
        recoveryHint(forErrorMessage: errorMessage)?.code
    }

    static func recoveryHint(forErrorMessage errorMessage: String?) -> AIRequestRecoveryHint? {
        guard let raw = errorMessage?.trimmingCharacters(in: .whitespacesAndNewlines),
              !raw.isEmpty else {
            return nil
        }

        let text = raw.lowercased()
        func containsAny(_ needles: [String]) -> Bool {
            needles.contains { text.contains($0) }
        }

        if containsAny(["未配置 api key", "invalid_api_key", "incorrect api key", "invalid api key", "unauthorized", "authentication", "auth error"]) ||
            (text.contains("401") && containsAny(["http", "api key", "token", "unauthorized", "auth"])) {
            return AIRequestRecoveryHint(code: "api-key",
                                         suggestion: "在 AI 设置中重新填写 API Key,并确认供应商账号可用")
        }

        if containsAny(["没有可用的 ai 供应商", "没有可用供应商", "missing provider", "no available provider", "no enabled provider"]) {
            return AIRequestRecoveryHint(code: "missing-provider",
                                         suggestion: "在 AI 设置中添加或启用供应商")
        }

        if containsAny(["未选择可用模型", "未选择模型", "missing model", "no available model", "no enabled model"]) {
            return AIRequestRecoveryHint(code: "missing-model",
                                         suggestion: "在 AI 设置中启用或添加模型,并选择当前模型")
        }

        if containsAny(["insufficient_quota", "quota", "billing", "credit", "balance", "payment required", "额度", "余额", "账单", "欠费"]) {
            return AIRequestRecoveryHint(code: "quota",
                                         suggestion: "检查供应商账户额度、账单或充值状态,也可切换备用供应商")
        }

        if containsAny(["rate limit", "rate_limit", "too many requests", "429", "限速", "频率", "请求过多"]) {
            return AIRequestRecoveryHint(code: "rate-limit",
                                         suggestion: "触发限速;稍后重试、降低频率或切换备用供应商")
        }

        if containsAny(["context_length", "context length", "maximum context", "token limit", "too long", "exceeds", "input is too long", "上下文", "文本过长", "超过限制"]) {
            return AIRequestRecoveryHint(code: "context-limit",
                                         suggestion: "文本超过模型上下文限制;缩短内容或切换长上下文模型")
        }

        if containsAny(["image too large", "图片过大", "payload too large", "413"]) {
            return AIRequestRecoveryHint(code: "payload-too-large",
                                         suggestion: "图片或请求体过大;压缩图片、减少内容后重试")
        }

        if containsAny(["base url", "invalid url", "unsupported url", "url 无效", "明文端点", "insecure http", "not a valid url"]) {
            return AIRequestRecoveryHint(code: "base-url",
                                         suggestion: "检查 Base URL 配置;远程端点请使用 HTTPS")
        }

        if containsAny(["model_not_found", "model not found", "model does not exist", "not found", "404", "模型不存在", "未找到模型"]) {
            return AIRequestRecoveryHint(code: "model-not-found",
                                         suggestion: "检查模型名称和 Base URL 是否匹配该供应商")
        }

        if containsAny(["forbidden", "permission", "access denied", "not allowed", "403", "无权限", "权限不足", "禁止访问"]) {
            return AIRequestRecoveryHint(code: "permission",
                                         suggestion: "确认账号有该模型或端点权限,必要时切换模型或供应商")
        }

        if containsAny(["timed out", "timeout", "超时", "not connected", "internet connection", "cannot connect", "network", "offline", "dns", "proxy", "代理", "网络"]) {
            return AIRequestRecoveryHint(code: "network",
                                         suggestion: "检查网络、代理和 Base URL 连通性,必要时切换供应商")
        }

        if containsAny(["500", "502", "503", "504", "server error", "bad gateway", "service unavailable", "gateway timeout", "服务器错误", "服务不可用"]) {
            return AIRequestRecoveryHint(code: "provider-service",
                                         suggestion: "供应商服务暂时异常;稍后重试或切换备用供应商")
        }

        if containsAny(["cancelled", "canceled", "已取消"]) {
            return AIRequestRecoveryHint(code: "cancelled",
                                         suggestion: "请求已取消;确认网络稳定后重新发送")
        }

        if containsAny(["http 400", "http 422", "bad request", "invalid request", "unprocessable", "请求失败 (http 400)", "请求失败 (http 422)"]) {
            return AIRequestRecoveryHint(code: "invalid-request",
                                         suggestion: "检查模型能力、请求内容和 Base URL;必要时复制完整请求诊断")
        }

        return nil
    }

    static func noCandidateRouteReasonSummary(providers: [AIProvider]) -> String {
        guard !providers.isEmpty else { return "no-providers=1" }
        let readinesses = providers.map { AIRequestRouter.providerReadiness($0) }
        let readyCount = readinesses.filter(\.isReady).count
        if readyCount > 0 {
            return "ready-providers=\(readyCount); no-selected-route=1"
        }
        let counts = Dictionary(grouping: readinesses, by: { $0 }).mapValues(\.count)
        let parts = providerReadinessIssueOrder.compactMap { readiness -> String? in
            guard let count = counts[readiness], count > 0 else { return nil }
            return "\(readiness.diagnosticCode)=\(count)"
        }
        return parts.isEmpty ? "unknown=1" : parts.joined(separator: "; ")
    }

    static func noCandidateRouteRecoverySuggestion(providers: [AIProvider]) -> String {
        guard !providers.isEmpty else { return "在 AI 设置中添加并启用供应商" }
        let readinesses = providers.map { AIRequestRouter.providerReadiness($0) }
        let readyCount = readinesses.filter(\.isReady).count
        if readyCount > 0 {
            return "在 AI 设置中选择当前模型,或开启自动路由/fallback"
        }
        let counts = Dictionary(grouping: readinesses, by: { $0 }).mapValues(\.count)
        let parts = providerReadinessIssueOrder.compactMap { readiness -> String? in
            guard let count = counts[readiness], count > 0 else { return nil }
            let suggestion = AIRequestRouter.providerRecoverySuggestion(providers: providers, readiness: readiness)
            return "\(readiness.diagnosticCode)=\(count): \(suggestion)"
        }
        return parts.isEmpty ? "检查 AI 供应商、模型、API Key 和 Base URL 配置" : parts.joined(separator: "; ")
    }

    var cloudFallbackReviewSummary: String {
        let localCount = candidateRoutes.filter(\.isLocalEndpoint).count
        let cloudCount = candidateRoutes.filter { !$0.isLocalEndpoint }.count
        guard actionPipeline.modelPolicy == "auto-route-local-first",
              localCount > 0,
              cloudCount > 0 else {
            return "not-needed; local=\(localCount); cloud=\(cloudCount)"
        }
        return "confirmation-required; local=\(localCount); cloud=\(cloudCount)"
    }

    func requiresCloudFallbackConfirmation(from failedRoute: AIRequestRoute,
                                           to nextRoute: AIRequestRoute?) -> Bool {
        guard fallbackEnabled,
              actionPipeline.modelPolicy == "auto-route-local-first",
              failedRoute.isLocalEndpoint,
              let nextRoute,
              !nextRoute.isLocalEndpoint else {
            return false
        }
        return true
    }

    var healthStatusLine: String {
        let outcome = Self.diagnosticHealthValue(requestOutcomeSummary, fallback: "pending", limit: 120)
        let recoveryCode = Self.diagnosticHealthValue(requestRecoveryCode, fallback: "none", limit: 80)
        let recovery = Self.diagnosticHealthValue(requestRecoverySuggestion, fallback: "none", limit: 180)
        let latest = Self.diagnosticHealthValue(latestAttemptSummary(includeMessage: false), fallback: "none", limit: 220)
        return "outcome=\(outcome), recoveryCode=\(recoveryCode), recovery=\(recovery), latest=\(latest)"
    }

    func preflightSkippedRouteSummary(limit: Int) -> String {
        guard autoRouteEnabled else { return "disabled" }
        let skippedRoutes = preflightSkippedRoutes
        guard !skippedRoutes.isEmpty else { return "none" }
        let displayLimit = max(1, limit)
        let displayedRoutes = Array(skippedRoutes.prefix(displayLimit))
        var parts = displayedRoutes.enumerated()
            .map { index, route in
                let routeSummary = "\(route.diagnosticProviderName) / \(route.diagnosticModelName)"
                return "\(index + 1). \(routeSummary) - \(routeHardIssueSummary(for: route))"
            }
        let hiddenCount = skippedRoutes.count - displayedRoutes.count
        if hiddenCount > 0 {
            parts.append("+\(hiddenCount) more")
        }
        return parts.joined(separator: " | ")
    }

    var firstRequestRoute: AIRequestRoute? {
        guard !candidateRoutes.isEmpty else { return nil }
        for (index, route) in candidateRoutes.enumerated() {
            let hasNextRoute = candidateRoutes.indices.contains(index + 1)
            if shouldSkipRouteBeforeRequest(route,
                                            autoRouteEnabled: autoRouteEnabled,
                                            hasNextRoute: hasNextRoute) {
                continue
            }
            return route
        }
        return candidateRoutes.last
    }

    var preflightSkippedRoutes: [AIRequestRoute] {
        guard autoRouteEnabled else { return [] }
        return candidateRoutes.enumerated().compactMap { index, route in
            let hasNextRoute = candidateRoutes.indices.contains(index + 1)
            return shouldSkipRouteBeforeRequest(route,
                                                autoRouteEnabled: true,
                                                hasNextRoute: hasNextRoute) ? route : nil
        }
    }

    func routeIssueSummary(for route: AIRequestRoute) -> String {
        payload.candidateFitIssueSummary(routes: [route],
                                         hasImage: hasImage,
                                         requiresReasoning: actionRequiresReasoning)
    }

    func routeHardIssueSummary(for route: AIRequestRoute) -> String {
        payload.candidateHardIssueSummary(routes: [route],
                                          hasImage: hasImage)
    }

    func shouldSkipRouteBeforeRequest(_ route: AIRequestRoute,
                                      autoRouteEnabled: Bool,
                                      hasNextRoute: Bool) -> Bool {
        guard autoRouteEnabled, hasNextRoute else { return false }
        let hardIssues = routeHardIssueSummary(for: route)
        return hardIssues != "all-ok" && hardIssues != "none"
    }

    func routeSkipMessage(for route: AIRequestRoute) -> String {
        "跳过明显不适配路由: \(routeHardIssueSummary(for: route))"
    }

    func skippedAttemptRecoveryCode(_ attempt: AIRequestAttemptDiagnostic) -> String {
        if Self.isRouteConfigurationSkipMessage(attempt.message) {
            return "route-unavailable"
        }
        return routeSkipRecoveryCode(for: attempt.route)
    }

    func skippedAttemptRecoverySuggestion(_ attempt: AIRequestAttemptDiagnostic) -> String {
        if Self.isRouteConfigurationSkipMessage(attempt.message) {
            return "在 AI 设置中重新启用供应商或模型,或切换当前模型"
        }
        return routeSkipRecoverySuggestion(for: attempt.route)
    }

    static func isRouteConfigurationSkipMessage(_ message: String?) -> Bool {
        guard let text = message?.trimmingCharacters(in: .whitespacesAndNewlines),
              !text.isEmpty else {
            return false
        }
        return text.contains("路由模型不可用") || text.contains("供应商已禁用")
    }

    func routeSkipRecoveryCode(for route: AIRequestRoute) -> String {
        let issues = routeHardIssueSummary(for: route)
        let hasContextLimit = issues.contains("context-over-limit")
        let hasImageUnsupported = issues.contains("image-unsupported")
        if hasContextLimit && hasImageUnsupported {
            return "preflight-context-limit-image-unsupported"
        }
        if hasContextLimit {
            return "preflight-context-limit"
        }
        if hasImageUnsupported {
            return "preflight-image-unsupported"
        }
        return "preflight-skipped"
    }

    func routeSkipRecoverySuggestion(for route: AIRequestRoute) -> String {
        switch routeSkipRecoveryCode(for: route) {
        case "preflight-context-limit-image-unsupported":
            return "文本超过该模型上下文且模型不支持图片;切换长上下文视觉模型或缩短内容"
        case "preflight-context-limit":
            return "文本超过该模型上下文限制;缩短内容或切换长上下文模型"
        case "preflight-image-unsupported":
            return "当前模型不支持图片;切换支持视觉的模型或移除图片"
        default:
            return "检查自动路由跳过原因;如需强制使用该模型,关闭自动路由"
        }
    }

    func routeSkipSwitchNote(for skippedRoute: AIRequestRoute,
                             nextRoute: AIRequestRoute?) -> String {
        let skipped = "\(skippedRoute.diagnosticProviderName) / \(skippedRoute.diagnosticModelName)"
        let issues = routeHardIssueSummary(for: skippedRoute)
        guard let nextRoute else {
            return "已跳过 \(skipped): \(issues)"
        }
        let next = "\(nextRoute.diagnosticProviderName) / \(nextRoute.diagnosticModelName)"
        return "已跳过 \(skipped): \(issues)。正在尝试 \(next)"
    }

    func routeDisplayNote(for route: AIRequestRoute) -> String {
        let issues = routeIssueSummary(for: route)
        guard issues != "all-ok", issues != "none" else {
            return route.displayRouteNote
        }
        return "\(route.displayRouteNote) · 适配问题: \(issues)"
    }

    func summaryText(includeAttemptMessages: Bool) -> String {
        var lines = [
            "SnapAI Request Diagnostics",
            "Action: \(AIRequestDiagnosticText.metadata(actionName, fallback: "未命名动作", maxLength: 80))",
            "Source Characters: \(sourceCharacterCount)",
            "Has Image: \(hasImage ? "yes" : "no")",
            "Pipeline Input: \(actionPipeline.inputPolicy)",
            "Pipeline Privacy: \(actionPipeline.privacyPolicy)",
            "Pipeline Output: \(actionPipeline.outputPolicy)",
            "Pipeline Model: \(actionPipeline.modelPolicy)",
            "Fallback Enabled: \(fallbackEnabled ? "yes" : "no")",
            "Auto Route Enabled: \(autoRouteEnabled ? "yes" : "no")",
            "Routing Preference: \(routingPreference.rawValue)",
            "Candidate Routes: \(candidateCount)",
            "Candidate Unavailability: \(candidateCount <= 0 ? candidateUnavailabilitySummary : "not-needed")",
            "Candidate Unavailability Recovery: \(candidateCount <= 0 ? candidateUnavailabilityRecoverySuggestion : "not-needed")",
            "Candidate Fit Issues: \(payload.candidateFitIssueSummary(routes: candidateRoutes, hasImage: hasImage, requiresReasoning: actionRequiresReasoning))",
            "Recommended Route: \(recommendedRouteSummary)",
            "Recommended Route Issues: \(recommendedRouteIssueSummary)",
            "First Request Route: \(firstRequestRouteSummary)",
            "First Request Route Issues: \(firstRequestRouteIssueSummary)",
            "Cloud Fallback Review: \(cloudFallbackReviewSummary)",
            "Preflight Skipped Routes: \(preflightSkippedRouteSummary)",
            "Attempt Statuses: \(attemptStatusSummary)",
            "Latest Attempt: \(latestAttemptSummary(includeMessage: includeAttemptMessages))",
            "Request Outcome: \(requestOutcomeSummary)",
            "Request Recovery Code: \(requestRecoveryCode)",
            "Request Recovery: \(requestRecoverySuggestion)"
        ]
        lines.append(contentsOf: context.summaryLines)
        lines.append(contentsOf: payload.summaryLines)
        if let submissionPrivacy {
            lines.append(contentsOf: submissionPrivacy.summaryLines)
        }
        if candidateRoutes.isEmpty {
            lines.append("Candidate Details: none")
        } else {
            lines.append("Candidate Details:")
            for (index, route) in candidateRoutes.enumerated() {
                let routeSummary = "\(route.diagnosticProviderName) / \(route.diagnosticModelName)"
                let fitSummary = candidateFitSummary(for: route)
                lines.append("\(index + 1). \(routeSummary) - \(route.diagnosticReason) · \(fitSummary)")
            }
        }
        if attempts.isEmpty {
            lines.append("Attempts: none")
        } else {
            lines.append("Attempts:")
            for (index, attempt) in attempts.enumerated() {
                lines.append("\(index + 1). \(attemptSummaryLine(attempt, includeMessage: includeAttemptMessages))")
            }
        }
        return lines.joined(separator: "\n")
    }

    private func attemptSummaryLine(_ attempt: AIRequestAttemptDiagnostic,
                                    includeMessage: Bool) -> String {
        let base = attempt.summaryLine(includeMessage: includeMessage)
        let issues = routeIssueSummary(for: attempt.route)
        guard issues != "all-ok", issues != "none" else { return base }
        return "\(base) · Route Issues \(issues)"
    }

    private func candidateFitSummary(for route: AIRequestRoute) -> String {
        [
            payload.contextFitSummary(for: route),
            payload.imageFitSummary(for: route, hasImage: hasImage),
            payload.reasoningFitSummary(for: route, requiresReasoning: actionRequiresReasoning)
        ].joined(separator: " · ")
    }

    private static func diagnosticHealthValue(_ value: String,
                                              fallback: String,
                                              limit: Int) -> String {
        let text = SensitiveTextSanitizer.sanitizedMessage(value, limit: limit)
            .replacingOccurrences(of: "\n", with: " ")
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? fallback : trimmed
    }

    private static var providerReadinessIssueOrder: [AIRequestRouter.ProviderReadiness] {
        [.disabled, .missingAPIKey, .noEnabledModels, .invalidBaseURL, .remoteHTTP]
    }

    mutating func mark(route: AIRequestRoute,
                       status: AIRequestAttemptStatus,
                       message: String? = nil,
                       elapsedMilliseconds: Int? = nil,
                       outputCharacterCount: Int? = nil,
                       fallbackDecision: AIRequestFallbackDecision? = nil) {
        if let index = attempts.lastIndex(where: { $0.route.id == route.id }) {
            attempts[index].status = status
            attempts[index].message = message
            attempts[index].elapsedMilliseconds = elapsedMilliseconds ?? attempts[index].elapsedMilliseconds
            attempts[index].outputCharacterCount = outputCharacterCount ?? attempts[index].outputCharacterCount
            attempts[index].fallbackDecision = fallbackDecision ?? attempts[index].fallbackDecision
        } else {
            attempts.append(AIRequestAttemptDiagnostic(route: route,
                                                       status: status,
                                                       message: message,
                                                       elapsedMilliseconds: elapsedMilliseconds,
                                                       outputCharacterCount: outputCharacterCount,
                                                       fallbackDecision: fallbackDecision))
        }
    }
}

enum AIRequestDiagnosticText {
    static func metadata(_ value: String,
                         fallback: String,
                         maxLength: Int) -> String {
        MarkdownExportSafety.metadata(value, fallback: fallback, maxLength: maxLength)
    }
}
