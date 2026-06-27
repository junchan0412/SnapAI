import Foundation
import Carbon.HIToolbox

var failures: [String] = []

func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() {
        failures.append(message)
    }
}

func testVersionNormalizationAndCompare() {
    expect(UpdateChecker.normalizedVersion("v1.2.3") == "1.2.3", "normalizes v prefix")
    expect(UpdateChecker.compareVersions("1.2.0", "1.1.9") == .orderedDescending, "orders newer version")
    expect(UpdateChecker.compareVersions("1.2", "1.2.0") == .orderedSame, "pads missing version parts")
    expect(UpdateChecker.compareVersions("1.2.0", "1.2.1") == .orderedAscending, "orders older version")
}

func testReleaseTagParsing() {
    let url = URL(string: "https://github.com/junchan0412/SnapAI/releases/tag/v1.2.3")
    expect(UpdateChecker.releaseTag(from: url) == "v1.2.3", "parses release tag URL")
    expect(UpdateChecker.releaseTag(from: URL(string: "https://github.com/junchan0412/SnapAI/releases/latest")) == nil,
           "ignores latest URL without tag component")
}

func testDesignatedRequirementParsing() {
    let output = """
    Executable=/Applications/SnapAI.app/Contents/MacOS/SnapAI
    Identifier=com.snapai.app
    designated => identifier "com.snapai.app" and certificate leaf = H"547f9e9ccbac459f1ae9db2644e819edeb2e766e"
    """
    expect(
        UpdateChecker.designatedRequirementLine(from: output) == "identifier \"com.snapai.app\" and certificate leaf = H\"547f9e9ccbac459f1ae9db2644e819edeb2e766e\"",
        "parses designated requirement from codesign output"
    )
}

func testBaseURLNormalization() {
    expect(AIClient.normalizedBase("api.openai.com", proto: .openAI) == "https://api.openai.com/v1",
           "adds https and /v1")
    expect(AIClient.normalizedBase("https://api.deepseek.com/v1/chat/completions", proto: .openAI) == "https://api.deepseek.com/v1",
           "strips method suffix")
    expect(AIClient.normalizedBase("http://localhost:11434", proto: .openAI) == "http://localhost:11434/v1",
           "keeps local http")
}

func testPromptRender() {
    var action = AIAction()
    action.prompt = "翻译: {{lang}}\n{{text}}"
    action.isTranslation = true
    action.targetLanguage = .english
    expect(action.render(text: "你好") == "翻译: 翻译成自然流畅的英语\n你好", "renders text and language placeholders")
}

func testHotKeyConflictDetection() {
    var ask = AIAction.defaults()[0]
    ask.id = "ask"
    var translate = AIAction.defaults()[1]
    translate.id = "translate"
    let conflict = HotKeyConflictDetector.conflict(
        for: ask.hotKey!,
        actions: [ask, translate],
        excludingActionID: "translate",
        quickPanelHotKey: .quickPanelDefault,
        includeQuickPanel: true
    )
    expect(conflict != nil, "detects action hotkey conflict")
    expect(HotKeyConflictDetector.systemWarning(
        for: HotKeyCombo(keyCode: UInt32(kVK_ANSI_Q), modifiers: UInt32(cmdKey))
    ) != nil, "warns for common system shortcut")
}

func testAIRouterIncludesFallbackCandidates() {
    let settings = AppSettings()
    var primary = AIProvider(name: "Primary", apiProtocol: .openAI,
                             baseURL: "https://primary.test/v1",
                             apiKey: "key",
                             models: [AIModelEntry(name: "gpt-4o-mini")])
    var fallback = AIProvider(name: "Fallback", apiProtocol: .openAI,
                              baseURL: "https://fallback.test/v1",
                              apiKey: "key",
                              models: [AIModelEntry(name: "claude-sonnet-200k")])
    primary.isEnabled = true
    fallback.isEnabled = true
    settings.providers = [primary, fallback]
    settings.activeProviderID = primary.id
    settings.activeModel = "gpt-4o-mini"
    settings.autoRouteEnabled = true
    settings.fallbackEnabled = true

    let routes = AIRequestRouter.candidates(settings: settings,
                                            action: AIAction.defaults()[0],
                                            sourceText: String(repeating: "长", count: 9_000),
                                            hasImage: false)
    expect(routes.first?.providerID == primary.id, "keeps active route first")
    expect(routes.contains { $0.providerID == fallback.id && $0.modelName == "claude-sonnet-200k" },
           "includes fallback candidate")
}

