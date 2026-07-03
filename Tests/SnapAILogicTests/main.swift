import Foundation
import AppKit
import ApplicationServices
import Carbon.HIToolbox

var failures: [String] = []

func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() {
        failures.append(message)
    }
}


func testPermissionDiagnosticsFormatting() {
    expect(PermissionHealthSnapshot.quarantineSummary(fromXattrOutput: nil) == "absent",
           "reports missing quarantine attribute")
    expect(PermissionHealthSnapshot.quarantineSummary(fromXattrOutput: "\n") == "absent",
           "treats empty quarantine output as absent")
    let quarantine = PermissionHealthSnapshot.quarantineSummary(fromXattrOutput: "0081;65f00000;Safari;")
    expect(quarantine == "present (0081;65f00000;Safari;)", "formats present quarantine attribute")
    expect(PermissionHealthSnapshot.shareablePath("/Users/alice/Applications/SnapAI.app",
                                                  homeDirectory: "/Users/alice") == "~/Applications/SnapAI.app",
           "collapses current home directory paths in shareable diagnostics")
    expect(PermissionHealthSnapshot.shareablePath("/Users/bob/Applications/SnapAI.app",
                                                  homeDirectory: "/Users/alice") == "/Users/[user]/Applications/SnapAI.app",
           "redacts other user directory names in shareable diagnostics")
    expect(PermissionHealthSnapshot.shareablePath("/Applications/SnapAI.app",
                                                  homeDirectory: "/Users/alice") == "/Applications/SnapAI.app",
           "keeps system application paths readable in shareable diagnostics")
    expect(PermissionHealthSnapshot.shareablePath("  ",
                                                  homeDirectory: "/Users/alice") == "none",
           "normalizes blank paths in shareable diagnostics")

    let snapshot = PermissionHealthSnapshot(appVersion: "1.2.0",
                                            macOSVersion: "macOS 14",
                                            bundleID: "com.snapai.app",
                                            installPath: "/Users/bob/Applications/SnapAI.app",
                                            accessibilityGranted: true,
                                            screenCaptureGranted: false,
                                            launchAtLogin: true,
                                            showDockIcon: false,
                                            installDirectoryWritable: true,
                                            quarantineStatus: "absent",
                                            latestInstallLogPath: "/Users/bob/Library/Logs/snapai-install.log",
                                            latestInstallLogAvailable: true,
                                            latestInstallLogStatus: "available",
                                            latestInstallLogRecoverySuggestion: "可通过命令面板或权限健康中心显示安装日志",
                                            signingSummary: "CDHash=abc",
                                            hotKeyFailures: ["⌥A failed"],
                                            activeModel: "OpenAI / gpt-4o-mini",
                                            providerCount: 2,
                                            enabledProviderCount: 2,
                                            requestReadyProviderCount: 1,
                                            activeProviderRequestReady: true,
                                            activeProviderRequestStatus: "ready",
                                            activeProviderRequestStatusText: "可请求",
                                            activeProviderRequestRecoverySuggestion: "无需处理",
                                            unavailableRequestReasonSummary: "missing-api-key=1",
                                            unavailableRequestRecoverySummary: "missing-api-key=1: 在 AI 设置中重新填写 API Key",
                                            apiKeyConfiguredProviderCount: 1,
                                            enabledProviderMissingAPIKeyCount: 1,
                                            textCaptureStatus: "state=no-selection, accessibility=missing, preferAX=yes, frontmostApp=Pages, capturedChars=0, recovery=授予辅助功能权限后重试; 也可打开快捷提问",
                                            writeBackStatus: "state=available",
                                            privacyPreviewEnabled: true,
                                            redactionEnabled: true,
                                            redactionRuleCount: 3,
                                            invalidRedactionRuleCount: 1,
                                            historyContentStorage: .metadataOnly,
                                            contextProfileCount: 3,
                                            usableContextProfileCount: 1,
                                            activeContextProfileName: "项目 A",
                                            activeContextCharacterCount: 42,
                                            globalSystemPromptCharacterCount: 18,
                                            effectiveSystemPromptCharacterCount: 96,
                                            workModeTitle: "隐私模式",
                                            workModeDetail: "发送前确认、本地脱敏,历史仅保存元信息。")
    let diagnostics = snapshot.diagnosticText
    expect(diagnostics.contains("Install Path: /Users/[user]/Applications/SnapAI.app"), "redacts user name in install path")
    expect(diagnostics.contains("Install Directory Writable: yes"), "includes install directory writability")
    expect(diagnostics.contains("Quarantine: absent"), "includes quarantine status")
    expect(diagnostics.contains("Latest Install Log: /Users/[user]/Library/Logs/snapai-install.log"), "redacts user name in latest install log path")
    expect(diagnostics.contains("Latest Install Log Status: available"), "includes latest install log status")
    expect(diagnostics.contains("Latest Install Log Recovery: 可通过命令面板或权限健康中心显示安装日志"),
           "includes latest install log recovery suggestion")
    expect(diagnostics.contains("Latest Install Log Available: yes"), "includes latest install log availability")
    expect(!diagnostics.contains("/Users/bob"), "permission diagnostics does not expose user home directory names")
    expect(diagnostics.contains("Work Mode: 隐私模式"), "includes current work mode")
    expect(diagnostics.contains("Work Mode Detail: 发送前确认、本地脱敏,历史仅保存元信息。"),
           "includes current work mode detail")
    expect(diagnostics.contains("Enabled Providers: 2"), "includes enabled provider count")
    expect(diagnostics.contains("Request Ready Providers: 1/2"), "includes request-ready provider count")
    expect(diagnostics.contains("Active Provider Request Ready: yes"), "includes active provider request readiness")
    expect(diagnostics.contains("Active Provider Request Status: ready"), "includes active provider request status")
    expect(diagnostics.contains("Active Provider Request Recovery: 无需处理"), "includes active provider request recovery")
    expect(diagnostics.contains("Unavailable Request Reasons: missing-api-key=1"), "includes unavailable request reason summary")
    expect(diagnostics.contains("Unavailable Request Recovery: missing-api-key=1: 在 AI 设置中重新填写 API Key"),
           "includes unavailable request recovery summary")
    expect(diagnostics.contains("API Keys: 1/2 configured; enabled missing 1"), "includes keychain api key health counts")
    expect(diagnostics.contains("Text Capture: state=no-selection, accessibility=missing, preferAX=yes, frontmostApp=Pages, capturedChars=0"),
           "includes recent text capture status")
    expect(diagnostics.contains("Privacy Preview: enabled"), "includes privacy preview state")
    expect(diagnostics.contains("Local Redaction: enabled"), "includes local redaction state")
    expect(diagnostics.contains("Redaction Rules: 3 (invalid 1)"), "includes redaction rule health")
    expect(diagnostics.contains("History Content Storage: 仅元信息"), "includes history content storage mode")
    expect(diagnostics.contains("Context Profiles: 3 (usable 1)"), "includes context profile health")
    expect(diagnostics.contains("Active Context: set"), "reports active context presence")
    expect(diagnostics.contains("Active Context Name Characters: 4"), "reports active context name length")
    expect(diagnostics.contains("Active Context Characters: 42"), "includes active context length")
    expect(diagnostics.contains("Global System Prompt Characters: 18"), "includes base system prompt length")
    expect(diagnostics.contains("Effective System Prompt Characters: 96"), "includes effective system prompt length")
    expect(!diagnostics.contains("项目 A"), "permission diagnostics does not expose context profile name")
    expect(!diagnostics.contains("术语: SnapAI"), "permission diagnostics does not expose context content")
    expect(!diagnostics.contains("基础提示"), "permission diagnostics does not expose system prompt content")
    expect(diagnostics.contains("HotKey Failures: ⌥A failed"), "includes hotkey failures")
    expect(diagnostics.contains("Recovery Suggestion Count: 6"),
           "full permission diagnostics include recovery suggestion count")
    expect(diagnostics.contains("Recovery Suggestion Status: 6 条建议"),
           "full permission diagnostics include recovery suggestion status")
    expect(diagnostics.contains("Recovery Suggestions: 屏幕录制: 在系统设置中允许 SnapAI 使用屏幕录制,然后重试截图提问"),
           "full permission diagnostics include recovery suggestions")
    expect(diagnostics.contains("API Key: 在 AI 设置中补齐启用供应商的 API Key"),
           "full permission diagnostics include api key recovery suggestion")
    expect(diagnostics.contains("取词: 授予辅助功能权限后重试; 也可打开快捷提问"),
           "full permission diagnostics include text capture recovery suggestion")

    let brief = snapshot.briefDiagnosticText
    expect(brief.contains("SnapAI Diagnostics Summary"), "brief permission diagnostics has a distinct heading")
    expect(brief.contains("Install Path: /Users/[user]/Applications/SnapAI.app"),
           "brief permission diagnostics redacts user name in install path")
    expect(brief.contains("Latest Install Log Status: available"),
           "brief permission diagnostics includes latest install log status without path")
    expect(!brief.contains("Latest Install Log Recovery:"),
           "brief permission diagnostics omits verbose install log recovery details")
    expect(brief.contains("AI Request: 可请求 1/2 个启用供应商"),
           "brief permission diagnostics includes request readiness summary")
    expect(brief.contains("API Key Health: 1 个启用供应商缺少 API Key"),
           "brief permission diagnostics includes api key health summary")
    expect(brief.contains("Text Capture: state=no-selection"),
           "brief permission diagnostics includes text capture status")
    expect(brief.contains("Work Mode: 隐私模式 - 发送前确认、本地脱敏,历史仅保存元信息。"),
           "brief permission diagnostics includes work mode summary")
    expect(brief.contains("Privacy: preview enabled, redaction enabled, invalid rules 1/3"),
           "brief permission diagnostics includes privacy summary")
    expect(brief.contains("Context: 1/3 usable; active set; effective prompt 96 chars"),
           "brief permission diagnostics includes safe context counts")
    expect(brief.contains("Recovery Suggestion Count: 6"),
           "brief permission diagnostics include recovery suggestion count")
    expect(brief.contains("Recovery Suggestion Status: 6 条建议"),
           "brief permission diagnostics include recovery suggestion status")
    expect(brief.contains("Recovery Suggestions: 屏幕录制: 在系统设置中允许 SnapAI 使用屏幕录制,然后重试截图提问"),
           "brief permission diagnostics include recovery suggestions")
    expect(brief.contains("API Key: 在 AI 设置中补齐启用供应商的 API Key"),
           "brief permission diagnostics include api key recovery suggestion")
    expect(brief.contains("取词: 授予辅助功能权限后重试; 也可打开快捷提问"),
           "brief permission diagnostics include text capture recovery suggestion")
    expect(!brief.contains("Latest Install Log:"),
           "brief permission diagnostics omits verbose install log details")
    expect(!brief.contains("项目 A"),
           "brief permission diagnostics does not expose context profile names")
    expect(brief.count < diagnostics.count,
           "brief permission diagnostics is shorter than full diagnostics")

    expect(PermissionHealthSnapshot.diagnosticField("recovery", in: snapshot.textCaptureStatus) == "授予辅助功能权限后重试; 也可打开快捷提问",
           "permission diagnostics can extract recovery guidance from structured status summaries")
    let recoverySuggestions = snapshot.recoverySuggestions
    expect(snapshot.recoverySuggestionCount == 6,
           "permission health snapshot exposes recovery suggestion count")
    expect(snapshot.recoverySuggestionStatusLine == "6 条建议",
           "permission health snapshot exposes compact recovery suggestion status")
    expect(recoverySuggestions.contains(PermissionHealthRecoverySuggestion(title: "屏幕录制",
                                                                           detail: "在系统设置中允许 SnapAI 使用屏幕录制,然后重试截图提问")),
           "permission health suggestions include screen recording recovery")
    expect(recoverySuggestions.contains(PermissionHealthRecoverySuggestion(title: "API Key",
                                                                           detail: "在 AI 设置中补齐启用供应商的 API Key")),
           "permission health suggestions include api key recovery")
    expect(recoverySuggestions.contains(PermissionHealthRecoverySuggestion(title: "备用供应商",
                                                                           detail: "missing-api-key=1: 在 AI 设置中重新填写 API Key")),
           "permission health suggestions include fallback provider recovery")
    expect(recoverySuggestions.contains(PermissionHealthRecoverySuggestion(title: "取词",
                                                                           detail: "授予辅助功能权限后重试; 也可打开快捷提问")),
           "permission health suggestions surface recent text capture recovery")
    let suggestionText = recoverySuggestions.map { "\($0.title): \($0.detail)" }.joined(separator: "\n")
    expect(!suggestionText.contains("/Users/bob"),
           "permission health suggestions do not expose user paths")
    expect(!suggestionText.contains("sk-live-secret-value-1234567890"),
           "permission health suggestions do not expose api keys")
    let clipboardSuggestions = snapshot.recoverySuggestionClipboardText
    expect(clipboardSuggestions.hasPrefix("SnapAI 修复建议\n"),
           "permission health suggestion clipboard text is self-describing")
    expect(clipboardSuggestions.contains("- 屏幕录制: 在系统设置中允许 SnapAI 使用屏幕录制,然后重试截图提问"),
           "permission health suggestion clipboard text uses readable bullet lines")
    expect(clipboardSuggestions.contains("- API Key: 在 AI 设置中补齐启用供应商的 API Key"),
           "permission health suggestion clipboard text includes api key recovery")
    expect(clipboardSuggestions.contains("- 取词: 授予辅助功能权限后重试; 也可打开快捷提问"),
           "permission health suggestion clipboard text includes text capture recovery")
    expect(!clipboardSuggestions.contains("/Users/bob"),
           "permission health suggestion clipboard text does not expose user paths")
    expect(!clipboardSuggestions.contains("sk-live-secret-value-1234567890"),
           "permission health suggestion clipboard text does not expose api keys")
    let healthySnapshot = PermissionHealthSnapshot(appVersion: "1.2.0",
                                                   macOSVersion: "macOS 14",
                                                   bundleID: "com.snapai.app",
                                                   installPath: "/Applications/SnapAI.app",
                                                   accessibilityGranted: true,
                                                   screenCaptureGranted: true,
                                                   launchAtLogin: true,
                                                   showDockIcon: true,
                                                   installDirectoryWritable: true,
                                                   quarantineStatus: "absent",
                                                   latestInstallLogPath: "none",
                                                   latestInstallLogAvailable: false,
                                                   latestInstallLogStatus: "no-record",
                                                   signingSummary: "CDHash=abc",
                                                   hotKeyFailures: [],
                                                   activeModel: "OpenAI / gpt-4o-mini",
                                                   providerCount: 1,
                                                   enabledProviderCount: 1,
                                                   requestReadyProviderCount: 1,
                                                   activeProviderRequestReady: true,
                                                   activeProviderRequestStatus: "ready",
                                                   activeProviderRequestStatusText: "可请求",
                                                   activeProviderRequestRecoverySuggestion: "无需处理",
                                                   unavailableRequestReasonSummary: "none",
                                                   unavailableRequestRecoverySummary: "none",
                                                   apiKeyConfiguredProviderCount: 1,
                                                   enabledProviderMissingAPIKeyCount: 0,
                                                   textCaptureStatus: "state=captured, recovery=无需处理",
                                                   writeBackStatus: "state=available",
                                                   privacyPreviewEnabled: true,
                                                   redactionEnabled: true,
                                                   redactionRuleCount: 1,
                                                   invalidRedactionRuleCount: 0)
    expect(healthySnapshot.recoverySuggestionClipboardText == "SnapAI 修复建议\n暂无需要处理的建议",
           "permission health suggestion clipboard text has a stable empty-state message")
    expect(healthySnapshot.recoverySuggestionCount == 0,
           "healthy permission health snapshot has no recovery suggestions")
    expect(healthySnapshot.recoverySuggestionStatusLine == "无需处理",
           "healthy permission health snapshot reports no required action")

    let recentAIRequestSnapshot = PermissionHealthSnapshot(appVersion: "1.2.0",
                                                           macOSVersion: "macOS 14",
                                                           bundleID: "com.snapai.app",
                                                           installPath: "/Applications/SnapAI.app",
                                                           accessibilityGranted: true,
                                                           screenCaptureGranted: true,
                                                           launchAtLogin: true,
                                                           showDockIcon: true,
                                                           installDirectoryWritable: true,
                                                           quarantineStatus: "absent",
                                                           latestInstallLogPath: "none",
                                                           latestInstallLogAvailable: false,
                                                           latestInstallLogStatus: "no-record",
                                                           signingSummary: "CDHash=abc",
                                                           hotKeyFailures: [],
                                                           activeModel: "LM Studio / local-chat",
                                                           providerCount: 2,
                                                           enabledProviderCount: 2,
                                                           requestReadyProviderCount: 2,
                                                           activeProviderRequestReady: true,
                                                           activeProviderRequestStatus: "ready",
                                                           activeProviderRequestStatusText: "可请求",
                                                           activeProviderRequestRecoverySuggestion: "无需处理",
                                                           unavailableRequestReasonSummary: "none",
                                                           unavailableRequestRecoverySummary: "none",
                                                           recentAIRequestStatus: "outcome=failed; fallback=cloud-confirmation-required, recoveryCode=fallback-cloud-confirmation-required, recovery=本地模型失败;如需改用云端模型请手动选择云端模型后重试, latest=LM Studio / local-chat -> 失败",
                                                           apiKeyConfiguredProviderCount: 2,
                                                           enabledProviderMissingAPIKeyCount: 0,
                                                           textCaptureStatus: "state=captured, recovery=无需处理",
                                                           writeBackStatus: "state=available",
                                                           privacyPreviewEnabled: true,
                                                           redactionEnabled: true,
                                                           redactionRuleCount: 1,
                                                           invalidRedactionRuleCount: 0)
    expect(recentAIRequestSnapshot.diagnosticText.contains("Recent AI Request: outcome=failed"),
           "permission diagnostics include the recent AI request status")
    expect(recentAIRequestSnapshot.briefDiagnosticText.contains("Recent AI Request: outcome=failed"),
           "brief permission diagnostics include the recent AI request status")
    expect(recentAIRequestSnapshot.recoverySuggestions == [
        PermissionHealthRecoverySuggestion(title: "最近 AI 请求",
                                           detail: "本地模型失败;如需改用云端模型请手动选择云端模型后重试")
    ], "permission health suggestions surface the recent AI request recovery")

    let pasteboardRecovery = "当前剪贴板内容过大或格式过多,为避免丢失用户剪贴板,已取消自动粘贴。请手动复制结果后粘贴。"
    let pasteboardProtectedSnapshot = PermissionHealthSnapshot(appVersion: "1.2.0",
                                                               macOSVersion: "macOS 14",
                                                               bundleID: "com.snapai.app",
                                                               installPath: "/Applications/SnapAI.app",
                                                               accessibilityGranted: true,
                                                               screenCaptureGranted: true,
                                                               launchAtLogin: true,
                                                               showDockIcon: true,
                                                               installDirectoryWritable: true,
                                                               quarantineStatus: "absent",
                                                               latestInstallLogPath: "none",
                                                               latestInstallLogAvailable: false,
                                                               latestInstallLogStatus: "no-record",
                                                               signingSummary: "CDHash=abc",
                                                               hotKeyFailures: [],
                                                               activeModel: "OpenAI / gpt-4o-mini",
                                                               providerCount: 1,
                                                               enabledProviderCount: 1,
                                                               requestReadyProviderCount: 1,
                                                               activeProviderRequestReady: true,
                                                               activeProviderRequestStatus: "ready",
                                                               activeProviderRequestStatusText: "可请求",
                                                               activeProviderRequestRecoverySuggestion: "无需处理",
                                                               unavailableRequestReasonSummary: "none",
                                                               unavailableRequestRecoverySummary: "none",
                                                               apiKeyConfiguredProviderCount: 1,
                                                               enabledProviderMissingAPIKeyCount: 0,
                                                               textCaptureStatus: "state=captured, recovery=无需处理",
                                                               writeBackStatus: "state=fallback-copied, operation=replace, copiedToPasteboard=no, recovery=\(pasteboardRecovery)",
                                                               privacyPreviewEnabled: true,
                                                               redactionEnabled: true,
                                                               redactionRuleCount: 1,
                                                               invalidRedactionRuleCount: 0)
    expect(pasteboardProtectedSnapshot.recoverySuggestionCount == 1,
           "permission health reports only the pasteboard-protected writeback suggestion")
    expect(pasteboardProtectedSnapshot.recoverySuggestions == [
        PermissionHealthRecoverySuggestion(title: "写回", detail: pasteboardRecovery)
    ], "permission health surfaces pasteboard safety recovery as the writeback suggestion")
    expect(pasteboardProtectedSnapshot.recoverySuggestionClipboardText.contains("- 写回: \(pasteboardRecovery)"),
           "permission recovery clipboard text includes pasteboard safety guidance")

    let lightweightSnapshot = PermissionHealthSnapshot.make(settings: AppSettings(),
                                                            hotKeyFailures: [],
                                                            textCaptureStatus: "none",
                                                            writeBackStatus: "none",
                                                            includeSigningSummary: false)
    expect(lightweightSnapshot.signingSummary == "未检查",
           "lightweight permission health snapshots skip signing inspection")
    expect(lightweightSnapshot.diagnosticText.contains("Signing: 未检查"),
           "full diagnostics expose skipped signing inspection state")
    expect(lightweightSnapshot.briefDiagnosticText.contains("Signing: 未检查"),
           "brief diagnostics expose skipped signing inspection state")

    expect(PermissionRecoveryCommand.title == "复制权限修复建议",
           "permission recovery command has a clear title")
    expect(PermissionRecoveryCommand.subtitle == "只复制权限健康中心当前建议",
           "permission recovery command explains the narrow copy scope")
    expect(PermissionRecoveryCommand.subtitle(statusLine: snapshot.recoverySuggestionStatusLine) == "当前: 6 条建议, 复制修复建议",
           "permission recovery command subtitle can include current suggestion status")
    expect(PermissionRecoveryCommand.subtitle(statusLine: healthySnapshot.recoverySuggestionStatusLine) == "当前: 无需处理, 复制修复建议",
           "permission recovery command subtitle can describe healthy state")
    expect(!PermissionRecoveryCommand.subtitle(statusLine: "路径 /Users/alice/token sk-live-secret-value-1234567890").contains("/Users/alice"),
           "permission recovery command subtitle redacts user paths")
    expect(!PermissionRecoveryCommand.subtitle(statusLine: "路径 /Users/alice/token sk-live-secret-value-1234567890").contains("sk-live-secret-value-1234567890"),
           "permission recovery command subtitle redacts secrets")
    expect(PermissionRecoveryCommand.systemImage == "lightbulb",
           "permission recovery command uses a suggestion icon")
    expect(CommandPaletteMatcher.matches(title: PermissionRecoveryCommand.title,
                                         subtitle: PermissionRecoveryCommand.subtitle,
                                         keywords: PermissionRecoveryCommand.keywords,
                                         query: "修复 建议"),
           "permission recovery command is searchable by Chinese recovery intent")
    expect(CommandPaletteMatcher.matches(title: PermissionRecoveryCommand.title,
                                         subtitle: PermissionRecoveryCommand.subtitle,
                                         keywords: PermissionRecoveryCommand.keywords,
                                         query: "recovery suggestions"),
           "permission recovery command is searchable by English recovery intent")

    let unsafeSnapshot = PermissionHealthSnapshot(appVersion: "1.2.0",
                                                  macOSVersion: "macOS 14",
                                                  bundleID: "com.snapai.app",
                                                  installPath: "/Users/alice/Applications/SnapAI.app",
                                                  accessibilityGranted: true,
                                                  screenCaptureGranted: true,
                                                  launchAtLogin: false,
                                                  showDockIcon: true,
                                                  installDirectoryWritable: true,
                                                  quarantineStatus: "0081;\norigin=/Users/alice/Downloads/SnapAI.zip",
                                                  latestInstallLogPath: "/Users/alice/Library/Logs/snapai-install.log",
                                                  latestInstallLogAvailable: true,
                                                  signingSummary: "Authority=Developer\nRequirement=/Users/alice/cert\nAuthorization: Bearer sk-live-secret-value-1234567890",
                                                  hotKeyFailures: ["动作 sk-live-secret-value-1234567890\n注册失败"],
                                                  activeModel: "OpenAI / gpt-4o-mini\napi_key=sk-live-secret-value-1234567890 / /Users/alice/model",
                                                  providerCount: 1,
                                                  textCaptureStatus: "frontmostApp=/Users/alice/Secret.app\nkey=sk-live-secret-value-1234567890",
                                                  writeBackStatus: "target=/Users/alice/Documents/input.txt\nsecret=sk-live-secret-value-1234567890")
    let unsafeDiagnostics = unsafeSnapshot.diagnosticText
    let unsafeBrief = unsafeSnapshot.briefDiagnosticText
    expect(!unsafeDiagnostics.contains("sk-live-secret-value-1234567890"),
           "permission diagnostics redacts secrets from free-form diagnostic fields")
    expect(!unsafeDiagnostics.contains("/Users/alice"),
           "permission diagnostics redacts user paths from free-form diagnostic fields")
    expect(!unsafeDiagnostics.contains("api_key=sk-"),
           "permission diagnostics redacts api_key fragments")
    expect(unsafeDiagnostics.contains("/Users/[user]/Downloads/SnapAI.zip"),
           "permission diagnostics keeps useful redacted quarantine path suffixes")
    expect(unsafeDiagnostics.contains("Authorization: Bearer [REDACTED]"),
           "permission diagnostics keeps sanitized signing error context")
    expect(unsafeDiagnostics.contains("HotKey Failures: 动作 [REDACTED_KEY] 注册失败"),
           "permission diagnostics flattens and sanitizes hotkey failures")
    expect(!unsafeBrief.contains("sk-live-secret-value-1234567890"),
           "brief permission diagnostics redacts secrets from free-form diagnostic fields")
    expect(!unsafeBrief.contains("/Users/alice"),
           "brief permission diagnostics redacts user paths from free-form diagnostic fields")
    expect(unsafeBrief.contains("Authorization: Bearer [REDACTED]"),
           "brief permission diagnostics keeps sanitized signing error context")
    expect(unsafeBrief.contains("Recovery Suggestions:"),
           "brief permission diagnostics keeps actionable recovery suggestions")
    expect(!unsafeBrief.contains("sk-live-secret-value-1234567890"),
           "brief permission recovery suggestions redact secrets")
    expect(!unsafeBrief.contains("/Users/alice"),
           "brief permission recovery suggestions redact user paths")
    expect(!unsafeSnapshot.recoverySuggestionClipboardText.contains("sk-live-secret-value-1234567890"),
           "permission health suggestion clipboard text redacts unsafe secrets")
    expect(!unsafeSnapshot.recoverySuggestionClipboardText.contains("/Users/alice"),
           "permission health suggestion clipboard text redacts unsafe user paths")
}

