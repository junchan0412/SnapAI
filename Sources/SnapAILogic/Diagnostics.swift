import AppKit
import ApplicationServices
import Foundation

package struct PermissionProviderRequestStatus: Equatable {
    package var isReady: Bool
    package var diagnosticCode: String
    package var displayText: String
    package var recoverySuggestion: String

    package init(isReady: Bool,
         diagnosticCode: String,
         displayText: String,
         recoverySuggestion: String) {
        self.isReady = isReady
        self.diagnosticCode = diagnosticCode
        self.displayText = displayText
        self.recoverySuggestion = recoverySuggestion
    }

    package init(readiness: AIRequestRouter.ProviderReadiness) {
        self.init(isReady: readiness.isReady,
                  diagnosticCode: readiness.diagnosticCode,
                  displayText: readiness.displayText,
                  recoverySuggestion: readiness.recoverySuggestion)
    }

    package init(provider: AIProvider) {
        let readiness = AIRequestRouter.providerReadiness(provider)
        self.init(isReady: readiness.isReady,
                  diagnosticCode: readiness.diagnosticCode,
                  displayText: readiness.displayText,
                  recoverySuggestion: AIRequestRouter.providerRecoverySuggestion(provider))
    }

    package static let missingActiveProvider = PermissionProviderRequestStatus(
        isReady: false,
        diagnosticCode: "missing-active-provider",
        displayText: "未选择供应商",
        recoverySuggestion: "在 AI 设置中选择并启用供应商"
    )

    package static let missingConfiguredActiveProvider = PermissionProviderRequestStatus(
        isReady: false,
        diagnosticCode: "missing-active-provider",
        displayText: "当前供应商不存在",
        recoverySuggestion: "在 AI 设置中重新选择供应商"
    )
}

package struct PermissionRequestReadinessSummary: Equatable {
    package var enabledProviderCount: Int
    package var readyProviderCount: Int
    package var activeProvider: PermissionProviderRequestStatus
    package var unavailableReasonSummary: String
    package var unavailableRecoverySummary: String

    package var activeProviderReady: Bool { activeProvider.isReady }
    package var activeProviderStatus: String { activeProvider.diagnosticCode }
    package var activeProviderStatusText: String { activeProvider.displayText }
    package var activeProviderRecoverySuggestion: String { activeProvider.recoverySuggestion }

    package var statusLine: String {
        if enabledProviderCount == 0 {
            return "没有启用供应商"
        }
        let base = "可请求 \(readyProviderCount)/\(enabledProviderCount) 个启用供应商"
        guard !activeProviderReady else { return base }
        return "\(base) · 当前: \(activeProviderStatusText)"
    }

    package var detailLine: String {
        let activeState = activeProviderReady ? "当前可用" : "当前: \(activeProviderStatusText)"
        let recovery = unavailableRecoverySummary == "none" ? "无异常" : unavailableRecoverySummary
        return "\(readyProviderCount)/\(enabledProviderCount) 可请求 · \(activeState) · \(recovery)"
    }

    package static let missingActiveProvider = PermissionRequestReadinessSummary(
        enabledProviderCount: 0,
        readyProviderCount: 0,
        activeProvider: .missingActiveProvider,
        unavailableReasonSummary: "none",
        unavailableRecoverySummary: "none"
    )
}

package struct PermissionAPIKeyHealthSummary: Equatable {
    package var providerCount: Int
    package var configuredProviderCount: Int
    package var enabledProviderMissingCount: Int

    package var statusLine: String {
        if providerCount == 0 {
            return "尚未配置供应商"
        }
        if enabledProviderMissingCount > 0 {
            return "\(enabledProviderMissingCount) 个启用供应商缺少 API Key"
        }
        return "\(configuredProviderCount)/\(providerCount) 个供应商已配置"
    }

    package var detailLine: String {
        "\(configuredProviderCount)/\(providerCount) 已配置 · 启用但缺失 \(enabledProviderMissingCount)"
    }
}