func testAIRouterSkipsDisabledActionOverrideModel() {
    let settings = AppSettings()
    var provider = AIProvider(name: "Primary", apiProtocol: .openAI,
                              baseURL: "https://primary.test/v1",
                              apiKey: "key",
                              models: [
                                AIModelEntry(name: "disabled-model", enabled: false),
                                AIModelEntry(name: "enabled-model", enabled: true)
                              ])
    provider.isEnabled = true
    settings.providers = [provider]
    settings.activeProviderID = provider.id
    settings.activeModel = "enabled-model"
    settings.autoRouteEnabled = false
    settings.fallbackEnabled = false

    var action = AIAction.defaults()[0]
    action.providerID = provider.id
    action.modelOverride = "disabled-model"

    let routes = AIRequestRouter.candidates(settings: settings,
                                            action: action,
                                            sourceText: "hello",
                                            hasImage: false)
    expect(routes.first?.modelName == "enabled-model", "skips disabled action override model")
}

func testModelCapabilityInference() {
    let gemini = ModelCapabilityRegistry.capability(for: "gemini-1.5-pro-1m")
    expect(gemini.supportsVision, "gemini supports vision")
    expect(gemini.supportsLongContext, "gemini 1m supports long context")

    let r1 = ModelCapabilityRegistry.capability(for: "deepseek-r1")
    expect(r1.supportsReasoning, "r1 supports reasoning")
    expect(r1.isCodeCapable, "deepseek is code capable")

    let mini = ModelCapabilityRegistry.capability(for: "gpt-4o-mini")
    expect(mini.isFast, "mini model is fast")
    expect(mini.isEconomical, "mini model is economical")
}

func testAIRouterUsesCapabilityReasonForCodeAction() {
    let settings = AppSettings()
    var provider = AIProvider(name: "Primary", apiProtocol: .openAI,
                              baseURL: "https://primary.test/v1",
                              apiKey: "key",
                              models: [
                                AIModelEntry(name: "gpt-4o-mini"),
                                AIModelEntry(name: "deepseek-coder")
                              ])
    provider.isEnabled = true
    settings.providers = [provider]
    settings.activeProviderID = provider.id
    settings.activeModel = "gpt-4o-mini"
    settings.autoRouteEnabled = true
    settings.fallbackEnabled = false

    var action = AIAction.defaults()[4]
    action.providerID = nil

    let routes = AIRequestRouter.candidates(settings: settings,
                                            action: action,
                                            sourceText: "func test() {}",
                                            hasImage: false)
    expect(routes.first?.reason == "当前模型", "keeps current model as explicit first route")
    expect(routes.contains { $0.reason == "代码任务优先" }, "adds code capability route reason")
}

func testPrivacyRedactionDefaults() {
    let text = "联系我 test@example.com 或 13800138000, token sk-abcdefghijklmnopqrstuvwxyz"
    let redacted = PrivacyFilter.apply(to: text, rules: PrivacyRedactionRule.defaults())
    expect(!redacted.contains("test@example.com"), "redacts email")
    expect(!redacted.contains("13800138000"), "redacts phone")
    expect(redacted.contains("[邮箱]"), "uses email replacement")
    expect(redacted.contains("[手机号]"), "uses phone replacement")
}

func testTextDiffSummary() {
    let rows = TextDiff.rows(original: "A\nB\nD", revised: "A\nC\nD\nE")
    let summary = TextDiff.summary(for: rows)
    expect(summary.changed == 1, "counts changed lines")
    expect(summary.inserted == 1, "counts inserted lines")
    expect(summary.deleted == 0, "does not count paired change as delete")
    expect(rows.contains { $0.kind == .unchanged && $0.original == "A" }, "keeps common prefix")
    expect(rows.contains { $0.kind == .unchanged && $0.original == "D" }, "keeps common suffix")
}

func testTextDiffCapsLargePreviewRows() {
    let original = (0..<2_000).map { "old-\($0)" }.joined(separator: "\n")
    let revised = (0..<2_000).map { "new-\($0)" }.joined(separator: "\n")
    let rows = TextDiff.rows(original: original, revised: revised, maxRows: 100)
    expect(rows.count == 100, "caps large diff preview rows")
    expect(rows.allSatisfy { $0.kind == .changed }, "keeps changed rows when capped")
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
}

testVersionNormalizationAndCompare()
testReleaseTagParsing()
testDesignatedRequirementParsing()
testBaseURLNormalization()
testPromptRender()
testHotKeyConflictDetection()
testAIRouterIncludesFallbackCandidates()
testAIRouterSkipsDisabledActionOverrideModel()
testModelCapabilityInference()
testAIRouterUsesCapabilityReasonForCodeAction()
testPrivacyRedactionDefaults()
testTextDiffSummary()
testTextDiffCapsLargePreviewRows()
testContextProfileEffectiveSystemPrompt()

if failures.isEmpty {
    print("SnapAILogicTests passed")
} else {
    print("SnapAILogicTests failed:")
    failures.forEach { print("- \($0)") }
    exit(1)
}