func testPermissionDiagnosticsReportsAPIKeyHealth() {
    let settings = AppSettings()
    var ready = AIProvider(name: "Ready", apiProtocol: .openAI,
                           baseURL: "https://ready.test/v1",
                           apiKey: "sk-live-secret-value-1234567890",
                           models: [AIModelEntry(name: "ready-model", enabled: true)])
    ready.isEnabled = true
    var missing = AIProvider(name: "Missing", apiProtocol: .openAI,
                             baseURL: "https://missing.test/v1",
                             apiKey: " \n ",
                             models: [AIModelEntry(name: "missing-model", enabled: true)])
    missing.isEnabled = true
    var disabled = AIProvider(name: "Disabled", apiProtocol: .openAI,
                              baseURL: "https://disabled.test/v1",
                              apiKey: "",
                              models: [AIModelEntry(name: "disabled-model", enabled: true)])
    disabled.isEnabled = false
    var noEnabledModels = AIProvider(name: "No Models", apiProtocol: .openAI,
                                     baseURL: "https://nomodels.test/v1",
                                     apiKey: "",
                                     models: [AIModelEntry(name: "disabled-model", enabled: false)])
    noEnabledModels.isEnabled = true
    settings.providers = [ready, missing, disabled, noEnabledModels]

    let health = PermissionHealthSnapshot.apiKeyHealth(settings: settings)
    expect(health.configuredProviderCount == 1,
           "permission diagnostics counts providers with configured api keys")
    expect(health.enabledProviderMissingCount == 1,
           "permission diagnostics only flags enabled providers with enabled models and missing api keys")
    expect(health.statusLine == "1 个启用供应商缺少 API Key",
           "permission diagnostics builds api key health status text")
    expect(health.detailLine == "1/4 已配置 · 启用但缺失 1",
           "permission diagnostics builds api key health detail text")

    settings.providers = []
    let emptyHealth = PermissionHealthSnapshot.apiKeyHealth(settings: settings)
    expect(emptyHealth.statusLine == "尚未配置供应商",
           "permission diagnostics explains missing provider configuration in api key health")
    expect(emptyHealth.detailLine == "0/0 已配置 · 启用但缺失 0",
           "permission diagnostics builds stable empty api key health detail text")

    ready.apiKey = "key"
    missing.apiKey = "key2"
    settings.providers = [ready, missing]
    let configuredHealth = PermissionHealthSnapshot.apiKeyHealth(settings: settings)
    expect(configuredHealth.statusLine == "2/2 个供应商已配置",
           "permission diagnostics reports all api keys configured")
    expect(configuredHealth.detailLine == "2/2 已配置 · 启用但缺失 0",
           "permission diagnostics reports all configured api key detail text")
}