package enum ICloudStatusSummary {
    package static func make(settings: AppSettings) -> String {
        guard settings.iCloudSyncEnabled else { return "disabled" }
        let status = PermissionHealthSnapshot.diagnosticValue(settings.iCloudLastSyncStatus,
                                                              fallback: "未同步",
                                                              limit: 120)
        let remoteDevice = PermissionHealthSnapshot.diagnosticValue(settings.iCloudLastRemoteDeviceID,
                                                                    fallback: "none",
                                                                    limit: 80)
        let updatedAt = settings.iCloudUpdatedAt.map { ISO8601DateFormatter().string(from: $0) } ?? "none"
        let syncedAt = settings.iCloudLastSyncAt.map { ISO8601DateFormatter().string(from: $0) } ?? "none"
        return "enabled, revision=\(max(0, settings.iCloudRevision)), localChanges=\(settings.iCloudHasLocalChanges ? "yes" : "no"), updatedAt=\(updatedAt), lastSyncAt=\(syncedAt), remoteDevice=\(remoteDevice), status=\(status)"
    }
}

package struct PermissionHealthRecoverySuggestion: Equatable, Hashable {
    package var title: String
    package var detail: String
}

package enum PermissionRecoveryCommand {
    package static let title = "复制权限修复建议"
    package static let subtitle = "只复制权限健康中心当前建议"
    package static let systemImage = "lightbulb"
    package static let keywords = "permission health recovery suggestion suggestions fix copy diagnostics 权限 健康 修复 建议 复制 诊断"

    package static func subtitle(statusLine: String) -> String {
        let safeStatus = PermissionHealthSnapshot.diagnosticValue(statusLine,
                                                                  fallback: "未知",
                                                                  limit: 80)
        return "当前: \(safeStatus), 复制修复建议"
    }
}