func testPermissionDiagnosticsReportsWorkMode() {
    let settings = AppSettings()
    settings.applyWorkMode(.privacy)

    let privacySnapshot = PermissionHealthSnapshot.make(settings: settings,
                                                        hotKeyFailures: [],
                                                        writeBackStatus: "none")
    expect(privacySnapshot.workModeTitle == "隐私模式",
           "permission diagnostics reports the matched work mode")
    expect(privacySnapshot.workModeDetail == WorkModePreset.privacy.summary,
           "permission diagnostics reports the matched work mode detail")
    expect(privacySnapshot.diagnosticText.contains("Work Mode: 隐私模式"),
           "full permission diagnostics includes matched work mode")
    expect(privacySnapshot.briefDiagnosticText.contains("Work Mode: 隐私模式"),
           "brief permission diagnostics includes matched work mode")

    settings.redactionEnabled = false
    let customSnapshot = PermissionHealthSnapshot.make(settings: settings,
                                                       hotKeyFailures: [],
                                                       writeBackStatus: "none")
    expect(customSnapshot.workModeTitle == "自定义模式",
           "permission diagnostics reports custom mode when behavior diverges from presets")
    expect(customSnapshot.workModeDetail.contains("偏离预设"),
           "permission diagnostics explains custom work mode mismatch")
}

func testPermissionDiagnosticsReportsRequestReadiness() {
    let settings = AppSettings()
    var ready = AIProvider(name: "Ready", apiProtocol: .openAI,
                           baseURL: "https://ready.test/v1",
                           apiKey: "key",
                           models: [AIModelEntry(name: "ready-model", enabled: true)])
    ready.id = "ready"
    ready.isEnabled = true
    var remoteHTTP = ready
    remoteHTTP.id = "remote-http"
    remoteHTTP.baseURL = "http://remote.example.test/v1"
    var missingKey = ready
    missingKey.id = "missing-key"
    missingKey.apiKey = ""
    var missingKeyAgain = ready
    missingKeyAgain.id = "missing-key-again"
    missingKeyAgain.apiKey = ""
    var disabled = ready
    disabled.id = "disabled"
    disabled.isEnabled = false
    settings.providers = [ready, remoteHTTP, missingKey, missingKeyAgain, disabled]
    settings.activeProviderID = ready.id
    settings.activeModel = "ready-model"

    var readiness = PermissionHealthSnapshot.requestReadiness(settings: settings)
    expect(readiness.enabledProviderCount == 4,
           "permission diagnostics counts enabled providers for request readiness")
    expect(readiness.readyProviderCount == 1,
           "permission diagnostics reuses router readiness for request-ready providers")
    expect(readiness.activeProviderReady,
           "permission diagnostics marks the active provider ready when it can request")
    expect(readiness.activeProvider == PermissionProviderRequestStatus(readiness: .ready),
           "permission diagnostics exposes structured active provider readiness")
    expect(readiness.activeProviderStatus == "ready",
           "permission diagnostics exposes the active provider readiness status")
    expect(readiness.unavailableReasonSummary == "missing-api-key=2; remote-http=1",
           "permission diagnostics summarizes unavailable provider reasons")
    expect(readiness.activeProviderRecoverySuggestion == "无需处理",
           "permission diagnostics exposes active provider recovery guidance")
    expect(readiness.unavailableRecoverySummary == "missing-api-key=2: 在 AI 设置中重新填写 API Key; remote-http=1: 远程端点请改用 HTTPS;HTTP 仅允许 localhost",
           "permission diagnostics summarizes recovery guidance in stable reason-code order")
    expect(readiness.statusLine == "可请求 1/4 个启用供应商",
           "permission diagnostics builds a compact request readiness status line")
    expect(readiness.detailLine == "1/4 可请求 · 当前可用 · missing-api-key=2: 在 AI 设置中重新填写 API Key; remote-http=1: 远程端点请改用 HTTPS;HTTP 仅允许 localhost",
           "permission diagnostics builds a detailed request readiness line")

    settings.activeProviderID = remoteHTTP.id
    settings.activeModel = "ready-model"
    readiness = PermissionHealthSnapshot.requestReadiness(settings: settings)
    expect(!readiness.activeProviderReady,
           "permission diagnostics marks the active provider unavailable when router readiness rejects it")
    expect(readiness.activeProviderStatus == "remote-http",
           "permission diagnostics reports why the active provider is unavailable")
    expect(readiness.activeProviderStatusText == "远程 HTTP 不安全",
           "permission diagnostics exposes localized active provider readiness text")
    expect(readiness.activeProviderRecoverySuggestion.contains("改用 HTTPS"),
           "permission diagnostics reports recovery guidance for the active provider")
    expect(readiness.statusLine == "可请求 1/4 个启用供应商 · 当前: 远程 HTTP 不安全",
           "permission diagnostics includes active provider issues in the compact status line")

    settings.activeProviderID = disabled.id
    settings.activeModel = "ready-model"
    readiness = PermissionHealthSnapshot.requestReadiness(settings: settings)
    expect(!readiness.activeProviderReady,
           "permission diagnostics does not hide a configured disabled active provider behind fallback")
    expect(readiness.activeProviderStatus == "disabled",
           "permission diagnostics reports configured disabled active providers")
    expect(readiness.activeProviderRecoverySuggestion.contains("启用该供应商"),
           "permission diagnostics suggests re-enabling configured disabled active providers")

    settings.activeProviderID = "missing-provider"
    readiness = PermissionHealthSnapshot.requestReadiness(settings: settings)
    expect(!readiness.activeProviderReady,
           "permission diagnostics does not hide a missing configured active provider behind fallback")
    expect(readiness.activeProviderStatus == "missing-active-provider",
           "permission diagnostics reports missing configured active providers")
    expect(readiness.activeProvider == .missingConfiguredActiveProvider,
           "permission diagnostics exposes structured missing configured active providers")
    expect(readiness.activeProviderStatusText == "当前供应商不存在",
           "permission diagnostics explains missing configured active provider ids")
    expect(readiness.activeProviderRecoverySuggestion.contains("重新选择供应商"),
           "permission diagnostics suggests reselecting missing configured active providers")

    let emptySettings = AppSettings()
    emptySettings.providers = []
    emptySettings.activeProviderID = ""
    emptySettings.activeModel = ""
    let emptyReadiness = PermissionHealthSnapshot.requestReadiness(settings: emptySettings)
    expect(emptyReadiness.statusLine == "没有启用供应商",
           "permission diagnostics explains when no providers are enabled")
    expect(emptyReadiness.detailLine == "0/0 可请求 · 当前: 未选择供应商 · 无异常",
           "permission diagnostics builds a stable empty request readiness detail line")
}