package struct PermissionHealthSnapshot {
    package var appVersion: String
    package var macOSVersion: String
    package var bundleID: String
    package var installPath: String
    package var accessibilityGranted: Bool
    package var screenCaptureGranted: Bool
    package var launchAtLogin: Bool
    package var showDockIcon: Bool
    package var installDirectoryWritable: Bool
    package var quarantineStatus: String
    package var latestInstallLogPath: String
    package var latestInstallLogAvailable: Bool
    package var latestInstallLogStatus: String = "unknown"
    package var latestInstallLogRecoverySuggestion: String = "重新检查更新后再复制诊断"
    package var signingSummary: String
    package var hotKeyFailures: [String]
    package var activeModel: String
    package var providerCount: Int
    package var enabledProviderCount: Int = 0
    package var requestReadyProviderCount: Int = 0
    package var activeProviderRequestReady: Bool = false
    package var activeProviderRequestStatus: String = "missing-active-provider"
    package var activeProviderRequestStatusText: String = "未选择供应商"
    package var activeProviderRequestRecoverySuggestion: String = "在 AI 设置中选择并启用供应商"
    package var unavailableRequestReasonSummary: String = "none"
    package var unavailableRequestRecoverySummary: String = "none"
    package var recentAIRequestStatus: String = "none"
    package var apiKeyConfiguredProviderCount: Int = 0
    package var enabledProviderMissingAPIKeyCount: Int = 0
    package var secretStoreStatus: String = "unknown"
    package var textCaptureStatus: String = "none"
    package var writeBackStatus: String
    package var privacyPreviewEnabled: Bool = false
    package var redactionEnabled: Bool = false
    package var redactionRuleCount: Int = 0
    package var invalidRedactionRuleCount: Int = 0
    package var historyContentStorage: HistoryContentStorage = .full
    package var historyStoreStatus: String = "unknown"
    package var iCloudSyncStatus: String = "disabled"
    package var contextProfileCount: Int = 0
    package var usableContextProfileCount: Int = 0
    package var activeContextProfileName: String = "none"
    package var activeContextCharacterCount: Int = 0
    package var globalSystemPromptCharacterCount: Int = 0
    package var effectiveSystemPromptCharacterCount: Int = 0
    package var workModeTitle: String = "标准模式"
    package var workModeDetail: String = "平衡日常效率与完整历史记录。"

    package var diagnosticText: String {
        """
        SnapAI Diagnostics
        Version: \(appVersion)
        macOS: \(Self.diagnosticValue(macOSVersion))
        Bundle ID: \(Self.diagnosticValue(bundleID))
        Install Path: \(Self.shareablePath(installPath))
        Accessibility: \(accessibilityGranted ? "granted" : "missing")
        Screen Recording: \(screenCaptureGranted ? "granted" : "missing")
        Launch At Login: \(launchAtLogin ? "enabled" : "disabled")
        Dock Icon: \(showDockIcon ? "visible" : "hidden")
        Install Directory Writable: \(installDirectoryWritable ? "yes" : "no")
        Quarantine: \(Self.diagnosticValue(quarantineStatus, limit: 180))
        Latest Install Log: \(Self.shareablePath(latestInstallLogPath))
        Latest Install Log Status: \(Self.diagnosticValue(latestInstallLogStatus))
        Latest Install Log Recovery: \(Self.diagnosticValue(latestInstallLogRecoverySuggestion))
        Latest Install Log Available: \(latestInstallLogAvailable ? "yes" : "no")
        Active Model: \(Self.diagnosticValue(activeModel, fallback: "未选择"))
        Work Mode: \(Self.diagnosticValue(workModeTitle))
        Work Mode Detail: \(Self.diagnosticValue(workModeDetail))
        Providers: \(providerCount)
        Enabled Providers: \(enabledProviderCount)
        Request Ready Providers: \(requestReadyProviderCount)/\(enabledProviderCount)
        Active Provider Request Ready: \(activeProviderRequestReady ? "yes" : "no")
        Active Provider Request Status: \(Self.diagnosticValue(activeProviderRequestStatus))
        Active Provider Request Recovery: \(Self.diagnosticValue(activeProviderRequestRecoverySuggestion))
        Unavailable Request Reasons: \(Self.diagnosticValue(unavailableRequestReasonSummary))
        Unavailable Request Recovery: \(Self.diagnosticValue(unavailableRequestRecoverySummary))
        Recent AI Request: \(Self.diagnosticValue(recentAIRequestStatus, limit: 500))
        API Keys: \(apiKeyConfiguredProviderCount)/\(providerCount) configured; enabled missing \(enabledProviderMissingAPIKeyCount)
        Secret Store: \(Self.diagnosticValue(secretStoreStatus, limit: 240))
        Text Capture: \(Self.diagnosticValue(textCaptureStatus))
        Write Back: \(Self.diagnosticValue(writeBackStatus))
        Privacy Preview: \(privacyPreviewEnabled ? "enabled" : "disabled")
        Local Redaction: \(redactionEnabled ? "enabled" : "disabled")
        Redaction Rules: \(redactionRuleCount) (invalid \(invalidRedactionRuleCount))
        History Content Storage: \(historyContentStorage.rawValue)
        History Store: \(Self.diagnosticValue(historyStoreStatus, limit: 240))
        iCloud Sync: \(Self.diagnosticValue(iCloudSyncStatus, limit: 240))
        Context Profiles: \(contextProfileCount) (usable \(usableContextProfileCount))
        Active Context: \(activeContextCharacterCount > 0 ? "set" : "none")
        Active Context Name Characters: \(activeContextCharacterCount > 0 ? activeContextProfileName.count : 0)
        Active Context Characters: \(activeContextCharacterCount)
        Global System Prompt Characters: \(globalSystemPromptCharacterCount)
        Effective System Prompt Characters: \(effectiveSystemPromptCharacterCount)
        Signing: \(Self.diagnosticValue(signingSummary, limit: 1_000))
        HotKey Failures: \(Self.diagnosticList(hotKeyFailures))
        Recovery Suggestion Count: \(recoverySuggestionCount)
        Recovery Suggestion Status: \(recoverySuggestionStatusLine)
        Recovery Suggestions: \(recoverySuggestionSummary(limit: 1_000))
        """
    }

    package var briefDiagnosticText: String {
        """
        SnapAI Diagnostics Summary
        Version: \(appVersion)
        macOS: \(Self.diagnosticValue(macOSVersion))
        Bundle ID: \(Self.diagnosticValue(bundleID))
        Install Path: \(Self.shareablePath(installPath))
        Accessibility: \(accessibilityGranted ? "granted" : "missing")
        Screen Recording: \(screenCaptureGranted ? "granted" : "missing")
        Launch At Login: \(launchAtLogin ? "enabled" : "disabled")
        Dock Icon: \(showDockIcon ? "visible" : "hidden")
        Install Directory Writable: \(installDirectoryWritable ? "yes" : "no")
        Quarantine: \(Self.diagnosticValue(quarantineStatus, limit: 120))
        Latest Install Log Status: \(Self.diagnosticValue(latestInstallLogStatus))
        Active Model: \(Self.diagnosticValue(activeModel, fallback: "未选择"))
        Work Mode: \(Self.diagnosticValue(workModeTitle)) - \(Self.diagnosticValue(workModeDetail, limit: 160))
        AI Request: \(Self.diagnosticValue(requestReadinessStatusLine, limit: 180))
        Recent AI Request: \(Self.diagnosticValue(recentAIRequestStatus, limit: 240))
        API Key Health: \(Self.diagnosticValue(apiKeyHealthStatusLine, limit: 160))
        Secret Store: \(Self.diagnosticValue(secretStoreStatus, limit: 160))
        Text Capture: \(Self.diagnosticValue(textCaptureStatus, limit: 180))
        Write Back: \(Self.diagnosticValue(writeBackStatus, limit: 180))
        Privacy: preview \(privacyPreviewEnabled ? "enabled" : "disabled"), redaction \(redactionEnabled ? "enabled" : "disabled"), invalid rules \(invalidRedactionRuleCount)/\(redactionRuleCount)
        History Content Storage: \(historyContentStorage.rawValue)
        History Store: \(Self.diagnosticValue(historyStoreStatus, limit: 180))
        iCloud Sync: \(Self.diagnosticValue(iCloudSyncStatus, limit: 180))
        Context: \(usableContextProfileCount)/\(contextProfileCount) usable; active \(activeContextCharacterCount > 0 ? "set" : "none"); effective prompt \(effectiveSystemPromptCharacterCount) chars
        Signing: \(Self.diagnosticValue(signingSummary, limit: 240))
        HotKey Failures: \(Self.diagnosticList(hotKeyFailures, limit: 240))
        Recovery Suggestion Count: \(recoverySuggestionCount)
        Recovery Suggestion Status: \(recoverySuggestionStatusLine)
        Recovery Suggestions: \(recoverySuggestionSummary(limit: 360))
        """
    }

    package var requestReadinessStatusLine: String {
        requestReadinessSummary.statusLine
    }

    package var requestReadinessDetailLine: String {
        requestReadinessSummary.detailLine
    }

    package var apiKeyHealthStatusLine: String {
        apiKeyHealthSummary.statusLine
    }

    package var apiKeyHealthDetailLine: String {
        apiKeyHealthSummary.detailLine
    }

    package var recoverySuggestions: [PermissionHealthRecoverySuggestion] {
        var suggestions: [PermissionHealthRecoverySuggestion] = []

        func add(_ title: String, _ detail: String) {
            let safeTitle = Self.diagnosticValue(title, fallback: "", limit: 48)
            let safeDetail = Self.diagnosticValue(detail, fallback: "", limit: 220)
            guard !safeTitle.isEmpty,
                  !safeDetail.isEmpty,
                  safeDetail != "none",
                  safeDetail != "无需处理" else {
                return
            }
            let suggestion = PermissionHealthRecoverySuggestion(title: safeTitle, detail: safeDetail)
            guard !suggestions.contains(suggestion) else { return }
            suggestions.append(suggestion)
        }

        if !accessibilityGranted {
            add("辅助功能", "授予辅助功能权限后重试取词、替换和追加")
        }
        if !screenCaptureGranted {
            add("屏幕录制", "在系统设置中允许 SnapAI 使用屏幕录制,然后重试截图提问")
        }
        if !installDirectoryWritable {
            add("更新权限", "将 SnapAI 放在可写的应用目录后再检查更新")
        }
        if quarantineStatus.hasPrefix("present") {
            add("Quarantine", "运行 xattr -cr 清除 SnapAI.app 的隔离属性后重新打开")
        }
        if latestInstallLogStatus != "available",
           latestInstallLogStatus != "no-record" {
            add("更新日志", latestInstallLogRecoverySuggestion)
        }
        if !hotKeyFailures.isEmpty {
            add("快捷键", "重新录制冲突快捷键,或在设置中恢复默认快捷键")
        }
        if enabledProviderMissingAPIKeyCount > 0 {
            add("API Key", "在 AI 设置中补齐启用供应商的 API Key")
        }
        if secretStoreStatus.contains("writeFailures=") {
            add("本地密钥", "本地加密密钥保存失败。请检查 Application Support 目录权限,或重新填写 API Key 后再复制诊断")
        }
        if !activeProviderRequestReady {
            add("AI 请求", activeProviderRequestRecoverySuggestion)
        }
        if enabledProviderCount > requestReadyProviderCount {
            add("备用供应商", unavailableRequestRecoverySummary)
        }
        if let outcome = Self.diagnosticField("outcome", in: recentAIRequestStatus),
           !["none", "pending", "running", "succeeded"].contains(outcome),
           let recovery = Self.diagnosticField("recovery", in: recentAIRequestStatus) {
            add("最近 AI 请求", recovery)
        }
        if invalidRedactionRuleCount > 0 {
            add("脱敏规则", "修正或禁用无效脱敏规则,避免发送前预览遗漏敏感内容")
        }
        if Self.diagnosticField("state", in: textCaptureStatus) == "no-selection",
           let recovery = Self.diagnosticField("recovery", in: textCaptureStatus) {
            add("取词", recovery)
        }
        if let writeBackState = Self.diagnosticField("state", in: writeBackStatus),
           writeBackState != "available",
           let recovery = Self.diagnosticField("recovery", in: writeBackStatus) {
            add("写回", recovery)
        }

        return suggestions
    }

    package var recoverySuggestionCount: Int {
        recoverySuggestions.count
    }

    package var recoverySuggestionStatusLine: String {
        recoverySuggestionCount == 0 ? "无需处理" : "\(recoverySuggestionCount) 条建议"
    }

    package func recoverySuggestionSummary(limit: Int = 800) -> String {
        let text = recoverySuggestions
            .map { "\($0.title): \($0.detail)" }
            .joined(separator: "; ")
        return Self.diagnosticValue(text, fallback: "none", limit: limit)
    }

    package var recoverySuggestionClipboardText: String {
        let lines = recoverySuggestions.map { suggestion in
            "- \(suggestion.title): \(suggestion.detail)"
        }
        let body = lines.isEmpty ? "暂无需要处理的建议" : lines.joined(separator: "\n")
        let sanitized = SensitiveTextSanitizer.sanitizedDiagnosticText("SnapAI 修复建议\n\(body)", limit: 1_200)
        return sanitized.isEmpty ? "SnapAI 修复建议\n暂无需要处理的建议" : sanitized
    }

    private var requestReadinessSummary: PermissionRequestReadinessSummary {
        PermissionRequestReadinessSummary(
            enabledProviderCount: enabledProviderCount,
            readyProviderCount: requestReadyProviderCount,
            activeProvider: PermissionProviderRequestStatus(
                isReady: activeProviderRequestReady,
                diagnosticCode: activeProviderRequestStatus,
                displayText: activeProviderRequestStatusText,
                recoverySuggestion: activeProviderRequestRecoverySuggestion
            ),
            unavailableReasonSummary: unavailableRequestReasonSummary,
            unavailableRecoverySummary: unavailableRequestRecoverySummary
        )
    }

    private var apiKeyHealthSummary: PermissionAPIKeyHealthSummary {
        PermissionAPIKeyHealthSummary(
            providerCount: providerCount,
            configuredProviderCount: apiKeyConfiguredProviderCount,
            enabledProviderMissingCount: enabledProviderMissingAPIKeyCount
        )
    }

    package static func make(settings: AppSettings,
                     hotKeyFailures: [String],
                     textCaptureStatus: String = "none",
                     writeBackStatus: String = "none",
                     recentAIRequestStatus: String = "none",
                     installLogStatus: PermissionInstallLogStatus = .noRecord,
                     includeSigningSummary: Bool = true) -> PermissionHealthSnapshot {
        let info = Bundle.main.infoDictionary ?? [:]
        let version = info["CFBundleShortVersionString"] as? String ?? "0.0.0"
        let bundleID = Bundle.main.bundleIdentifier ?? "unknown"
        let appURL = Bundle.main.bundleURL
        let installPath = appURL.path
        let os = ProcessInfo.processInfo.operatingSystemVersionString
        let active = activeModelSummary(settings: settings)
        let requestReadiness = requestReadiness(settings: settings)
        let apiKeyHealth = apiKeyHealth(settings: settings)
        let secretStoreStatus = settings.secretStoreStatus == "not-checked"
            ? LocalSecretStore.diagnosticSummary()
            : settings.secretStoreStatus
        let invalidRedactionRules = settings.redactionRules.filter {
            PrivacyFilter.validatePattern($0.pattern) != nil
        }.count
        let contextSummary = settings.contextStatusSummary
        return PermissionHealthSnapshot(
            appVersion: version,
            macOSVersion: os,
            bundleID: bundleID,
            installPath: installPath,
            accessibilityGranted: TextCapture.hasAccessibilityPermission(),
            screenCaptureGranted: CGPreflightScreenCaptureAccess(),
            launchAtLogin: LoginItem.isEnabled,
            showDockIcon: settings.showDockIcon,
            installDirectoryWritable: installDirectoryWritable(for: appURL),
            quarantineStatus: quarantineSummary(for: appURL),
            latestInstallLogPath: installLogStatus.diagnosticPath,
            latestInstallLogAvailable: installLogStatus.isAvailable,
            latestInstallLogStatus: installLogStatus.diagnosticCode,
            latestInstallLogRecoverySuggestion: installLogStatus.recoverySuggestion,
            signingSummary: includeSigningSummary ? signingSummary(for: appURL) : "未检查",
            hotKeyFailures: hotKeyFailures,
            activeModel: active,
            providerCount: settings.providers.count,
            enabledProviderCount: requestReadiness.enabledProviderCount,
            requestReadyProviderCount: requestReadiness.readyProviderCount,
            activeProviderRequestReady: requestReadiness.activeProviderReady,
            activeProviderRequestStatus: requestReadiness.activeProviderStatus,
            activeProviderRequestStatusText: requestReadiness.activeProviderStatusText,
            activeProviderRequestRecoverySuggestion: requestReadiness.activeProviderRecoverySuggestion,
            unavailableRequestReasonSummary: requestReadiness.unavailableReasonSummary,
            unavailableRequestRecoverySummary: requestReadiness.unavailableRecoverySummary,
            recentAIRequestStatus: recentAIRequestStatus,
            apiKeyConfiguredProviderCount: apiKeyHealth.configuredProviderCount,
            enabledProviderMissingAPIKeyCount: apiKeyHealth.enabledProviderMissingCount,
            secretStoreStatus: secretStoreStatus,
            textCaptureStatus: textCaptureStatus,
            writeBackStatus: writeBackStatus,
            privacyPreviewEnabled: settings.privacyPreviewEnabled,
            redactionEnabled: settings.redactionEnabled,
            redactionRuleCount: settings.redactionRules.count,
            invalidRedactionRuleCount: invalidRedactionRules,
            historyContentStorage: settings.historyContentStorage,
            historyStoreStatus: HistoryStore.latestStatusLine,
            iCloudSyncStatus: ICloudStatusSummary.make(settings: settings),
            contextProfileCount: contextSummary.profileCount,
            usableContextProfileCount: contextSummary.usableProfileCount,
            activeContextProfileName: contextSummary.activeProfileName.isEmpty ? "none" : contextSummary.activeProfileName,
            activeContextCharacterCount: contextSummary.activeContextCharacterCount,
            globalSystemPromptCharacterCount: contextSummary.globalSystemPromptCharacterCount,
            effectiveSystemPromptCharacterCount: contextSummary.effectiveSystemPromptCharacterCount,
            workModeTitle: settings.workModeStatusTitle,
            workModeDetail: settings.workModeStatusDetail
        )
    }

    package static func activeModelSummary(settings: AppSettings) -> String {
        let active = [settings.activeProvider?.name ?? "", settings.model]
            .filter { !$0.isEmpty }
            .joined(separator: " / ")
        return diagnosticValue(active, fallback: "未选择")
    }

    package static func requestReadiness(settings: AppSettings) -> PermissionRequestReadinessSummary {
        let enabledProviders = settings.providers.filter(\.isEnabled)
        let readinessByProvider = enabledProviders.map { AIRequestRouter.providerReadiness($0) }
        let readyProviderCount = readinessByProvider.filter(\.isReady).count
        let activeStatus = configuredActiveProviderReadiness(settings: settings)
        let unavailableReasonSummary = requestUnavailableReasonSummary(readinessByProvider)
        let unavailableRecoverySummary = requestUnavailableRecoverySummary(enabledProviders)
        return PermissionRequestReadinessSummary(
            enabledProviderCount: enabledProviders.count,
            readyProviderCount: readyProviderCount,
            activeProvider: activeStatus,
            unavailableReasonSummary: unavailableReasonSummary,
            unavailableRecoverySummary: unavailableRecoverySummary
        )
    }

    private static func configuredActiveProviderReadiness(settings: AppSettings) -> PermissionProviderRequestStatus {
        let configuredID = settings.activeProviderID.trimmingCharacters(in: .whitespacesAndNewlines)
        if let configuredProvider = settings.providers.first(where: { $0.id == configuredID }) {
            return PermissionProviderRequestStatus(provider: configuredProvider)
        }
        if !configuredID.isEmpty {
            return .missingConfiguredActiveProvider
        }
        if let effectiveProvider = settings.activeProvider {
            return PermissionProviderRequestStatus(provider: effectiveProvider)
        }
        return .missingActiveProvider
    }

    private static func requestUnavailableReasonSummary(_ readiness: [AIRequestRouter.ProviderReadiness]) -> String {
        let counts = Dictionary(grouping: readiness.filter { !$0.isReady }, by: \.diagnosticCode)
            .mapValues(\.count)
        guard !counts.isEmpty else { return "none" }
        return counts.keys.sorted().map { "\($0)=\(counts[$0] ?? 0)" }.joined(separator: "; ")
    }

    private static func requestUnavailableRecoverySummary(_ providers: [AIProvider]) -> String {
        let unavailable = providers.filter { !AIRequestRouter.providerReadiness($0).isReady }
        let grouped = Dictionary(grouping: unavailable, by: { AIRequestRouter.providerReadiness($0).diagnosticCode })
        guard !grouped.isEmpty else { return "none" }
        return grouped.keys.sorted().compactMap { code in
            guard let values = grouped[code],
                  let first = values.first else {
                return nil
            }
            let suggestion = AIRequestRouter.providerRecoverySuggestion(first)
            return "\(code)=\(values.count): \(suggestion)"
        }.joined(separator: "; ")
    }

    package static func apiKeyHealth(settings: AppSettings) -> PermissionAPIKeyHealthSummary {
        let configured = settings.providers.filter { provider in
            !provider.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }.count
        let missingEnabled = settings.providers.filter { provider in
            provider.isEnabled &&
            !provider.enabledModelNames.isEmpty &&
            provider.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }.count
        return PermissionAPIKeyHealthSummary(providerCount: settings.providers.count,
                                             configuredProviderCount: configured,
                                             enabledProviderMissingCount: missingEnabled)
    }

    package static func diagnosticValue(_ value: String,
                                fallback: String = "none",
                                limit: Int = 500) -> String {
        let sanitized = SensitiveTextSanitizer.sanitizedMessage(value, limit: limit)
        return sanitized.isEmpty ? fallback : sanitized
    }

    package static func diagnosticList(_ values: [String],
                               fallback: String = "none",
                               limit: Int = 800) -> String {
        let sanitized = values
            .map { diagnosticValue($0, fallback: "", limit: limit) }
            .filter { !$0.isEmpty }
            .joined(separator: "; ")
        return diagnosticValue(sanitized, fallback: fallback, limit: limit)
    }

    package static func diagnosticField(_ name: String, in summary: String) -> String? {
        let marker = "\(name)="
        guard let range = summary.range(of: marker) else { return nil }
        let remainder = summary[range.upperBound...]
        let value: Substring
        if let end = remainder.range(of: ", ") {
            value = remainder[..<end.lowerBound]
        } else {
            value = remainder[...]
        }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    package static func installDirectoryWritable(for appURL: URL) -> Bool {
        FileManager.default.isWritableFile(atPath: appURL.deletingLastPathComponent().path)
    }

    package static func shareablePath(_ path: String, homeDirectory: String = NSHomeDirectory()) -> String {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "none" }

        let home = homeDirectory
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if !home.isEmpty {
            let normalizedHome = "/" + home
            if trimmed == normalizedHome {
                return "~"
            }
            if trimmed.hasPrefix(normalizedHome + "/") {
                return "~" + trimmed.dropFirst(normalizedHome.count)
            }
        }

        let components = trimmed.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        guard components.count >= 3,
              components[0].isEmpty,
              components[1] == "Users",
              !components[2].isEmpty else {
            return trimmed
        }
        return "/" + (["Users", "[user]"] + Array(components.dropFirst(3))).joined(separator: "/")
    }

    package static func quarantineSummary(fromXattrOutput output: String?) -> String {
        guard let output else { return "absent" }
        let flattened = output
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !flattened.isEmpty else { return "absent" }
        let limited = flattened.count > 120 ? String(flattened.prefix(120)) + "..." : flattened
        return "present (\(limited))"
    }

    private static func quarantineSummary(for appURL: URL) -> String {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/xattr")
        proc.arguments = ["-p", "com.apple.quarantine", appURL.path]
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = Pipe()
        do {
            try proc.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            proc.waitUntilExit()
            guard proc.terminationStatus == 0 else {
                return quarantineSummary(fromXattrOutput: nil)
            }
            return quarantineSummary(fromXattrOutput: String(data: data, encoding: .utf8))
        } catch {
            return "unknown: \(SensitiveTextSanitizer.sanitizedMessage(error.localizedDescription))"
        }
    }

    private static func signingSummary(for appURL: URL) -> String {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
        proc.arguments = ["-dv", "--verbose=4", appURL.path]
        let pipe = Pipe()
        proc.standardError = pipe
        proc.standardOutput = pipe
        do {
            try proc.run()
            // 先读完管道再等待退出,避免输出填满缓冲区时死锁
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            proc.waitUntilExit()
            let text = String(data: data, encoding: .utf8) ?? ""
            let requirement = text
                .split(separator: "\n")
                .map(String.init)
                .first { $0.hasPrefix("designated =>") }
                .map { String($0.dropFirst("designated =>".count)).trimmingCharacters(in: .whitespacesAndNewlines) }
            var lines = text
                .split(separator: "\n")
                .map(String.init)
                .filter { $0.hasPrefix("Authority=") || $0.hasPrefix("TeamIdentifier=") || $0.hasPrefix("CDHash=") }
            if let requirement {
                lines.append("Requirement=\(requirement)")
            }
            return lines.isEmpty ? "未获取到签名详情" : lines.joined(separator: ", ")
        } catch {
            return "签名检查失败: \(SensitiveTextSanitizer.sanitizedMessage(error.localizedDescription))"
        }
    }
}

package struct PermissionInstallLogStatus {
    package var diagnosticPath: String
    package var isAvailable: Bool
    package var diagnosticCode: String
    package var recoverySuggestion: String

    package static let noRecord = PermissionInstallLogStatus(
        diagnosticPath: "none",
        isAvailable: false,
        diagnosticCode: "no-record",
        recoverySuggestion: "暂无自动更新日志;如更新失败,请重新检查更新后再复制诊断"
    )

    package init(diagnosticPath: String,
                 isAvailable: Bool,
                 diagnosticCode: String,
                 recoverySuggestion: String) {
        self.diagnosticPath = diagnosticPath
        self.isAvailable = isAvailable
        self.diagnosticCode = diagnosticCode
        self.recoverySuggestion = recoverySuggestion
    }
}