func snapAIURL(host: String, queryItems: [URLQueryItem] = [], path: String = "") -> URL {
    var components = URLComponents()
    components.scheme = "snapai"
    components.host = host
    components.path = path
    components.queryItems = queryItems.isEmpty ? nil : queryItems
    return components.url!
}


func testPermissionDiagnosticsUsesSafeActiveModelSummary() {
    let settings = AppSettings()
    var provider = AIProvider(name: "Primary", apiProtocol: .openAI,
                              baseURL: "https://primary.test/v1",
                              apiKey: "key",
                              models: [
                                AIModelEntry(name: "disabled-active", enabled: false),
                                AIModelEntry(name: "enabled-model", enabled: true)
                              ])
    provider.isEnabled = true
    settings.providers = [provider]
    settings.activeProviderID = provider.id
    settings.activeModel = "disabled-active"

    expect(PermissionHealthSnapshot.activeModelSummary(settings: settings) == "Primary / enabled-model",
           "permission diagnostics reports the safe active model")

    var unsafeProvider = provider
    unsafeProvider.name = "Primary\napi_key=sk-live-secret-value-1234567890 / /Users/alice/project"
    unsafeProvider.models = [AIModelEntry(name: "enabled-model\n/Users/alice/model", enabled: true)]
    settings.providers = [unsafeProvider]
    settings.activeProviderID = unsafeProvider.id
    settings.activeModel = "enabled-model\n/Users/alice/model"
    let unsafeSummary = PermissionHealthSnapshot.activeModelSummary(settings: settings)
    expect(!unsafeSummary.contains("sk-live-secret-value-1234567890"),
           "active model summary redacts secrets from provider names")
    expect(!unsafeSummary.contains("/Users/alice"),
           "active model summary redacts local paths from provider and model names")
    expect(!unsafeSummary.contains("\n"),
           "active model summary is single-line")
    expect(unsafeSummary.contains("[REDACTED]"),
           "active model summary keeps a redaction marker for sensitive fragments")
}


func testContextProfileEffectiveSystemPrompt() {
    let settings = AppSettings()
    let profile = ContextProfile(name: "项目 A", content: "术语: SnapAI = 菜单栏 AI 工具")
    settings.systemPrompt = "基础提示"
    settings.contextProfiles = [profile]
    settings.activeContextProfileID = profile.id
    expect(settings.effectiveSystemPrompt.contains("基础提示"), "keeps base system prompt")
    expect(settings.effectiveSystemPrompt.contains("项目 A"), "includes active context profile name")
    expect(settings.effectiveSystemPrompt.contains("术语"), "includes active context content")

    settings.contextProfiles[0].isEnabled = false
    expect(settings.effectiveSystemPrompt == "基础提示", "ignores disabled context profile")
    let baseOnlyMarkdown = settings.effectiveSystemPromptMarkdownExport
    expect(baseOnlyMarkdown.contains("# SnapAI 实际系统提示"), "effective system prompt markdown has a clear title")
    expect(baseOnlyMarkdown.contains("- 当前上下文包: 无"), "effective system prompt markdown reports missing context")
    expect(baseOnlyMarkdown.contains("基础提示"), "effective system prompt markdown exports base prompt")

    settings.contextProfiles[0].isEnabled = true
    let effectiveMarkdown = settings.effectiveSystemPromptMarkdownExport
    expect(effectiveMarkdown.contains("- 当前上下文包: 项目 A"), "effective system prompt markdown reports active context")
    expect(effectiveMarkdown.contains("当前上下文包: 项目 A"), "effective system prompt markdown includes rendered context block")
    expect(effectiveMarkdown.contains("术语: SnapAI = 菜单栏 AI 工具"), "effective system prompt markdown includes context content")

    let contextStatus = settings.contextStatusMarkdownExport
    expect(contextStatus.contains("# SnapAI 上下文状态"), "context status markdown has a clear title")
    expect(contextStatus.contains("- 上下文包总数: 1"), "context status markdown reports total profile count")
    expect(contextStatus.contains("- 可用上下文包: 1"), "context status markdown reports usable profile count")
    expect(contextStatus.contains("- 当前上下文包: 项目 A"), "context status markdown reports active profile name")
    expect(contextStatus.contains("- 当前上下文字符数: \(profile.content.count)"), "context status markdown reports active context length")
    expect(!contextStatus.contains("术语: SnapAI"), "context status markdown does not expose context content")
    expect(!contextStatus.contains("基础提示"), "context status markdown does not expose base system prompt content")

    let requestContext = AIRequestContextDiagnostic.make(settings: settings)
    expect(requestContext.contextProfileCount == 1, "request context diagnostics reports total profile count")
    expect(requestContext.usableContextProfileCount == 1, "request context diagnostics reports usable profile count")
    expect(requestContext.activeContextCharacterCount == profile.content.count,
           "request context diagnostics reports active context length")
    expect(requestContext.globalSystemPromptCharacterCount == "基础提示".count,
           "request context diagnostics reports base system prompt length")
    expect(requestContext.effectiveSystemPromptCharacterCount == settings.effectiveSystemPrompt.count,
           "request context diagnostics reports effective system prompt length")
    let requestContextSummary = requestContext.summaryLines.joined(separator: "\n")
    expect(requestContextSummary.contains("Active Context: set"), "request context diagnostics reports active context presence")
    expect(!requestContextSummary.contains("项目 A"), "request context diagnostics does not expose context profile name")
    expect(!requestContextSummary.contains("术语: SnapAI"), "request context diagnostics does not expose context content")
    expect(!requestContextSummary.contains("基础提示"), "request context diagnostics does not expose system prompt content")

    let markdown = profile.markdownExport(isActive: true)
    expect(markdown.contains("# 项目 A"), "context profile markdown exports the profile name")
    expect(markdown.contains("- 状态: 使用中"), "context profile markdown exports active state")
    expect(markdown.contains("- 启用: 是"), "context profile markdown exports enabled state")
    expect(markdown.contains("- 字符数: \(profile.content.count)"), "context profile markdown exports content length")
    expect(markdown.contains("## 内容\n\n术语: SnapAI = 菜单栏 AI 工具"), "context profile markdown exports content")

    let blank = ContextProfile(name: " \n ", content: " \n ", isEnabled: false)
    expect(blank.markdownExport(isActive: false).contains("# 未命名上下文"), "blank context profile markdown uses fallback name")
    expect(blank.markdownExport(isActive: false).contains("无内容"), "blank context profile markdown explains empty content")

    let unsafeProfile = ContextProfile(name: "项目\n# 注入|`名称`",
                                       content: "术语\n保留正文换行")
    settings.contextProfiles = [unsafeProfile]
    settings.activeContextProfileID = unsafeProfile.id
    let unsafePrompt = settings.effectiveSystemPrompt
    expect(unsafePrompt.contains("当前上下文包: 项目 # 注入/'名称'"),
           "effective system prompt keeps context profile name single-line")
    expect(!unsafePrompt.contains("项目\n# 注入"), "effective system prompt does not allow context name newline injection")
    expect(unsafePrompt.contains("术语\n保留正文换行"), "effective system prompt preserves context content newlines")

    let unsafeProfileMarkdown = unsafeProfile.markdownExport(isActive: true)
    expect(unsafeProfileMarkdown.contains("# 项目 # 注入/'名称'"),
           "context profile markdown keeps unsafe names single-line")
    expect(!unsafeProfileMarkdown.contains("项目\n# 注入"),
           "context profile markdown does not allow heading newline injection")
    expect(unsafeProfileMarkdown.contains("## 内容\n\n术语\n保留正文换行"),
           "context profile markdown preserves content newlines")

    let unsafeEffectiveMarkdown = settings.effectiveSystemPromptMarkdownExport
    expect(unsafeEffectiveMarkdown.contains("- 当前上下文包: 项目 # 注入/'名称'"),
           "effective prompt markdown keeps active context name single-line")
    let unsafeStatusMarkdown = settings.contextStatusMarkdownExport
    expect(unsafeStatusMarkdown.contains("- 当前上下文包: 项目 # 注入/'名称'"),
           "context status markdown keeps active context name single-line")
}


func legacyDefaultRedactionRulesForTests() -> [PrivacyRedactionRule] {
    [
        PrivacyRedactionRule(
            name: "邮箱地址",
            pattern: #"[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}"#,
            replacement: "[邮箱]"
        ),
        PrivacyRedactionRule(
            name: "手机号",
            pattern: #"(?<!\d)(?:\+?86[- ]?)?1[3-9]\d{9}(?!\d)"#,
            replacement: "[手机号]"
        ),
        PrivacyRedactionRule(
            name: "疑似 API Key",
            pattern: #"(?i)\b(?:sk(?:-[a-z0-9]+)+|gh[pousr]_[a-z0-9_]{20,}|xox[baprs]-[a-z0-9-]{20,}|(?:api[_-]?key|token|secret)[_:\-= ]+[a-z0-9][a-z0-9._-]{11,})\b"#,
            replacement: "[密钥]"
        )
    ]
}


testVersionNormalizationAndCompare()
testReleaseTagParsing()
testReleaseAssetSelectionUsesExactVersionedNames()
testGitHubAssetDigestValidation()
testChecksumSourceRequiresDigestOrManifest()
testReleaseManifestValidation()
testReleaseManifestSigningAndSignatureValidation()
testLatestInstallLogURLValidation()
testInstallLogCommandSubtitleRedactsUserPaths()
testDesignatedRequirementParsing()
testPermissionDiagnosticsFormatting()
testPermissionDiagnosticsReportsAPIKeyHealth()
testPermissionDiagnosticsReportsWorkMode()
testPermissionDiagnosticsReportsRequestReadiness()
testBaseURLNormalization()
testAIClientEffectiveRuntimeParametersAreSanitized()
testAIClientStreamErrorParsing()
testAIClientResponseErrorBodySanitization()
testPromptRender()
testActionPipelineDiagnostic()
testAIActionSanitizesImportedConfiguration()
testActionTemplateLibraryBuiltInsAreShareable()
testActionTemplateLibraryExportsPortableBundle()
testActionTemplateLibraryImportsAndInstallsSafely()
testDefaultPolishActionConfirmsReplacement()
testTextReplacementSelectionDelay()
testMenuCoordinatorBuildsModelSwitchMenu()
testScreenCaptureTemporaryFileUsesUniqueUnpredictablePath()
testScreenCapturePermissionPreflightAndRecoveryMessage()
testScreenCaptureFailureDiagnosticsAreShareableAndPathFree()
testScreenCaptureFailureDiagnosticsDescribeOutputProblems()
testWriteBackUndoRecordAvailability()
testWriteBackFallbackDiagnosticSummarizesFailureWithoutContent()
testWriteBackUndoFallbackDiagnosticSummarizesFailureWithoutContent()
testWriteBackCommandFactoryReflectsUndoAvailability()
testCapturedTextPreservesSelectionWhitespace()
testTextWriteBackAppendPayloadContract()
testTextCaptureExtractsSelectedSubstringFromAXValueRange()
testServicePasteboardTextAcceptsCommonPlainTextTypes()
testTextCaptureTargetActivationGuards()
testCaptureTargetResolverUsesRecentExternalAppWhenSnapAIIsFrontmost()
testTextCaptureRecoveryGuidePointsToActionablePermissionHelp()
testTextCaptureDiagnosticSummarizesStateWithoutContent()
testSelectionSourceContextClassifiesAppsSafely()
testSystemPrivacySettingsBuildsStablePaneURLs()
testPasteboardRestoreDecisionProtectsUserChanges()
testTextCaptureValidatesAXCoreFoundationTypes()
testHotKeyConflictDetection()
testHotKeyRecorderTextDescribesRecordingAndReservedShortcuts()
testHotKeyCoordinatorDetectsConflictsAndRegistrationFailures()
testCommandPaletteMatchesMultipleTerms()
testCommandPaletteRanksMatchesByRelevance()
testCommandPaletteSearchesShortcutTextAliases()
testCommandIdentifierSlugAndUniqueness()
testModelSwitchCommandFactoryFiltersAndMarksCurrentModel()
testModelSwitchCommandIDsAreStableSlugs()
testActionCommandFactoryFiltersAndFormatsActions()
testActionCommandFactoryPrioritizesFrequentActions()
testActionCommandIDsAreStableSlugs()
testAutomationActionSelectionNormalizesQueries()
testAutomationSettingsSectionSelectionNormalizesQueries()
testAutomationRouterParsesURLsAndSettingsSections()
testAutomationURLCommandParsing()
testAutomationWriteBackPolicyRequiresCapturedSelection()
testAutomationRunOptionsApplyToActionWithoutChangingSettings()
testAutomationModelSelectionResolvesEnabledModelsOnly()
testAutomationContextSelectionRequiresEnabledNonEmptyProfile()
testAutomationContextClearRestoresBasePrompt()
testAutomationRoutingPreferenceSelectionResolvesAliases()
testAutomationWorkModeSelectionResolvesAliases()
testAutomationTypewriterSpeedSelectionResolvesAliases()
testAIRouterIncludesFallbackCandidates()
testAIRequestDiagnosticsSummary()
testAIRequestPayloadDiagnosticEstimatesRequestShape()
testAIRequestPayloadDiagnosticReportsContextFit()
testAIRequestDiagnosticsReportsCandidateImageFit()
testAIRequestDiagnosticsReportsCandidateReasoningFit()
testAIRequestDiagnosticsReportsCandidateFitIssueSummary()
testAIRequestDiagnosticsReportsRecommendedRouteSafely()
testAIRequestDiagnosticsReportsRecommendedRouteIssues()
testAIRequestDiagnosticsReportsFirstRequestRouteAfterSkips()
testAIRequestDiagnosticsBuildsVisibleRouteExplanation()
testAIRequestDiagnosticsBuildsRouteDisplayNotesWithIssues()
testAIRequestDiagnosticsAnnotatesAttemptsWithRouteIssues()
testAIRequestDiagnosticsSkipsHardIncompatibleRoutes()
testAIRequestFallbackDecisionExplainsSkippedFallbacks()
testFallbackRunnerSwitchesAfterThinkingOnlyFailureAndProtectsVisiblePartialOutput()
testVisibleErrorRecoverySuggestionText()
testAIRequestDiagnosticsClassifiesCommonErrorRecoverySuggestions()
testNoCandidateRouteDiagnosticsExplainProviderReadiness()
testAIRequestAttemptDiagnosticFormatsDurations()
testSensitiveTextSanitizerRedactsSensitiveErrorFragments()
testAIRequestDiagnosticsUsesSensitiveTextSanitizer()
testAIRequestDiagnosticsSanitizesRouteMetadata()
testAIRequestRouteDisplayNotesAreSanitized()
testAIRouterSkipsDisabledActionOverrideModel()
testAIRouterSkipsDisabledActiveModel()
testAIRouterScopedSettingsRequiresEnabledRouteModel()
testAIRouterProviderRequestReadiness()
testAIRouterFallbackSkipsProvidersThatCannotRequest()
testAIRouterKeepsActiveProviderWhenNotRequestReady()
testSettingsModelClearsWhenActiveProviderHasNoEnabledModels()
testPermissionDiagnosticsUsesSafeActiveModelSummary()
testModelCapabilityInference()
testAIRouterUsesCapabilityReasonForCodeAction()
testAIRouterUsesFullRequestSizeForLongContextRouting()
testAIRouterDemotesOverLimitModelsWhenAutoRouting()
testAIRouterPromotesVisionModelForImageRequests()
testAIRouterPromotesReasoningModelForThinkingActions()
testAIRouterUsesRoutingPreferenceForFallbackOrder()
testAIRouterUsesRoutingPreferenceWhenOnlyFallbackIsEnabled()
testAIRouterPrefersLocalModelRoutesInPrivacyMode()
testAIRouterUsesStableConfiguredOrderForEqualScores()
testRoutingMetricsRecordPerformanceAndFailures()
testAIRouterUsesRoutingMetricsForFallbackOrder()
testPrivacyRedactionDefaults()
testPrivacyRedactionDefaultSampleDemonstratesSensitiveFormats()
testPrivacyRedactionPreviewReportsInvalidRules()
testPrivacyRedactionGuardsRiskyRulesAndLongReplacement()
testPrivacySubmissionPreviewExplainsFinalPayload()
testPrivacySubmissionPreviewReportsRiskWhenRedactionDisabled()
testPrivacySubmissionPreviewRequirementProtectsHighRiskPayloads()
testPrivacySubmissionPreviewReportsInvalidRules()
testPrivacyHistoryTagExportPriorityIncludesMetadataOnly()
testAppSettingsAddHistoryPersistsPrivacyTags()
testAppSettingsAddHistoryCanStoreMetadataOnly()
testAppSettingsAddHistoryCanOverrideStorageForOneEntry()
testAppSettingsAddHistoryTruncatesLargeContentAndTags()
testAppSettingsUpdateHistoryTagsSanitizesManualTags()
testSettingsDecodeSanitizesStoredHistory()
testSettingsClampsStoredPanelDimensions()
testPrivacySubmissionPreviewCanRepresentFollowUpPayload()
testPrivacySubmissionPreviewRendersSourceResendPayload()
testTextDiffSummary()
testTextDiffCapsLargePreviewRows()
testContextProfileEffectiveSystemPrompt()
testSettingsCodablePreservesRoutingAndHistoryPreferences()
testSettingsExportConfigurationOmitsSecretsAndHistory()
testSettingsSanitizesStoredActionUsageCounts()
testSettingsRecordActionUsageUsesSafeBounds()
testSettingsImportProvidersIgnorePlaintextKeys()
testSettingsImportProvidersSanitizeRuntimeBoundaries()
testSettingsImportRemapsActionProviderOverridesAfterProviderIDRepair()
testSettingsDecodeSanitizesStoredProviders()
testSettingsDecodeSanitizesStoredRedactionRules()
testSettingsLoadPersistsMigratedLegacyRedactionRules()
testSettingsImportSanitizesUnsafeConfiguration()
testSettingsDecodeSanitizesStoredContextProfiles()
testSettingsDecodeSanitizesStoredPrompts()
testSettingsDecodeDefaultsRoutingPreference()
testSettingsDecodeDefaultsActiveProviderToFirstProvider()
testSettingsNormalizeActiveSkipsDisabledProviderAndModel()
testSettingsNormalizeActiveClearsWhenNoEnabledProviderExists()
testCloudSettingsPayloadPreservesRoutingPreferenceAndNormalizesModel()
testCloudSettingsPayloadRemapsActiveProviderAfterProviderIDRepair()
testCloudSettingsPayloadDecodeRemapsActionsAfterProviderIDRepair()
testWorkModePresetsApplyCoherentSettings()
testWorkModeCommandFactoryReflectsCurrentState()
testSettingsToggleCommandReflectsCurrentState()
testSettingsToggleCommandResolvesAliasesAndSetsState()
testSettingsWindowPinCommandReflectsCurrentState()
testResultPinCommandReflectsCurrentState()
testDisplayBehaviorCommandFactoryReflectsCurrentState()
testRoutingContextCommandFactoryReflectsCurrentState()
testResultDiagnosticsCommandIsSearchable()
testResultRecoveryCommandPointsToAISettings()
testFollowUpInputBehaviorSupportsMultilineDrafts()
testRequestSessionBuildsInitialMessagesAndCounts()
testStreamingAccumulatorSeparatesThinkingAndResetsForFallback()
testResultRouteStatusTextBuildsCompactPrimaryAndDetails()
testFollowUpHistoryStoreNavigatesRecentPromptsSafely()
testResultCommandFactoryHidesCommandsWithoutResultContext()
testResultCommandStateBuildsFromResultTexts()
testResultCommandFactoryBuildsStableMenuCommands()
testResultCommandFactoryExplainsProtectedConversationExports()
testResultCommandFactoryAdaptsAISettingsRecoveryCommand()
testResultCommandFactoryAdaptsRetryRecoveryCommand()
testResultCommandFactoryIncludesResultWriteBackAndRegenerateCommands()
testResultCommandFactoryUsesStopWhileStreaming()
testResultCommandFactoryOmitsDiagnosticsWhenUnavailable()
testResultCommandFactoryShowsRecoverySettingsWithoutDiagnostics()
testHistoryEntryMarkdownExport()
testHistoryEntryCompactTitlesForMenus()
testHistoryEntryCommandPaletteKeywordsCoverMetadata()
testHistoryStorePersistsAndSearchesWithFTS()
testHistorySearchUsesStoreResultsBeforeFacetFiltering()
testHistorySearchFallsBackToMemoryForCompactMatching()
testHistoryFilterCriteriaMatchesMultipleTermsAndFacets()
testHistoryFilterCriteriaMatchesDisplayFallbacks()
testHistoryCollectionExportMarkdown()
testHistoryContextProfileBuilderCreatesSafeContextDraft()
testHistoryContextProfileBuilderSanitizesMetadata()
testAppSettingsUpsertsHistoryContextProfileByName()
testHistoryContextCommandFactoryBuildsUsableContextCommands()
testHistoryExportCommandsUseDisplayTags()
testHistoryExportCommandFactoryBuildsRankedFacetCommands()
testHistoryExportCommandFactoryKeepsPrivacyTagsBeyondFacetLimit()
testHistoryExportCommandIDsAreStableSlugs()
testConversationExportMarkdown()
testResultPersistenceAndWriteBackCoordinator()

if failures.isEmpty {
    print("SnapAILogicTests passed")
} else {
    print("SnapAILogicTests failed:")
    failures.forEach { print("- \($0)") }
    exit(1)
}
