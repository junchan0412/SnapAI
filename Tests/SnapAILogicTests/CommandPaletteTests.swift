import Foundation
import AppKit
import ApplicationServices
import Carbon.HIToolbox
#if !SNAPAI_MANUAL_TEST_MAIN
@testable import SnapAILogic
#endif

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
    let detail = HotKeyConflictDetector.conflictDetail(
        for: ask.hotKey!,
        actions: [ask, translate],
        excludingActionID: "translate",
        quickPanelHotKey: .quickPanelDefault,
        includeQuickPanel: true
    )
    expect(detail == HotKeyConflictDetector.Conflict(title: "提问", target: .action(id: "ask")),
           "hotkey conflict detail points to the conflicting action")
    let quickPanelConflict = HotKeyConflictDetector.conflictDetail(
        for: .quickPanelDefault,
        actions: [ask, translate],
        excludingActionID: nil,
        quickPanelHotKey: .quickPanelDefault,
        includeQuickPanel: true
    )
    expect(quickPanelConflict == HotKeyConflictDetector.Conflict(title: "快捷提问面板", target: .quickPanel),
           "hotkey conflict detail points to the quick panel shortcut")
    expect(HotKeyConflictDetector.systemWarning(
        for: HotKeyCombo(keyCode: UInt32(kVK_ANSI_Q), modifiers: UInt32(cmdKey))
    ) != nil, "warns for common system shortcut")
}

func testHotKeyRecorderTextDescribesRecordingAndReservedShortcuts() {
    expect(HotKeyRecorderText.title(for: .unset, recording: false) == "未设置",
           "hotkey recorder shows a clear empty state")
    expect(HotKeyRecorderText.title(for: .askDefault, recording: true) == "录制中...",
           "hotkey recorder shows a distinct recording state")
    expect(HotKeyRecorderText.recordingHelp.contains("Esc") &&
           HotKeyRecorderText.recordingHelp.contains("Delete"),
           "hotkey recorder recording help explains cancel and clear keys")
    let commandQ = HotKeyCombo(keyCode: UInt32(kVK_ANSI_Q), modifiers: UInt32(cmdKey))
    expect(HotKeyRecorderText.help(for: commandQ, recording: false).contains("退出应用"),
           "hotkey recorder help carries reserved system shortcut warnings")
    expect(HotKeyRecorderText.instructions.contains("Esc") &&
           HotKeyRecorderText.instructions.contains("Delete") &&
           HotKeyRecorderText.instructions.contains("系统保留快捷键"),
           "hotkey recorder visible instructions explain cancel, clear, and reserved shortcuts")
}

func testHotKeyCoordinatorDetectsConflictsAndRegistrationFailures() {
    let settings = AppSettings()
    let sharedCombo = HotKeyCombo(keyCode: UInt32(kVK_ANSI_A), modifiers: UInt32(optionKey))
    var first = AIAction(name: "一号", hotKey: sharedCombo)
    first.id = "first"
    var second = AIAction(name: "二号", hotKey: sharedCombo)
    second.id = "second"
    settings.actions = [first, second]
    settings.quickPanelHotKey = HotKeyCombo(keyCode: UInt32(kVK_Space), modifiers: UInt32(optionKey))

    var unregisterCalled = false
    var registeredCombos: [HotKeyCombo] = []
    var triggeredActionID: String?
    var quickTriggered = false
    var handlers: [() -> Void] = []
    let failures = HotKeyCoordinator().registerAll(
        settings: settings,
        actionHandler: { triggeredActionID = $0 },
        quickPanelHandler: { quickTriggered = true },
        registerHotKey: { combo, handler in
            registeredCombos.append(combo)
            handlers.append(handler)
            if combo == settings.quickPanelHotKey { return nil }
            return UInt32(registeredCombos.count)
        },
        unregisterAll: {
            unregisterCalled = true
        },
        logFailures: false
    )

    expect(unregisterCalled, "hotkey coordinator unregisters existing shortcuts before registration")
    expect(registeredCombos == [sharedCombo, settings.quickPanelHotKey],
           "hotkey coordinator registers first unique action and quick panel shortcut")
    expect(failures.contains { $0.contains("动作「二号」") && $0.contains("冲突") },
           "hotkey coordinator reports duplicate action shortcut conflicts")
    expect(failures.contains { $0.contains("快捷提问面板") && $0.contains("注册失败") },
           "hotkey coordinator reports registrar failures")
    handlers.first?()
    handlers.dropFirst().first?()
    expect(triggeredActionID == "first", "hotkey coordinator routes action hotkey callbacks")
    expect(quickTriggered, "hotkey coordinator routes quick panel callback")
}

func testCommandPaletteMatchesMultipleTerms() {
    expect(CommandPaletteMatcher.matches(title: "复制完整结果",
                                         subtitle: "Markdown,含原文、结果、模型和路由摘要",
                                         keywords: "result markdown export copy 完整 结果",
                                         query: "copy result"),
           "matches multiple terms across keywords")
    expect(CommandPaletteMatcher.matches(title: "复制完整结果",
                                         subtitle: "Markdown,含原文、结果、模型和路由摘要",
                                         keywords: "result markdown export copy 完整 结果",
                                         query: "完整 markdown"),
           "matches mixed title and keyword terms")
    expect(!CommandPaletteMatcher.matches(title: "复制完整结果",
                                          subtitle: "Markdown,含原文、结果、模型和路由摘要",
                                          keywords: "result markdown export copy 完整 结果",
                                          query: "history delete"),
           "rejects unrelated multi-term query")
    expect(CommandPaletteMatcher.matches(title: "gpt-4o-mini",
                                         subtitle: "切换模型 - Open AI",
                                         keywords: "model provider",
                                         query: "gpt4o"),
           "matches compact model queries without separators")
    expect(CommandPaletteMatcher.matches(title: "切换模型",
                                         subtitle: "Open AI / gpt-4o-mini",
                                         keywords: "provider",
                                         query: "openai"),
           "matches compact provider queries without spaces")
    expect(CommandPaletteMatcher.matches(title: "复制标签「项目A」历史",
                                         subtitle: "2 条记录,Markdown",
                                         keywords: "history export copy tag 项目A",
                                         query: "标签：项目A"),
           "matches queries separated by full-width colon")
    expect(CommandPaletteMatcher.matches(title: "复制全部历史",
                                         subtitle: "Markdown,含原文、结果、模型",
                                         keywords: "history export copy markdown 历史 导出 复制",
                                         query: "复制，历史"),
           "matches queries separated by Chinese comma")
    expect(CommandPaletteMatcher.matches(title: "复制模型「gpt-4o-mini」历史",
                                         subtitle: "2 条记录,Markdown",
                                         keywords: "history export copy model gpt-4o-mini",
                                         query: "模型《gpt4o》"),
           "matches compact terms wrapped in Chinese punctuation")
}

func testCommandPaletteRanksMatchesByRelevance() {
    struct Fixture {
        let id: String
        let title: String
        let subtitle: String
        let keywords: String
    }
    let items = [
        Fixture(id: "keyword", title: "打开设置", subtitle: "供应商、动作、隐私", keywords: "model provider settings"),
        Fixture(id: "title", title: "模型设置", subtitle: "供应商和路由", keywords: "settings"),
        Fixture(id: "subtitle", title: "检查更新", subtitle: "模型 manifest", keywords: "release")
    ]
    let ranked = CommandPaletteMatcher.ranked(items, query: "模型") { item in
        (title: item.title, subtitle: item.subtitle, keywords: item.keywords)
    }
    expect(ranked.map(\.id) == ["title", "subtitle"], "ranks title matches before subtitle matches and filters keyword-only misses")

    let stable = CommandPaletteMatcher.ranked(items, query: "") { item in
        (title: item.title, subtitle: item.subtitle, keywords: item.keywords)
    }
    expect(stable.map(\.id) == ["keyword", "title", "subtitle"], "preserves original order for empty query")

    let compactRanked = CommandPaletteMatcher.ranked([
        Fixture(id: "compact", title: "gpt-4o-mini", subtitle: "切换模型", keywords: ""),
        Fixture(id: "prefix", title: "gpt4o local", subtitle: "切换模型", keywords: "")
    ], query: "gpt4o") { item in
        (title: item.title, subtitle: item.subtitle, keywords: item.keywords)
    }
    expect(compactRanked.map(\.id) == ["prefix", "compact"],
           "ranks direct prefix matches before compact separator-insensitive matches")
}

func testCommandPaletteSearchesShortcutTextAliases() {
    let keywords = CommandPaletteMatcher.shortcutSearchKeywords("⌘⇧C")
    let keywordParts = keywords.split(separator: " ").map(String.init)
    expect(Array(keywordParts.prefix(5)) == ["⌘⇧c", "cmd", "command", "shift", "c"],
           "shortcut keywords preserve first occurrence order")
    expect(Set(keywordParts).count == keywordParts.count,
           "shortcut keywords remove duplicates without reordering")
    expect(keywords.contains("cmd"), "shortcut keywords include cmd alias")
    expect(keywords.contains("command"), "shortcut keywords include command alias")
    expect(keywords.contains("shift"), "shortcut keywords include shift alias")
    expect(keywords.contains("c"), "shortcut keywords include key")
    let spaceKeywords = CommandPaletteMatcher.shortcutSearchKeywords("⌥Space")
    expect(spaceKeywords.contains("space"), "shortcut keywords include Space text key")
    expect(spaceKeywords.contains("optionspace"), "shortcut keywords include compact option-space alias")
    let symbolSpaceKeywords = CommandPaletteMatcher.shortcutSearchKeywords("⌘␣")
    expect(symbolSpaceKeywords.contains("cmdspace"), "shortcut keywords include compact command-space alias")
    let escapeKeywords = CommandPaletteMatcher.shortcutSearchKeywords("⌘⎋")
    expect(escapeKeywords.contains("cmdesc"), "shortcut keywords include compact command-escape alias")
    expect(escapeKeywords.contains("escape"), "shortcut keywords include escape alias for symbol key")
    let returnKeywords = CommandPaletteMatcher.shortcutSearchKeywords("⌘⇧↩")
    expect(returnKeywords.contains("return"), "shortcut keywords include return alias for return symbol")
    expect(returnKeywords.contains("enter"), "shortcut keywords include enter alias for return symbol")
    expect(returnKeywords.contains("cmdshiftreturn"), "shortcut keywords include compact command-shift-return alias")
    expect(returnKeywords.contains("cmdshiftenter"), "shortcut keywords include compact command-shift-enter alias")
    let optionKeywords = CommandPaletteMatcher.shortcutSearchKeywords("⌘⌥C")
    expect(optionKeywords.contains("cmdoptionc"), "shortcut keywords include primary command-option compact alias")
    expect(optionKeywords.contains("cmdoptc"), "shortcut keywords include short option compact alias")
    expect(optionKeywords.contains("cmdaltc"), "shortcut keywords include alt compact alias")
    expect(optionKeywords.contains("commandaltc"), "shortcut keywords include command-alt compact alias")
    let forwardDeleteKeywords = CommandPaletteMatcher.shortcutSearchKeywords("⌘⌦")
    expect(forwardDeleteKeywords.contains("forwarddelete"), "shortcut keywords include forward delete alias")
    expect(forwardDeleteKeywords.contains("cmdforwarddelete"), "shortcut keywords include compact command-forward-delete alias")
    expect(forwardDeleteKeywords.contains("cmddelete"), "shortcut keywords include compact command-delete alias")
    let deleteKeywords = CommandPaletteMatcher.shortcutSearchKeywords("Delete")
    expect(deleteKeywords.contains("delete"), "shortcut keywords include Delete text key")
    let backspaceKeywords = CommandPaletteMatcher.shortcutSearchKeywords("Backspace")
    expect(backspaceKeywords.contains("backspace"), "shortcut keywords include Backspace text key")
    expect(backspaceKeywords.contains("delete"), "shortcut keywords treat Backspace as a delete key")
    expect(!backspaceKeywords.split(separator: " ").contains("space"),
           "shortcut keywords do not treat Backspace as Space")

    expect(CommandPaletteMatcher.matches(title: "复制结果",
                                         subtitle: "当前结果面板",
                                         keywords: "result copy \(CommandPaletteMatcher.shortcutSearchKeywords("⌘⇧C"))",
                                         query: "cmd shift c"),
           "command palette matcher matches shortcut aliases")
    expect(CommandPaletteMatcher.matches(title: "复制结果",
                                         subtitle: "当前结果面板",
                                         keywords: "result copy \(CommandPaletteMatcher.shortcutSearchKeywords("⌘⇧C"))",
                                         query: "command c"),
           "command palette matcher matches command alias and key")
    expect(CommandPaletteMatcher.matches(title: "复制结果",
                                         subtitle: "当前结果面板",
                                         keywords: "result copy \(CommandPaletteMatcher.shortcutSearchKeywords("⌘⇧C"))",
                                         query: "cmd+shift+c"),
           "command palette matcher treats plus signs as shortcut separators")
    expect(CommandPaletteMatcher.matches(title: "复制结果",
                                         subtitle: "当前结果面板",
                                         keywords: "result copy \(CommandPaletteMatcher.shortcutSearchKeywords("⌘⇧C"))",
                                         query: "⌘+⇧+C"),
           "command palette matcher handles symbol shortcuts with separators")
    expect(CommandPaletteMatcher.matches(title: "快捷提问",
                                         subtitle: "打开快捷提问面板",
                                         keywords: "quick ask \(CommandPaletteMatcher.shortcutSearchKeywords("⌥Space"))",
                                         query: "option space"),
           "command palette matcher matches option-space shortcut")
    expect(CommandPaletteMatcher.matches(title: "快捷提问",
                                         subtitle: "打开快捷提问面板",
                                         keywords: "quick ask \(CommandPaletteMatcher.shortcutSearchKeywords("⌥Space"))",
                                         query: "optionspace"),
           "command palette matcher matches compact option-space shortcut")
    expect(CommandPaletteMatcher.matches(title: "停止生成",
                                         subtitle: "当前结果面板",
                                         keywords: "result stop \(CommandPaletteMatcher.shortcutSearchKeywords("Esc"))",
                                         query: "escape"),
           "command palette matcher matches escape alias for Esc text")
    expect(CommandPaletteMatcher.matches(title: "追加到文档",
                                         subtitle: "当前结果面板",
                                         keywords: "result append \(CommandPaletteMatcher.shortcutSearchKeywords("⌘⇧↩"))",
                                         query: "cmdshiftenter"),
           "command palette matcher matches compact command-shift-enter shortcut")
    expect(CommandPaletteMatcher.matches(title: "追加到文档",
                                         subtitle: "当前结果面板",
                                         keywords: "result append \(CommandPaletteMatcher.shortcutSearchKeywords("⌘⇧↩"))",
                                         query: "cmd return"),
           "command palette matcher matches command-return alias")
    expect(CommandPaletteMatcher.matches(title: "复制完整结果",
                                         subtitle: "当前结果面板",
                                         keywords: "result copy markdown \(CommandPaletteMatcher.shortcutSearchKeywords("⌘⌥C"))",
                                         query: "cmdoptc"),
           "command palette matcher matches compact command-option shortcut with opt alias")
    expect(CommandPaletteMatcher.matches(title: "复制完整结果",
                                         subtitle: "当前结果面板",
                                         keywords: "result copy markdown \(CommandPaletteMatcher.shortcutSearchKeywords("⌘⌥C"))",
                                         query: "cmdaltc"),
           "command palette matcher matches compact command-option shortcut with alt alias")
    expect(CommandPaletteMatcher.matches(title: "删除历史",
                                         subtitle: "历史记录",
                                         keywords: "history delete \(CommandPaletteMatcher.shortcutSearchKeywords("⌘⌦"))",
                                         query: "cmddelete"),
           "command palette matcher matches compact command-delete shortcut")
    expect(CommandPaletteMatcher.matches(title: "gpt-4o-mini",
                                         subtitle: "当前模型 - OpenAI",
                                         keywords: "model provider ai switch",
                                         query: "gpt-4o"),
           "command palette matcher splits hyphenated model queries without losing matches")

    struct Fixture {
        let id: String
        let title: String
        let subtitle: String
        let keywords: String
    }
    let ranked = CommandPaletteMatcher.ranked([
        Fixture(id: "quick",
                title: "快捷提问",
                subtitle: "打开快捷提问面板",
                keywords: "quick ask \(CommandPaletteMatcher.shortcutSearchKeywords("⌥Space"))"),
        Fixture(id: "copy",
                title: "复制结果",
                subtitle: "当前结果面板",
                keywords: "result copy \(CommandPaletteMatcher.shortcutSearchKeywords("⌘⇧C"))")
    ], query: "cmd shift c") { item in
        (title: item.title, subtitle: item.subtitle, keywords: item.keywords)
    }
    expect(ranked.map(\.id) == ["copy"], "command palette ranking indexes shortcut aliases")

    let unsafeSearchKeywords = MarkdownExportSafety.keywords([
        "alpha\napi_key=supersecret123456|`mark`",
        CommandPaletteMatcher.shortcutSearchKeywords("⌘⇧K")
    ])
    expect(unsafeSearchKeywords.contains("alpha"), "command palette keeps safe keyword content")
    expect(unsafeSearchKeywords.contains("cmdshiftk"), "command palette still indexes shortcut aliases")
    expect(!unsafeSearchKeywords.contains("supersecret123456"),
           "command palette searchable keywords redact key-like fragments")
    expect(!unsafeSearchKeywords.contains("\n") &&
           !unsafeSearchKeywords.contains("|") &&
           !unsafeSearchKeywords.contains("`"),
           "command palette searchable keywords are single-line and markdown-safe")
}

func testCommandIdentifierSlugAndUniqueness() {
    expect(CommandIdentifier.slug(for: " gpt/4o mini ") == "gpt-4o-mini",
           "command identifier slug replaces separators and trims edges")
    expect(CommandIdentifier.slug(for: "项目/Alpha") == "项目-Alpha",
           "command identifier slug keeps readable unicode letters")
    expect(CommandIdentifier.slug(for: " / ") == "untitled",
           "command identifier slug falls back for separator-only values")

    var usedIDs: Set<String> = ["model-local-gpt-4o-mini"]
    let first = CommandIdentifier.unique(prefix: "model",
                                         values: ["local", "gpt/4o mini"],
                                         usedIDs: &usedIDs)
    let second = CommandIdentifier.unique(prefix: "model",
                                          values: ["local", "gpt 4o mini"],
                                          usedIDs: &usedIDs)
    expect(first == "model-local-gpt-4o-mini-2",
           "command identifier unique appends suffix for existing ids")
    expect(second == "model-local-gpt-4o-mini-3",
           "command identifier unique keeps suffixing for repeated collisions")

    var baseIDs: Set<String> = ["settings"]
    let duplicateBase = CommandIdentifier.unique(base: "settings", usedIDs: &baseIDs)
    let rawBase = CommandIdentifier.unique(base: "team/A", usedIDs: &baseIDs)
    expect(duplicateBase == "settings-2",
           "command identifier unique base appends suffix for duplicate item ids")
    expect(rawBase == "team-A",
           "command identifier unique base slugs raw item ids before use")

    expect(CommandIdentifier.uniqued(["settings", "settings", "team/A", " / "]) == [
        "settings",
        "settings-2",
        "team-A",
        "untitled"
    ], "command identifier uniqued maps item id lists to stable safe unique ids")
}

func testModelSwitchCommandFactoryFiltersAndMarksCurrentModel() {
    let primary = ModelSwitchProviderInput(id: "openai",
                                           name: "OpenAI",
                                           isEnabled: true,
                                           enabledModelNames: ["gpt-4o-mini"])
    let disabledProvider = ModelSwitchProviderInput(id: "disabled",
                                                    name: "Disabled",
                                                    isEnabled: false,
                                                    enabledModelNames: ["hidden-model"])
    let fallback = ModelSwitchProviderInput(id: "deepseek",
                                            name: "DeepSeek",
                                            isEnabled: true,
                                            enabledModelNames: ["deepseek-chat"])

    let descriptors = ModelSwitchCommandFactory.descriptors(providers: [primary, disabledProvider, fallback],
                                                            activeProviderID: "openai",
                                                            activeModel: "gpt-4o-mini")

    expect(descriptors.map(\.id) == [
        "model-openai-gpt-4o-mini",
        "model-deepseek-deepseek-chat"
    ], "model switch commands include enabled provider models only")
    expect(descriptors[0].subtitle == "当前模型 - OpenAI", "current model is marked in subtitle")
    expect(descriptors[0].systemImage == "checkmark.circle.fill", "current model uses check icon")
    expect(descriptors[1].subtitle == "切换模型 - DeepSeek", "non-current model offers switch")
    expect(descriptors[1].keywords.contains("deepseek-chat"), "model command is searchable by model")
    expect(descriptors[1].providerID == "deepseek" && descriptors[1].modelName == "deepseek-chat",
           "model command carries switch target")
}

func testMenuCoordinatorBuildsModelSwitchMenu() {
    let settings = AppSettings()
    var primary = AIProvider(name: "OpenAI",
                             apiProtocol: .openAI,
                             baseURL: "https://api.openai.com/v1",
                             apiKey: "key",
                             models: [
                                AIModelEntry(name: "gpt-4o-mini"),
                                AIModelEntry(name: "disabled-model", enabled: false)
                             ])
    primary.id = "openai"
    primary.isEnabled = true
    var disabledProvider = AIProvider(name: "Disabled",
                                      apiProtocol: .openAI,
                                      baseURL: "https://disabled.test/v1",
                                      apiKey: "key",
                                      models: [AIModelEntry(name: "hidden-model")])
    disabledProvider.id = "disabled"
    disabledProvider.isEnabled = false
    settings.providers = [primary, disabledProvider]
    settings.activeProviderID = primary.id
    settings.activeModel = "gpt-4o-mini"

    let menu = MenuCoordinator.modelSwitchMenu(settings: settings,
                                               target: NSObject(),
                                               action: Selector(("switchModel:")))
    let titles = menu.items.map(\.title)
    expect(titles.contains("OpenAI"), "model switch menu includes enabled provider header")
    expect(titles.contains("  gpt-4o-mini"), "model switch menu includes enabled model")
    expect(!titles.contains("Disabled"), "model switch menu omits disabled providers")
    expect(!titles.contains("  disabled-model"), "model switch menu omits disabled models")
    let modelItem = menu.items.first { $0.title == "  gpt-4o-mini" }
    expect(modelItem?.state == .on, "model switch menu marks the active model")
    let represented = modelItem?.representedObject as? [String: String]
    expect(represented?["provider"] == "openai" && represented?["model"] == "gpt-4o-mini",
           "model switch menu carries provider and model identifiers")
}

func testModelSwitchCommandIDsAreStableSlugs() {
    let provider = ModelSwitchProviderInput(id: "local/test",
                                            name: "Local",
                                            isEnabled: true,
                                            enabledModelNames: ["gpt/4o mini", "gpt 4o mini"])

    let descriptors = ModelSwitchCommandFactory.descriptors(providers: [provider],
                                                            activeProviderID: "local/test",
                                                            activeModel: "gpt/4o mini")

    expect(descriptors.map(\.id) == [
        "model-local-test-gpt-4o-mini",
        "model-local-test-gpt-4o-mini-2"
    ], "model switch command ids slug provider and model values with collision suffixes")
    expect(descriptors.map(\.modelName) == ["gpt/4o mini", "gpt 4o mini"],
           "model switch command ids do not alter switch target model names")
    expect(descriptors.allSatisfy { !$0.id.contains("/") && !$0.id.contains(" ") },
           "model switch command ids do not contain path or whitespace separators")

    let unsafeProvider = ModelSwitchProviderInput(id: "unsafe",
                                                  name: "Local\nLab|`A`",
                                                  isEnabled: true,
                                                  enabledModelNames: ["gpt\n4o|mini"])
    let unsafe = ModelSwitchCommandFactory.descriptors(providers: [unsafeProvider],
                                                       activeProviderID: "unsafe",
                                                       activeModel: "gpt\n4o|mini")
    expect(unsafe.first?.title == "gpt 4o/mini", "model command title keeps unsafe model names single-line")
    expect(unsafe.first?.subtitle == "当前模型 - Local Lab/'A'",
           "model command subtitle keeps unsafe provider names single-line")
    expect(unsafe.first?.modelName == "gpt\n4o|mini",
           "model command action target keeps the original model name")
    expect(unsafe.first?.keywords.contains("\n") == false &&
           unsafe.first?.keywords.contains("|") == false &&
           unsafe.first?.keywords.contains("`") == false,
           "model command keywords keep unsafe provider and model names search-safe")
}

private func actionCommandInputs(_ actions: [AIAction]) -> [ActionCommandInput] {
    actions.map { action in
        ActionCommandInput(id: action.id,
                           name: action.name,
                           group: action.group,
                           icon: action.icon,
                           isEnabled: action.isEnabled,
                           shortcutText: action.hotKey?.displayString)
    }
}

func testActionCommandFactoryFiltersAndFormatsActions() {
    var enabled = AIAction(name: "代码审查",
                           icon: "",
                           group: "开发",
                           hotKey: HotKeyCombo(keyCode: UInt32(kVK_ANSI_R), modifiers: UInt32(optionKey)))
    enabled.id = "review"
    enabled.isEnabled = true
    var disabled = AIAction(name: "禁用动作",
                            icon: "xmark",
                            group: "隐藏")
    disabled.id = "disabled"
    disabled.isEnabled = false
    var plain = AIAction(name: "无快捷键",
                         icon: "sparkles",
                         group: "")
    plain.id = "plain"
    plain.isEnabled = true

    let descriptors = ActionCommandFactory.descriptors(for: actionCommandInputs([enabled, disabled, plain]))

    expect(descriptors.map(\.id) == ["action-review", "action-plain"],
           "action commands include enabled actions only")
    expect(descriptors[0].title == "代码审查", "action command uses action name")
    expect(descriptors[0].subtitle == "动作 - 开发", "action command shows action group in subtitle")
    expect(descriptors[0].shortcutText == "⌥R", "action command exposes hotkey separately")
    expect(descriptors[0].systemImage == "wand.and.stars", "action command falls back when icon is blank")
    expect(descriptors[0].keywords.contains("开发"), "action command is searchable by group")
    expect(descriptors[0].actionID == "review", "action command carries action target")
    expect(descriptors[1].subtitle == "动作", "action command falls back when hotkey is absent")
    expect(descriptors[1].shortcutText == nil, "action command omits shortcut text when hotkey is absent")
    expect(descriptors[1].systemImage == "sparkles", "action command preserves configured icon")

    var unsafe = AIAction(name: "润色\n# 注入|`A`",
                          icon: "",
                          group: "写作\n组|`B`")
    unsafe.id = "unsafe/action"
    unsafe.isEnabled = true
    let unsafeDescriptors = ActionCommandFactory.descriptors(for: actionCommandInputs([unsafe]))
    expect(unsafeDescriptors.first?.title == "润色 # 注入/'A'",
           "action command title keeps unsafe action names single-line")
    expect(unsafeDescriptors.first?.subtitle == "动作 - 写作 组/'B'",
           "action command subtitle keeps unsafe groups single-line")
    expect(unsafeDescriptors.first?.actionID == "unsafe/action",
           "action command keeps the original action id")
    expect(unsafeDescriptors.first?.keywords.contains("\n") == false,
           "action command keywords do not contain newlines")
    expect(unsafeDescriptors.first?.keywords.contains("|") == false &&
           unsafeDescriptors.first?.keywords.contains("`") == false,
           "action command keywords are markdown-safe")
}

func testActionCommandFactoryPrioritizesFrequentActions() {
    var translate = AIAction(name: "翻译", icon: "character.bubble", group: "")
    translate.id = "translate"
    translate.isEnabled = true
    var polish = AIAction(name: "润色", icon: "wand.and.stars", group: "")
    polish.id = "polish"
    polish.isEnabled = true
    var summarize = AIAction(name: "总结", icon: "list.bullet", group: "阅读")
    summarize.id = "summarize"
    summarize.isEnabled = true
    var explain = AIAction(name: "解释", icon: "text.bubble", group: "")
    explain.id = "explain"
    explain.isEnabled = true

    let descriptors = ActionCommandFactory.descriptors(
        for: actionCommandInputs([translate, polish, summarize, explain]),
        usageCounts: ["翻译": 5, "润色": 12, "总结": 5, "解释": -4]
    )

    expect(descriptors.map(\.actionID) == ["polish", "translate", "summarize", "explain"],
           "action commands sort frequent actions first and preserve configured order for equal counts")
    expect(descriptors.map(\.usageCount) == [12, 5, 5, 0],
           "action command descriptors expose sanitized usage counts")
    expect(descriptors[0].subtitle == "动作 · 常用 12 次",
           "frequent action command subtitle exposes usage count")
    expect(descriptors[2].subtitle == "动作 - 阅读 · 常用 5 次",
           "frequent grouped action command keeps group context in subtitle")
    expect(descriptors[0].keywords.contains("常用") &&
           descriptors[0].keywords.contains("recent") &&
           descriptors[0].keywords.contains("12"),
           "frequent action command is searchable by usage intent")
    expect(descriptors[3].subtitle == "动作",
           "unused action command keeps the compact default subtitle")
}

func testActionCommandIDsAreStableSlugs() {
    var slash = AIAction(name: "动作一", icon: "", group: "")
    slash.id = "team/A"
    slash.isEnabled = true
    var space = AIAction(name: "动作二", icon: "", group: "")
    space.id = "team A"
    space.isEnabled = true

    let descriptors = ActionCommandFactory.descriptors(for: actionCommandInputs([slash, space]))

    expect(descriptors.map(\.id) == ["action-team-A", "action-team-A-2"],
           "action command ids slug action ids and disambiguate collisions")
    expect(descriptors.map(\.actionID) == ["team/A", "team A"],
           "action command keeps original action ids as execution targets")
    expect(descriptors.allSatisfy { !$0.id.contains("/") && !$0.id.contains(" ") },
           "action command ids do not contain path or whitespace separators")
}

func testAutomationActionSelectionNormalizesQueries() {
    var review = AIAction(name: "代码 审查", icon: "", group: "开发")
    review.id = "code-review"
    review.isEnabled = true
    var translate = AIAction(name: "翻译", icon: "", group: "")
    translate.id = "translate/default"
    translate.isEnabled = true
    var disabled = AIAction(name: "禁用 动作", icon: "", group: "")
    disabled.id = "disabled-action"
    disabled.isEnabled = false

    let actions = [review, translate, disabled]

    expect(AutomationActionSelection.resolve(query: "code_review", actions: actions)?.id == "code-review",
           "automation action selection normalizes action id separators")
    expect(AutomationActionSelection.resolve(query: "代码审查", actions: actions)?.id == "code-review",
           "automation action selection normalizes action name whitespace")
    expect(AutomationActionSelection.resolve(query: "translate-default", actions: actions)?.id == "translate/default",
           "automation action selection normalizes action id slashes")
    expect(AutomationActionSelection.resolve(query: "禁用动作", actions: actions) == nil,
           "automation action selection rejects disabled actions")
    expect(AutomationActionSelection.resolve(query: nil, actions: actions) == nil,
           "automation action selection requires a query")
}

func testAutomationSettingsSectionSelectionNormalizesQueries() {
    expect(AutomationSettingsSectionSelection.resolve("AI", fallback: .general) == .ai,
           "settings section selection resolves cased AI alias")
    expect(AutomationSettingsSectionSelection.resolve("api_key", fallback: .general) == .ai,
           "settings section selection normalizes AI key aliases")
    expect(AutomationSettingsSectionSelection.resolve("hot-keys", fallback: .general) == .actions,
           "settings section selection normalizes hotkey aliases")
    expect(AutomationSettingsSectionSelection.resolve("history_records", fallback: .general) == .history,
           "settings section selection normalizes history aliases")
    expect(AutomationSettingsSectionSelection.resolve("screen recording", fallback: .general) == .permission,
           "settings section selection normalizes permission aliases")
    expect(AutomationSettingsSectionSelection.resolve("permission/screen-recording", fallback: .general) == .permission,
           "settings section selection normalizes composite permission aliases")
    expect(AutomationSettingsSectionSelection.resolve("login_item", fallback: .ai) == .permission,
           "settings section selection resolves login item aliases")
    expect(AutomationSettingsSectionSelection.resolve("missing", fallback: .history) == .history,
           "settings section selection falls back for unknown sections")
    expect(AutomationSettingsSectionSelection.resolve(nil, fallback: .actions) == .actions,
           "settings section selection falls back for missing sections")
}

func testAutomationRouterParsesURLsAndSettingsSections() {
    expect(AutomationRouter.command(from: "snapai://settings/ai") == .openSettings(section: "ai"),
           "automation router parses raw URL strings into automation commands")
    expect(AutomationRouter.command(from: "not a url") == nil,
           "automation router rejects invalid URL strings")
    expect(AutomationRouter.settingsSection(for: "history_records", fallback: .ai) == .history,
           "automation router resolves settings section aliases")
    expect(AutomationRouter.settingsSection(for: nil, fallback: .permission) == .permission,
           "automation router keeps current settings section as fallback")
}

func testAutomationURLCommandParsing() {
    let run = snapAIURL(host: "run", queryItems: [
        URLQueryItem(name: "action", value: "润色"),
        URLQueryItem(name: "provider", value: "DeepSeek"),
        URLQueryItem(name: "model", value: "deepseek-chat"),
        URLQueryItem(name: "lang", value: "en"),
        URLQueryItem(name: "replace", value: "true"),
        URLQueryItem(name: "history", value: "false"),
        URLQueryItem(name: "text", value: "  保留空白\n")
    ])
    expect(AutomationURLCommand.parse(run) == .run(
        actionQuery: "润色",
        text: "  保留空白\n",
        options: AutomationRunOptions(providerQuery: "DeepSeek",
                                      modelQuery: "deepseek-chat",
                                      saveHistory: false,
                                      targetLanguage: .english,
                                      replaceByDefault: true)
    ), "parses run URL, preserves text whitespace, and captures run options")

    expect(AutomationURLCommand.parse(URL(string: "snapai://run/%E6%80%BB%E7%BB%93?text=hello")!) == .run(actionQuery: "总结", text: "hello"),
           "parses run URL path as action query")
    expect(AutomationURLCommand.parse(URL(string: "snapai:///run/%E7%BF%BB%E8%AF%91?text=hello")!) == .run(actionQuery: "翻译", text: "hello"),
           "parses path-only run URL path as action query")
    expect(AutomationURLCommand.parse(URL(string: "snapai://run/%E6%80%BB%E7%BB%93?action=%E7%BF%BB%E8%AF%91&text=hello")!) == .run(actionQuery: "翻译", text: "hello"),
           "prefers query action over run path action")

    let snakeCaseRun = snapAIURL(host: "run", queryItems: [
        URLQueryItem(name: "action_id", value: "总结"),
        URLQueryItem(name: "provider_id", value: "OpenAI"),
        URLQueryItem(name: "model-override", value: "gpt-4o-mini"),
        URLQueryItem(name: "target_language", value: "zh"),
        URLQueryItem(name: "replace_by_default", value: "on"),
        URLQueryItem(name: "save_history", value: "no"),
        URLQueryItem(name: "text", value: "hello")
    ])
    expect(AutomationURLCommand.parse(snakeCaseRun) == .run(
        actionQuery: "总结",
        text: "hello",
        options: AutomationRunOptions(providerQuery: "OpenAI",
                                      modelQuery: "gpt-4o-mini",
                                      saveHistory: false,
                                      targetLanguage: .chinese,
                                      replaceByDefault: true)
    ), "normalizes snake_case and kebab-case run option names")

    let boolAliasesRun = snapAIURL(host: "run", queryItems: [
        URLQueryItem(name: "save_history", value: "disabled"),
        URLQueryItem(name: "write_back", value: "enabled"),
        URLQueryItem(name: "text", value: "hello")
    ])
    expect(AutomationURLCommand.parse(boolAliasesRun) == .run(
        actionQuery: nil,
        text: "hello",
        options: AutomationRunOptions(saveHistory: false,
                                      replaceByDefault: true)
    ), "normalizes enabled and disabled boolean aliases")

    let conflictingHistoryRun = snapAIURL(host: "run", queryItems: [
        URLQueryItem(name: "history", value: "true"),
        URLQueryItem(name: "saveHistory", value: "false"),
        URLQueryItem(name: "text", value: "hello")
    ])
    expect(AutomationURLCommand.parse(conflictingHistoryRun) == .run(
        actionQuery: nil,
        text: "hello",
        options: AutomationRunOptions(saveHistory: false)
    ), "explicit false save-history run option wins over conflicting true history aliases")

    let normalizedLanguage = snapAIURL(host: "run", queryItems: [
        URLQueryItem(name: "lang", value: "simplified-chinese"),
        URLQueryItem(name: "text", value: "hello")
    ])
    expect(AutomationURLCommand.parse(normalizedLanguage) == .run(
        actionQuery: nil,
        text: "hello",
        options: AutomationRunOptions(targetLanguage: .chinese)
    ), "normalizes hyphenated target language aliases")

    let japaneseLanguage = snapAIURL(host: "run", queryItems: [
        URLQueryItem(name: "target_language", value: "Japanese"),
        URLQueryItem(name: "text", value: "hello")
    ])
    expect(AutomationURLCommand.parse(japaneseLanguage) == .run(
        actionQuery: nil,
        text: "hello",
        options: AutomationRunOptions(targetLanguage: .japanese)
    ), "normalizes cased target language aliases")

    let koreanLanguage = snapAIURL(host: "run", queryItems: [
        URLQueryItem(name: "language", value: "korean_language"),
        URLQueryItem(name: "text", value: "hello")
    ])
    expect(AutomationURLCommand.parse(koreanLanguage) == .run(
        actionQuery: nil,
        text: "hello",
        options: AutomationRunOptions(targetLanguage: .korean)
    ), "normalizes underscore target language aliases")

    let translate = snapAIURL(host: "translate", queryItems: [
        URLQueryItem(name: "text", value: "hello")
    ])
    expect(AutomationURLCommand.parse(translate) == .run(actionQuery: "翻译", text: "hello"),
           "maps translate URL alias to translation action")

    let quick = snapAIURL(host: "quick", queryItems: [
        URLQueryItem(name: "action", value: "翻译"),
        URLQueryItem(name: "prompt", value: "直接打开输入框")
    ])
    expect(AutomationURLCommand.parse(quick) == .openQuickInput(text: "直接打开输入框", actionQuery: "翻译"),
           "parses quick URL with prefilled prompt and action")
    expect(AutomationURLCommand.parse(URL(string: "snapai://quick/%E6%B6%A6%E8%89%B2?prompt=hello")!) == .openQuickInput(text: "hello", actionQuery: "润色"),
           "parses quick URL path as action query")
    expect(AutomationURLCommand.parse(URL(string: "snapai:///quick/%E6%80%BB%E7%BB%93?prompt=hello")!) == .openQuickInput(text: "hello", actionQuery: "总结"),
           "parses path-only quick URL path as action query")
    expect(AutomationURLCommand.parse(URL(string: "snapai://quick/%E6%B6%A6%E8%89%B2?action=%E7%BF%BB%E8%AF%91&prompt=hello")!) == .openQuickInput(text: "hello", actionQuery: "翻译"),
           "prefers query action over quick path action")
    let quickInputAlias = snapAIURL(host: "quick_input", queryItems: [
        URLQueryItem(name: "prompt", value: "下划线命令")
    ])
    expect(AutomationURLCommand.parse(quickInputAlias) == .openQuickInput(text: "下划线命令", actionQuery: nil),
           "normalizes underscore quick input command names")
    expect(AutomationURLCommand.parse(URL(string: "snapai:///quick%20input?prompt=encoded")!) == .openQuickInput(text: "encoded", actionQuery: nil),
           "normalizes encoded-space path command names")

    let settings = snapAIURL(host: "settings", queryItems: [
        URLQueryItem(name: "section", value: "privacy")
    ])
    expect(AutomationURLCommand.parse(settings) == .openSettings(section: "privacy"),
           "parses settings section")

    let settingsPath = URL(string: "snapai://settings/ai")!
    expect(AutomationURLCommand.parse(settingsPath) == .openSettings(section: "ai"),
           "parses settings section from path when query section is absent")
    expect(AutomationURLCommand.parse(URL(string: "snapai:///settings/ai")!) == .openSettings(section: "ai"),
           "parses settings section from path-only URL")
    expect(AutomationURLCommand.parse(URL(string: "snapai://settings/section/permission")!) == .openSettings(section: "permission"),
           "parses labeled settings section path value")
    expect(AutomationURLCommand.parse(URL(string: "snapai:///settings/tab/screen-recording")!) == .openSettings(section: "screen-recording"),
           "parses path-only labeled settings tab path value")
    expect(AutomationURLCommand.parse(URL(string: "snapai://settings/permission/screen-recording")!) == .openSettings(section: "permission/screen-recording"),
           "preserves composite settings section path values")

    let settingsQueryWins = URL(string: "snapai://settings/history?section=permission")!
    expect(AutomationURLCommand.parse(settingsQueryWins) == .openSettings(section: "permission"),
           "prefers settings query section over path section")

    expect(AutomationURLCommand.parse(URL(string: "snapai://history?clear=true")!) == .clearHistory,
           "parses explicit history clear URL")
    expect(AutomationURLCommand.parse(URL(string: "snapai://history/clear")!) == .clearHistory,
           "parses history clear path subcommand")
    expect(AutomationURLCommand.parse(URL(string: "snapai:///history/delete_all")!) == .clearHistory,
           "parses path-only history delete-all subcommand")
    expect(AutomationURLCommand.parse(URL(string: "snapai://history?delete_all")!) == .clearHistory,
           "normalizes snake_case history delete-all flag")
    expect(AutomationURLCommand.parse(URL(string: "snapai://history/clear?clear=false")!) == .openHistory,
           "explicit false clear query suppresses history clear path subcommands")
    expect(AutomationURLCommand.parse(URL(string: "snapai://history/delete-all?reset=off")!) == .openHistory,
           "explicit off reset query suppresses history reset path subcommands")
    expect(AutomationURLCommand.parse(URL(string: "snapai://history/clear?clear=true&reset=off")!) == .openHistory,
           "explicit false-equivalent history clear parameter wins over conflicting true parameters")
    expect(AutomationURLCommand.parse(URL(string: "snapai://history?clear=true&query=release")!) == .openHistory,
           "does not clear all history when a clear URL also carries a search filter")
    expect(AutomationURLCommand.parse(URL(string: "snapai://history/clear?tag=%E9%A1%B9%E7%9B%AEA")!) == .openHistory,
           "does not clear all history when a clear path also carries a tag filter")
    expect(AutomationURLCommand.parse(URL(string: "snapai://history?delete_all=true&favorite=true")!) == .openHistory,
           "does not clear all history when a clear URL also carries a favorite filter")
    expect(AutomationURLCommand.parse(URL(string: "snapai://history?export=true")!) == .copyHistoryMarkdown(),
           "parses history export URL as copy markdown command")
    expect(AutomationURLCommand.parse(URL(string: "snapai://history/export")!) == .copyHistoryMarkdown(),
           "parses history export path subcommand")
    expect(AutomationURLCommand.parse(URL(string: "snapai://history/export?export=false")!) == .openHistory,
           "explicit false export query suppresses history export path subcommands")
    expect(AutomationURLCommand.parse(URL(string: "snapai:///history/markdown")!) == .copyHistoryMarkdown(),
           "parses path-only history markdown subcommand")
    let filteredHistoryPath = snapAIURL(host: "history", queryItems: [
        URLQueryItem(name: "search", value: "release"),
        URLQueryItem(name: "action_name", value: "总结"),
        URLQueryItem(name: "model", value: "gpt-4o-mini"),
        URLQueryItem(name: "tag", value: "发布"),
        URLQueryItem(name: "favorite", value: nil)
    ], path: "/export")
    expect(AutomationURLCommand.parse(filteredHistoryPath) == .copyHistoryMarkdown(criteria: HistoryFilterCriteria(
        query: "release",
        actionFilter: "总结",
        modelFilter: "gpt-4o-mini",
        tagFilter: "发布",
        favoriteOnly: true
    )), "path history export preserves normalized filter query parameters")
    expect(AutomationURLCommand.parse(URL(string: "snapai://history?copy=true")!) == .copyHistoryMarkdown(),
           "parses history copy URL as copy markdown command")
    expect(AutomationURLCommand.parse(URL(string: "snapai://history?export")!) == .copyHistoryMarkdown(),
           "parses flag-style history export URL as copy markdown command")
    expect(AutomationURLCommand.parse(URL(string: "snapai://history?copy=")!) == .copyHistoryMarkdown(),
           "parses empty-value history copy URL as enabled flag")
    expect(AutomationURLCommand.parse(URL(string: "snapai://history/export?copy=true&export=false")!) == .openHistory,
           "explicit false-equivalent history export parameter wins over conflicting true parameters")
    let filteredHistory = snapAIURL(host: "history", queryItems: [
        URLQueryItem(name: "export", value: "true"),
        URLQueryItem(name: "query", value: "release 诊断"),
        URLQueryItem(name: "action", value: "总结"),
        URLQueryItem(name: "model", value: "gpt-4o-mini"),
        URLQueryItem(name: "tag", value: "发布"),
        URLQueryItem(name: "favorite", value: "true")
    ])
    expect(AutomationURLCommand.parse(filteredHistory) == .copyHistoryMarkdown(criteria: HistoryFilterCriteria(
        query: "release 诊断",
        actionFilter: "总结",
        modelFilter: "gpt-4o-mini",
        tagFilter: "发布",
        favoriteOnly: true
    )), "parses filtered history markdown export URL")
    let filteredHistoryContext = snapAIURL(host: "history", queryItems: [
        URLQueryItem(name: "search", value: "release"),
        URLQueryItem(name: "action", value: "总结"),
        URLQueryItem(name: "model", value: "gpt-4o-mini"),
        URLQueryItem(name: "tag", value: "发布"),
        URLQueryItem(name: "favorite", value: "true"),
        URLQueryItem(name: "name", value: "项目A上下文"),
        URLQueryItem(name: "limit", value: "3"),
        URLQueryItem(name: "max_chars", value: "80")
    ], path: "/context")
    expect(AutomationURLCommand.parse(filteredHistoryContext) == .createHistoryContext(criteria: HistoryFilterCriteria(
        query: "release",
        actionFilter: "总结",
        modelFilter: "gpt-4o-mini",
        tagFilter: "发布",
        favoriteOnly: true
    ), options: AutomationHistoryContextOptions(name: "项目A上下文",
                                                maxEntries: 3,
                                                maxFieldCharacters: 80)), "path history context command preserves filters and context options")
    expect(AutomationURLCommand.parse(URL(string: "snapai://history?create_context=true")!) == .createHistoryContext(),
           "parses snake_case history create-context flag")
    expect(AutomationURLCommand.parse(URL(string: "snapai:///history/create-context-profile?tag=%E9%A1%B9%E7%9B%AEA&profile_name=%E9%A1%B9%E7%9B%AEA%E8%AE%B0%E5%BF%86&entry_limit=2&max_field_chars=120")!) == .createHistoryContext(criteria: HistoryFilterCriteria(tagFilter: "项目A"), options: AutomationHistoryContextOptions(name: "项目A记忆", maxEntries: 2, maxFieldCharacters: 120)),
           "parses path-only history create-context-profile subcommand with snake_case context options")
    expect(AutomationURLCommand.parse(URL(string: "snapai://history/context?export=true")!) == .copyHistoryMarkdown(),
           "history export flag takes precedence over context path command")
    expect(AutomationURLCommand.parse(URL(string: "snapai://history/context?clear=true")!) == .clearHistory,
           "history clear flag takes precedence over context path command")
    expect(AutomationURLCommand.parse(URL(string: "snapai://health")!) == .openPermissionHealth,
           "parses health URL as permission health center")
    expect(AutomationURLCommand.parse(URL(string: "snapai://permission_health")!) == .openPermissionHealth,
           "normalizes underscore permission health command names")
    expect(AutomationURLCommand.parse(URL(string: "snapai://health?copy=true")!) == .copyPermissionDiagnostics,
           "health copy query reuses permission diagnostics copy command")
    expect(AutomationURLCommand.parse(URL(string: "snapai://health?summary=true")!) == .copyBriefPermissionDiagnostics,
           "health summary query reuses brief permission diagnostics command")
    expect(AutomationURLCommand.parse(URL(string: "snapai://health/recovery")!) == .copyPermissionRecoverySuggestions,
           "health recovery path reuses permission recovery suggestions command")
    expect(AutomationURLCommand.parse(URL(string: "snapai://permission_health?suggestions=true")!) == .copyPermissionRecoverySuggestions,
           "permission health suggestions query reuses permission recovery suggestions command")
    expect(AutomationURLCommand.parse(URL(string: "snapai://health/recovery?copy=false")!) == .openPermissionHealth,
           "explicit false copy query suppresses health recovery path subcommands")
    expect(AutomationURLCommand.parse(URL(string: "snapai://diagnostics")!) == .openPermissionHealth,
           "parses diagnostics URL as permission health center")
    expect(AutomationURLCommand.parse(URL(string: "snapai://diagnostics?copy=true")!) == .copyPermissionDiagnostics,
           "parses diagnostics copy URL as copy diagnostics command")
    expect(AutomationURLCommand.parse(URL(string: "snapai://diagnostics?copy")!) == .copyPermissionDiagnostics,
           "parses flag-style diagnostics copy URL")
    expect(AutomationURLCommand.parse(URL(string: "snapai://diagnostics?summary=true")!) == .copyBriefPermissionDiagnostics,
           "parses diagnostics summary query as copy brief diagnostics command")
    expect(AutomationURLCommand.parse(URL(string: "snapai://diagnostics?brief")!) == .copyBriefPermissionDiagnostics,
           "parses flag-style diagnostics brief query")
    expect(AutomationURLCommand.parse(URL(string: "snapai://diagnostics/summary")!) == .copyBriefPermissionDiagnostics,
           "parses diagnostics summary path subcommand")
    expect(AutomationURLCommand.parse(URL(string: "snapai:///diagnostics/copy_summary")!) == .copyBriefPermissionDiagnostics,
           "parses path-only diagnostics copy summary subcommand")
    expect(AutomationURLCommand.parse(URL(string: "snapai://diagnostics/copy?summary=true")!) == .copyBriefPermissionDiagnostics,
           "diagnostics summary query takes precedence over full copy path command")
    expect(AutomationURLCommand.parse(URL(string: "snapai://diagnostics/recovery")!) == .copyPermissionRecoverySuggestions,
           "parses diagnostics recovery path subcommand")
    expect(AutomationURLCommand.parse(URL(string: "snapai:///diagnostics/copy_suggestions")!) == .copyPermissionRecoverySuggestions,
           "parses path-only diagnostics copy suggestions subcommand")
    expect(AutomationURLCommand.parse(URL(string: "snapai://diagnostics?suggestions=true")!) == .copyPermissionRecoverySuggestions,
           "parses diagnostics suggestions query as copy recovery suggestions command")
    expect(AutomationURLCommand.parse(URL(string: "snapai://diagnostics/copy?fix=true")!) == .copyPermissionRecoverySuggestions,
           "diagnostics recovery query takes precedence over full copy path command")
    expect(AutomationURLCommand.parse(URL(string: "snapai://diagnostics/recovery?copy=false")!) == .openPermissionHealth,
           "explicit false copy query suppresses diagnostics recovery path subcommands")
    expect(AutomationURLCommand.parse(URL(string: "snapai://diagnostics/recovery?suggestions=false")!) == .openPermissionHealth,
           "explicit false recovery query suppresses diagnostics recovery path subcommands")
    expect(AutomationURLCommand.parse(URL(string: "snapai://diagnostics/summary?copy=false")!) == .openPermissionHealth,
           "explicit false copy query suppresses diagnostics summary path subcommands")
    expect(AutomationURLCommand.parse(URL(string: "snapai://diagnostics?summary=false&copy=true")!) == .copyPermissionDiagnostics,
           "explicit false summary query falls back to full diagnostics copy when copy is true")
    expect(AutomationURLCommand.parse(URL(string: "snapai://diagnostics/copy")!) == .copyPermissionDiagnostics,
           "parses diagnostics copy path subcommand")
    expect(AutomationURLCommand.parse(URL(string: "snapai://diagnostics/copy?copy=false")!) == .openPermissionHealth,
           "explicit false copy query suppresses diagnostics copy path subcommands")
    expect(AutomationURLCommand.parse(URL(string: "snapai://diagnostics/copy?copy=true&copy=false")!) == .openPermissionHealth,
           "explicit false diagnostics copy parameter wins over conflicting true parameters")
    expect(AutomationURLCommand.parse(URL(string: "snapai:///diagnostics/copy_diagnostics")!) == .copyPermissionDiagnostics,
           "parses path-only diagnostics copy subcommand")
    expect(AutomationURLCommand.parse(URL(string: "snapai://diagnostics?copy_diagnostics")!) == .copyPermissionDiagnostics,
           "normalizes snake_case diagnostics copy flag")
    expect(AutomationURLCommand.parse(URL(string: "snapai://install-log")!) == .revealInstallLog,
           "parses install log URL as reveal latest install log command")
    expect(AutomationURLCommand.parse(URL(string: "snapai://install-log?copy=true")!) == .copyInstallLogPath,
           "parses install log copy URL as copy install log path command")
    expect(AutomationURLCommand.parse(URL(string: "snapai://install_log?copy")!) == .copyInstallLogPath,
           "normalizes underscore install log command names")
    expect(AutomationURLCommand.parse(URL(string: "snapai://install-log?copy_path")!) == .copyInstallLogPath,
           "normalizes snake_case install log copy path flag")
    expect(AutomationURLCommand.parse(URL(string: "snapai://install-log/copy")!) == .copyInstallLogPath,
           "parses install log copy path subcommand")
    expect(AutomationURLCommand.parse(URL(string: "snapai://install-log/copy?copy=false")!) == .revealInstallLog,
           "explicit false copy query suppresses install log copy path subcommands")
    expect(AutomationURLCommand.parse(URL(string: "snapai://install-log/copy?copy_path=true&copy=false")!) == .revealInstallLog,
           "explicit false install log copy parameter wins over conflicting true parameters")
    expect(AutomationURLCommand.parse(URL(string: "snapai:///install-log/copy_path")!) == .copyInstallLogPath,
           "parses path-only install log copy path subcommand")
    expect(AutomationURLCommand.parse(URL(string: "snapai://model?provider=DeepSeek&model=deepseek-chat")!) == .switchModel(providerQuery: "DeepSeek", modelQuery: "deepseek-chat"),
           "parses model switch URL with provider and model query")
    expect(AutomationURLCommand.parse(URL(string: "snapai://model/gpt-4o-mini")!) == .switchModel(providerQuery: nil, modelQuery: "gpt-4o-mini"),
           "parses model switch URL path as model query")
    expect(AutomationURLCommand.parse(URL(string: "snapai:///model/gpt-4o-mini")!) == .switchModel(providerQuery: nil, modelQuery: "gpt-4o-mini"),
           "parses path-only model switch URL argument")
    expect(AutomationURLCommand.parse(URL(string: "snapai://model/OpenAI/gpt-4o-mini")!) == .switchModel(providerQuery: "OpenAI", modelQuery: "gpt-4o-mini"),
           "parses model switch URL provider and model from path")
    expect(AutomationURLCommand.parse(URL(string: "snapai:///model/OpenAI/gpt-4o-mini")!) == .switchModel(providerQuery: "OpenAI", modelQuery: "gpt-4o-mini"),
           "parses path-only model switch provider and model from path")
    expect(AutomationURLCommand.parse(URL(string: "snapai://model/provider/OpenAI/model/gpt-4o-mini")!) == .switchModel(providerQuery: "OpenAI", modelQuery: "gpt-4o-mini"),
           "parses labeled provider and model path values")
    expect(AutomationURLCommand.parse(URL(string: "snapai://model/model/gpt-4o-mini")!) == .switchModel(providerQuery: nil, modelQuery: "gpt-4o-mini"),
           "parses labeled model path value without provider")
    expect(AutomationURLCommand.parse(URL(string: "snapai://model/OpenAI/gpt-4o-mini?provider=DeepSeek&model=deepseek-chat")!) == .switchModel(providerQuery: "DeepSeek", modelQuery: "deepseek-chat"),
           "prefers model query parameters over provider and model path values")
    expect(AutomationURLCommand.parse(URL(string: "snapai://model/openrouter%2Fauto")!) == .switchModel(providerQuery: nil, modelQuery: "openrouter/auto"),
           "preserves encoded slash in model path argument")
    expect(AutomationURLCommand.parse(URL(string: "snapai:///model/openrouter%2Fauto")!) == .switchModel(providerQuery: nil, modelQuery: "openrouter/auto"),
           "preserves encoded slash in path-only model argument")
    expect(AutomationURLCommand.parse(URL(string: "snapai://context?name=项目A")!) == .switchContext(profileQuery: "项目A"),
           "parses context switch URL with profile query")
    expect(AutomationURLCommand.parse(URL(string: "snapai://context/项目A")!) == .switchContext(profileQuery: "项目A"),
           "parses context switch URL path as profile query")
    expect(AutomationURLCommand.parse(URL(string: "snapai:///context/%E9%A1%B9%E7%9B%AEA%2FDocs")!) == .switchContext(profileQuery: "项目A/Docs"),
           "preserves encoded slash in path-only context argument")
    expect(AutomationURLCommand.parse(URL(string: "snapai://context?copy=true")!) == .copyContext(profileQuery: nil),
           "parses context copy URL as copy active context command")
    expect(AutomationURLCommand.parse(URL(string: "snapai://context/项目A?copy=true")!) == .copyContext(profileQuery: "项目A"),
           "parses context copy URL path as profile query")
    expect(AutomationURLCommand.parse(URL(string: "snapai://context/copy")!) == .copyContext(profileQuery: nil),
           "parses context copy path subcommand")
    expect(AutomationURLCommand.parse(URL(string: "snapai://context/copy?copy=false")!) == .switchContext(profileQuery: "copy"),
           "explicit false copy query suppresses context copy path subcommands")
    expect(AutomationURLCommand.parse(URL(string: "snapai://context/copy?copy=true&export=off")!) == .switchContext(profileQuery: "copy"),
           "explicit false-equivalent context copy parameter wins over conflicting true parameters")
    expect(AutomationURLCommand.parse(URL(string: "snapai:///context/copy/%E9%A1%B9%E7%9B%AEA%2FDocs")!) == .copyContext(profileQuery: "项目A/Docs"),
           "parses path-only context copy subcommand with profile argument")
    expect(AutomationURLCommand.parse(URL(string: "snapai://context/copy?name=%E9%A1%B9%E7%9B%AEA")!) == .copyContext(profileQuery: "项目A"),
           "context copy query profile takes precedence over copy path command")
    expect(AutomationURLCommand.parse(URL(string: "snapai://context/effective?copy=true")!) == .copyEffectiveSystemPrompt,
           "parses context effective path as copy effective system prompt")
    expect(AutomationURLCommand.parse(URL(string: "snapai://context/effective?copy=false")!) == .switchContext(profileQuery: "effective"),
           "explicit false copy query suppresses context effective path subcommands")
    expect(AutomationURLCommand.parse(URL(string: "snapai://context?effective_prompt=true")!) == .copyEffectiveSystemPrompt,
           "parses context effective prompt flag as copy effective system prompt")
    expect(AutomationURLCommand.parse(URL(string: "snapai://context/effective?export=off")!) == .switchContext(profileQuery: "effective"),
           "explicit off export query suppresses context effective export path subcommands")
    expect(AutomationURLCommand.parse(URL(string: "snapai://context/status?copy=true")!) == .copyContextStatus,
           "parses context status path as copy context status")
    expect(AutomationURLCommand.parse(URL(string: "snapai://context/status?copy=false")!) == .switchContext(profileQuery: "status"),
           "explicit false copy query suppresses context status path subcommands")
    expect(AutomationURLCommand.parse(URL(string: "snapai://context/status?status=true&copy=false")!) == .switchContext(profileQuery: "status"),
           "explicit false copy parameter wins over conflicting context status true parameters")
    expect(AutomationURLCommand.parse(URL(string: "snapai://context/status?status=false")!) == .switchContext(profileQuery: "status"),
           "explicit false status query suppresses context status path subcommands")
    expect(AutomationURLCommand.parse(URL(string: "snapai://context/status?markdown=false")!) == .switchContext(profileQuery: "status"),
           "explicit false markdown query suppresses context status markdown path subcommands")
    expect(AutomationURLCommand.parse(URL(string: "snapai://context?diagnostics=true")!) == .copyContextStatus,
           "parses context diagnostics flag as copy context status")
    expect(AutomationURLCommand.parse(URL(string: "snapai://prompt?copy=true")!) == .copyEffectiveSystemPrompt,
           "parses prompt copy URL as copy effective system prompt")
    expect(AutomationURLCommand.parse(URL(string: "snapai://prompt?copy=true&copy=false")!) == .openQuickInput(text: nil, actionQuery: nil),
           "explicit false prompt copy parameter wins over conflicting true parameters")
    expect(AutomationURLCommand.parse(URL(string: "snapai:///system-prompt/copy")!) == .copyEffectiveSystemPrompt,
           "parses path-only system-prompt copy URL")
    expect(AutomationURLCommand.parse(URL(string: "snapai:///system-prompt/copy?copy=false")!) == .openSettings(section: "general"),
           "explicit false copy query suppresses system-prompt copy path subcommands")
    expect(AutomationURLCommand.parse(URL(string: "snapai://effective-prompt?export=off")!) == .openSettings(section: "general"),
           "explicit off export query suppresses effective-prompt copy commands")
    expect(AutomationURLCommand.parse(URL(string: "snapai://context?clear=true")!) == .clearContext,
           "parses context clear URL as clear context command")
    expect(AutomationURLCommand.parse(URL(string: "snapai://context?clear")!) == .clearContext,
           "parses flag-style context clear URL")
    expect(AutomationURLCommand.parse(URL(string: "snapai://context/clear")!) == .clearContext,
           "parses context clear path subcommand")
    expect(AutomationURLCommand.parse(URL(string: "snapai://context/clear?clear=false")!) == .switchContext(profileQuery: "clear"),
           "explicit false clear query suppresses context clear path subcommands")
    expect(AutomationURLCommand.parse(URL(string: "snapai:///context/disable")!) == .clearContext,
           "parses path-only context disable subcommand")
    expect(AutomationURLCommand.parse(URL(string: "snapai://context/项目A?clear=true")!) == .clearContext,
           "context clear query takes precedence over path profile")
    expect(AutomationURLCommand.parse(URL(string: "snapai://context/copy?clear=true")!) == .clearContext,
           "context clear query takes precedence over copy path command")
    expect(AutomationURLCommand.parse(URL(string: "snapai://context/status?clear=true")!) == .clearContext,
           "context clear query takes precedence over status path command")
    expect(AutomationURLCommand.parse(URL(string: "snapai://context/clear?name=clear")!) == .switchContext(profileQuery: "clear"),
           "explicit context query can still select a profile named clear")
    expect(AutomationURLCommand.parse(URL(string: "snapai://toggle/privacy-preview?enabled=true")!) == .setToggle(commandQuery: "privacy-preview", enabled: true),
           "parses toggle URL path with explicit enabled value")
    expect(AutomationURLCommand.parse(URL(string: "snapai:///toggle/privacy-preview?enabled=true")!) == .setToggle(commandQuery: "privacy-preview", enabled: true),
           "parses path-only toggle URL argument")
    expect(AutomationURLCommand.parse(URL(string: "snapai://toggle/privacy-preview/on")!) == .setToggle(commandQuery: "privacy-preview", enabled: true),
           "parses toggle path state as enabled value")
    expect(AutomationURLCommand.parse(URL(string: "snapai:///toggle/fallback/off")!) == .setToggle(commandQuery: "fallback", enabled: false),
           "parses path-only toggle path state as disabled value")
    expect(AutomationURLCommand.parse(URL(string: "snapai://toggle/privacy-preview/off?enabled=true")!) == .setToggle(commandQuery: "privacy-preview", enabled: true),
           "prefers toggle query enabled value over path state")
    expect(AutomationURLCommand.parse(URL(string: "snapai://toggle/privacy-preview?enabled=启用")!) == .setToggle(commandQuery: "privacy-preview", enabled: true),
           "parses Chinese enabled boolean aliases")
    expect(AutomationURLCommand.parse(URL(string: "snapai://toggle/privacy-preview?enabled")!) == .setToggle(commandQuery: "privacy-preview", enabled: true),
           "parses flag-style toggle enabled URL")
    expect(AutomationURLCommand.parse(URL(string: "snapai://toggle?name=fallback&enabled=false")!) == .setToggle(commandQuery: "fallback", enabled: false),
           "parses toggle URL query with explicit disabled value")
    expect(AutomationURLCommand.parse(URL(string: "snapai://toggle?name=fallback&enabled=禁用")!) == .setToggle(commandQuery: "fallback", enabled: false),
           "parses Chinese disabled boolean aliases")
    expect(AutomationURLCommand.parse(URL(string: "snapai://toggle/redaction")!) == .setToggle(commandQuery: "redaction", enabled: nil),
           "parses toggle URL without enabled value as toggle intent")
    expect(AutomationURLCommand.parse(URL(string: "snapai://toggle/history-metadata/on")!) == .setToggle(commandQuery: "history-metadata", enabled: true),
           "parses history metadata-only toggle URL path state")
    expect(AutomationURLCommand.parse(URL(string: "snapai://routing?preference=quality")!) == .setRoutingPreference(.quality),
           "parses routing preference URL query")
    expect(AutomationURLCommand.parse(URL(string: "snapai://routing/fastest")!) == .setRoutingPreference(.fastest),
           "parses routing preference URL path")
    expect(AutomationURLCommand.parse(URL(string: "snapai:///routing/fastest")!) == .setRoutingPreference(.fastest),
           "parses path-only routing preference URL argument")
    expect(AutomationURLCommand.parse(URL(string: "snapai://routing/preference/quality")!) == .setRoutingPreference(.quality),
           "parses labeled routing preference path value")
    expect(AutomationURLCommand.parse(URL(string: "snapai:///routing/mode/speed-first")!) == .setRoutingPreference(.fastest),
           "parses path-only labeled routing preference path value")
    expect(AutomationURLCommand.parse(URL(string: "snapai://routing/preference/quality?preference=balanced")!) == .setRoutingPreference(.balanced),
           "prefers routing query value over labeled path value")
    expect(AutomationURLCommand.parse(URL(string: "snapai://routing/unknown")!) == .setRoutingPreference(nil),
           "keeps invalid routing preference as nil for AppDelegate fallback")
    expect(AutomationURLCommand.parse(URL(string: "snapai://work-mode?mode=privacy")!) == .setWorkMode(.privacy),
           "parses work mode URL query")
    expect(AutomationURLCommand.parse(URL(string: "snapai://work-mode/quality")!) == .setWorkMode(.quality),
           "parses work mode URL path")
    expect(AutomationURLCommand.parse(URL(string: "snapai:///work-mode/speed")!) == .setWorkMode(.speed),
           "parses path-only work mode URL argument")
    expect(AutomationURLCommand.parse(URL(string: "snapai://work-mode/preset/standard")!) == .setWorkMode(.standard),
           "parses labeled work mode path value")
    expect(AutomationURLCommand.parse(URL(string: "snapai:///workflow-mode/mode/best_quality")!) == .setWorkMode(.quality),
           "parses path-only labeled work mode path value")
    expect(AutomationURLCommand.parse(URL(string: "snapai://work-mode/privacy?mode=speed")!) == .setWorkMode(.speed),
           "prefers work mode query value over path value")
    expect(AutomationURLCommand.parse(URL(string: "snapai://work-mode/unknown")!) == .setWorkMode(nil),
           "keeps invalid work mode as nil for AppDelegate fallback")
    expect(AutomationURLCommand.parse(URL(string: "snapai://dock?enabled=false")!) == .setDockIcon(false),
           "parses dock icon visibility URL")
    expect(AutomationURLCommand.parse(URL(string: "snapai://dock?enabled=否")!) == .setDockIcon(false),
           "parses no-style Chinese dock boolean alias")
    expect(AutomationURLCommand.parse(URL(string: "snapai://dock/hide")!) == .setDockIcon(false),
           "parses dock hide path state")
    expect(AutomationURLCommand.parse(URL(string: "snapai:///dock/show")!) == .setDockIcon(true),
           "parses path-only dock show path state")
    expect(AutomationURLCommand.parse(URL(string: "snapai://login-item?enabled=true")!) == .setLoginItem(true),
           "parses login item URL")
    expect(AutomationURLCommand.parse(URL(string: "snapai://login-item?enabled=真")!) == .setLoginItem(true),
           "parses true-style Chinese login item boolean alias")
    expect(AutomationURLCommand.parse(URL(string: "snapai://login-item/enable")!) == .setLoginItem(true),
           "parses login item enable path state")
    expect(AutomationURLCommand.parse(URL(string: "snapai:///login-item/disable")!) == .setLoginItem(false),
           "parses path-only login item disable path state")
    expect(AutomationURLCommand.parse(URL(string: "snapai://typewriter?speed=off")!) == .setTypewriterSpeed(.off),
           "parses typewriter speed query")
    expect(AutomationURLCommand.parse(URL(string: "snapai://typewriter/fast")!) == .setTypewriterSpeed(.fast),
           "parses typewriter speed path")
    expect(AutomationURLCommand.parse(URL(string: "snapai:///typewriter/fast")!) == .setTypewriterSpeed(.fast),
           "parses path-only typewriter speed argument")
    expect(AutomationURLCommand.parse(URL(string: "snapai://typewriter/speed/normal")!) == .setTypewriterSpeed(.normal),
           "parses labeled typewriter speed path value")
    expect(AutomationURLCommand.parse(URL(string: "snapai:///typewriter/mode/standard_speed")!) == .setTypewriterSpeed(.normal),
           "parses path-only labeled typewriter speed path value")
    expect(AutomationURLCommand.parse(URL(string: "snapai://typewriter/speed/fast?speed=off")!) == .setTypewriterSpeed(.off),
           "prefers typewriter query speed over labeled path value")
    expect(AutomationURLCommand.parse(URL(string: "snapai://typewriter/unknown")!) == .setTypewriterSpeed(nil),
           "keeps invalid typewriter speed as nil for AppDelegate fallback")
    expect(AutomationURLCommand.parse(URL(string: "snapai://command_palette")!) == .openCommandPalette,
           "normalizes underscore command palette command names")
    expect(AutomationURLCommand.parse(URL(string: "snapai:///command%20palette")!) == .openCommandPalette,
           "normalizes encoded-space command palette path names")
    expect(AutomationURLCommand.parse(URL(string: "snapai://check_updates")!) == .checkUpdates,
           "normalizes underscore check updates command names")

    let emptyRun = snapAIURL(host: "run", queryItems: [
        URLQueryItem(name: "action", value: "总结"),
        URLQueryItem(name: "text", value: "  \n")
    ])
    expect(AutomationURLCommand.parse(emptyRun) == .openQuickInput(text: nil, actionQuery: "总结"),
           "empty run text opens quick input with requested action instead of dispatching an empty request")

    let blankControls = snapAIURL(host: "run", queryItems: [
        URLQueryItem(name: "action", value: "  "),
        URLQueryItem(name: "provider", value: ""),
        URLQueryItem(name: "model", value: " \n "),
        URLQueryItem(name: "text", value: "hello")
    ])
    expect(AutomationURLCommand.parse(blankControls) == .run(actionQuery: nil,
                                                             text: "hello",
                                                             options: .empty),
           "normalizes blank control parameters without trimming payload text")

    expect(AutomationURLCommand.parse(URL(string: "https://example.com")!) == nil,
           "rejects non-SnapAI schemes")
}

func testAutomationRunOptionsApplyToActionWithoutChangingSettings() {
    let settings = AppSettings()
    var openAI = AIProvider(name: "Open AI", apiProtocol: .openAI,
                            baseURL: "https://openai.test/v1",
                            apiKey: "key",
                            models: [
                                AIModelEntry(name: "gpt-4o-mini"),
                                AIModelEntry(name: "disabled-model", enabled: false)
                            ])
    var deepSeek = AIProvider(name: "DeepSeek", apiProtocol: .openAI,
                              baseURL: "https://deepseek.test/v1",
                              apiKey: "key",
                              models: [AIModelEntry(name: "deepseek-chat")])
    openAI.isEnabled = true
    deepSeek.isEnabled = true
    settings.providers = [openAI, deepSeek]
    settings.activeProviderID = openAI.id
    settings.activeModel = "gpt-4o-mini"

    var action = AIAction.defaults()[0]
    action.saveHistory = true

    let overridden = action.applyingAutomationOptions(
        AutomationRunOptions(providerQuery: "DeepSeek",
                             modelQuery: "deepseek-chat",
                             saveHistory: false,
                             targetLanguage: .japanese,
                             replaceByDefault: true),
        settings: settings
    )
    expect(overridden.providerID == deepSeek.id, "automation provider option resolves by provider name")
    expect(overridden.modelOverride == "deepseek-chat", "automation model option resolves enabled model")
    expect(overridden.saveHistory == false, "automation saveHistory option overrides action history behavior")
    expect(overridden.isTranslation && overridden.targetLanguage == .japanese,
           "automation language option sets a one-shot translation target")
    expect(overridden.replaceByDefault, "automation replace option overrides default replacement confirmation flag")
    expect(action.providerID == nil &&
           action.modelOverride == nil &&
           action.saveHistory == true &&
           action.targetLanguage == .auto &&
           action.replaceByDefault == false,
           "automation options do not mutate the source action")
    expect(settings.activeProviderID == openAI.id && settings.activeModel == "gpt-4o-mini",
           "automation options do not mutate global active model settings")

    let disabledModel = action.applyingAutomationOptions(
        AutomationRunOptions(providerQuery: "Open AI",
                             modelQuery: "disabled-model",
                             saveHistory: nil),
        settings: settings
    )
    expect(disabledModel.providerID == openAI.id, "automation can still choose the requested provider")
    expect(disabledModel.modelOverride == nil, "automation ignores disabled model overrides")

    let modelOnly = action.applyingAutomationOptions(
        AutomationRunOptions(providerQuery: nil,
                             modelQuery: "deepseek-chat",
                             saveHistory: nil),
        settings: settings
    )
    expect(modelOnly.providerID == deepSeek.id && modelOnly.modelOverride == "deepseek-chat",
           "automation can infer provider from model when provider is omitted")

    let normalizedLookup = action.applyingAutomationOptions(
        AutomationRunOptions(providerQuery: "openai",
                             modelQuery: "gpt4omini",
                             saveHistory: nil),
        settings: settings
    )
    expect(normalizedLookup.providerID == openAI.id && normalizedLookup.modelOverride == "gpt-4o-mini",
           "automation options normalize provider and model lookup separators")

    let invalidProvider = action.applyingAutomationOptions(
        AutomationRunOptions(providerQuery: "MissingProvider",
                             modelQuery: "deepseek-chat",
                             saveHistory: nil),
        settings: settings
    )
    expect(invalidProvider.providerID == nil && invalidProvider.modelOverride == nil,
           "automation does not infer provider from model when an explicit provider query is invalid")
}

func testAutomationModelSelectionResolvesEnabledModelsOnly() {
    let settings = AppSettings()
    var openAI = AIProvider(name: "Open AI", apiProtocol: .openAI,
                            baseURL: "https://openai.test/v1",
                            apiKey: "key",
                            models: [
                                AIModelEntry(name: "gpt-4o-mini"),
                                AIModelEntry(name: "disabled-model", enabled: false)
                            ])
    var deepSeek = AIProvider(name: "DeepSeek", apiProtocol: .openAI,
                              baseURL: "https://deepseek.test/v1",
                              apiKey: "key",
                              models: [AIModelEntry(name: "deepseek-chat")])
    openAI.isEnabled = true
    deepSeek.isEnabled = true
    settings.providers = [openAI, deepSeek]

    let explicit = AutomationModelSelection.resolve(providerQuery: "DeepSeek",
                                                    modelQuery: "deepseek-chat",
                                                    settings: settings)
    expect(explicit == AutomationModelSelection(providerID: deepSeek.id, modelName: "deepseek-chat"),
           "model selection resolves explicit provider and enabled model")

    let modelOnly = AutomationModelSelection.resolve(providerQuery: nil,
                                                     modelQuery: "deepseek-chat",
                                                     settings: settings)
    expect(modelOnly == AutomationModelSelection(providerID: deepSeek.id, modelName: "deepseek-chat"),
           "model selection can infer provider from model when provider is omitted")

    let normalized = AutomationModelSelection.resolve(providerQuery: "openai",
                                                      modelQuery: "gpt4omini",
                                                      settings: settings)
    expect(normalized == AutomationModelSelection(providerID: openAI.id, modelName: "gpt-4o-mini"),
           "model selection normalizes provider and model separators")

    let normalizedModelOnly = AutomationModelSelection.resolve(providerQuery: nil,
                                                               modelQuery: "deepseekchat",
                                                               settings: settings)
    expect(normalizedModelOnly == AutomationModelSelection(providerID: deepSeek.id, modelName: "deepseek-chat"),
           "model selection can infer provider from normalized model query")

    expect(AutomationModelSelection.resolve(providerQuery: "MissingProvider",
                                            modelQuery: "deepseek-chat",
                                            settings: settings) == nil,
           "model selection does not infer provider when explicit provider is invalid")
    expect(AutomationModelSelection.resolve(providerQuery: "OpenAI",
                                            modelQuery: "disabled-model",
                                            settings: settings) == nil,
           "model selection rejects disabled models")
    expect(AutomationModelSelection.resolve(providerQuery: nil,
                                            modelQuery: nil,
                                            settings: settings) == nil,
           "model selection requires a model query")
}

func testAutomationContextSelectionRequiresEnabledNonEmptyProfile() {
    let settings = AppSettings()
    let enabled = ContextProfile(id: "project-a",
                                 name: "项目A",
                                 content: "术语: SnapAI",
                                 isEnabled: true)
    let spacedName = ContextProfile(id: "project-docs",
                                    name: "项目 A Docs",
                                    content: "文档上下文",
                                    isEnabled: true)
    let disabled = ContextProfile(id: "project-b",
                                  name: "项目B",
                                  content: "禁用内容",
                                  isEnabled: false)
    let empty = ContextProfile(id: "project-c",
                               name: "项目C",
                               content: " \n ",
                               isEnabled: true)
    settings.contextProfiles = [enabled, spacedName, disabled, empty]

    expect(AutomationContextSelection.resolve(profileQuery: "项目A", settings: settings) == AutomationContextSelection(profileID: "project-a"),
           "context selection resolves enabled non-empty profile by name")
    expect(AutomationContextSelection.resolve(profileQuery: "project-a", settings: settings) == AutomationContextSelection(profileID: "project-a"),
           "context selection resolves enabled non-empty profile by id")
    expect(AutomationContextSelection.resolve(profileQuery: "project_docs", settings: settings) == AutomationContextSelection(profileID: "project-docs"),
           "context selection normalizes profile id separators")
    expect(AutomationContextSelection.resolve(profileQuery: "项目ADocs", settings: settings) == AutomationContextSelection(profileID: "project-docs"),
           "context selection normalizes profile name whitespace")
    expect(AutomationContextSelection.resolve(profileQuery: "项目B", settings: settings) == nil,
           "context selection rejects disabled profiles")
    expect(AutomationContextSelection.resolve(profileQuery: "项目C", settings: settings) == nil,
           "context selection rejects empty profiles that would not affect prompts")
    expect(AutomationContextSelection.resolve(profileQuery: nil, settings: settings) == nil,
           "context selection requires a profile query")
}

func testAutomationContextClearRestoresBasePrompt() {
    let settings = AppSettings()
    let profile = ContextProfile(id: "project-a",
                                 name: "项目A",
                                 content: "术语: SnapAI",
                                 isEnabled: true)
    settings.systemPrompt = "基础提示"
    settings.contextProfiles = [profile]
    settings.activeContextProfileID = profile.id
    expect(settings.effectiveSystemPrompt.contains("术语"), "fixture starts with active context")

    settings.activeContextProfileID = ""
    expect(settings.effectiveSystemPrompt == "基础提示",
           "clearing active context restores the base system prompt")
}

func testAutomationRoutingPreferenceSelectionResolvesAliases() {
    expect(AutomationRoutingPreferenceSelection.resolve("fast") == .fastest,
           "resolves fast alias")
    expect(AutomationRoutingPreferenceSelection.resolve("balanced") == .balanced,
           "resolves balanced alias")
    expect(AutomationRoutingPreferenceSelection.resolve("quality") == .quality,
           "resolves quality alias")
    expect(AutomationRoutingPreferenceSelection.resolve("speed first") == .fastest,
           "resolves spaced speed-first alias")
    expect(AutomationRoutingPreferenceSelection.resolve("best_quality") == .quality,
           "resolves underscore best-quality alias")
    expect(AutomationRoutingPreferenceSelection.resolve("best-quality") == .quality,
           "resolves hyphenated best-quality alias")
    expect(AutomationRoutingPreferenceSelection.resolve("最快") == .fastest,
           "resolves Chinese fast alias")
    expect(AutomationRoutingPreferenceSelection.resolve("最佳质量") == .quality,
           "resolves Chinese quality alias")
    expect(AutomationRoutingPreferenceSelection.resolve("missing") == nil,
           "rejects unknown routing preference")
    expect(AutomationRoutingPreferenceSelection.resolve(nil) == nil,
           "requires a routing preference query")
}

func testAutomationWorkModeSelectionResolvesAliases() {
    expect(AutomationWorkModeSelection.resolve("standard") == .standard,
           "resolves standard work mode")
    expect(AutomationWorkModeSelection.resolve("default") == .standard,
           "resolves default work mode alias")
    expect(AutomationWorkModeSelection.resolve("隐私") == .privacy,
           "resolves Chinese privacy work mode")
    expect(AutomationWorkModeSelection.resolve("private") == .privacy,
           "resolves private work mode alias")
    expect(AutomationWorkModeSelection.resolve("fastest") == .speed,
           "resolves fastest work mode alias")
    expect(AutomationWorkModeSelection.resolve("极速") == .speed,
           "resolves Chinese speed work mode")
    expect(AutomationWorkModeSelection.resolve("best_quality") == .quality,
           "resolves underscore quality work mode alias")
    expect(AutomationWorkModeSelection.resolve("质量模式") == .quality,
           "resolves full Chinese quality work mode title")
    expect(AutomationWorkModeSelection.resolve("missing") == nil,
           "rejects unknown work mode")
    expect(AutomationWorkModeSelection.resolve(nil) == nil,
           "requires a work mode query")
}

func testAutomationTypewriterSpeedSelectionResolvesAliases() {
    expect(AutomationTypewriterSpeedSelection.resolve("off") == .off,
           "resolves off typewriter speed")
    expect(AutomationTypewriterSpeedSelection.resolve("standard speed") == .normal,
           "resolves spaced standard speed alias")
    expect(AutomationTypewriterSpeedSelection.resolve("standard_speed") == .normal,
           "resolves underscore standard speed alias")
    expect(AutomationTypewriterSpeedSelection.resolve("normal") == .normal,
           "resolves normal typewriter speed")
    expect(AutomationTypewriterSpeedSelection.resolve("faster") == .fast,
           "resolves faster typewriter speed")
    expect(AutomationTypewriterSpeedSelection.resolve("2") == .normal,
           "resolves numeric typewriter speed alias")
    expect(AutomationTypewriterSpeedSelection.resolve("missing") == nil,
           "rejects unknown typewriter speed")
    expect(AutomationTypewriterSpeedSelection.resolve(nil) == nil,
           "requires a typewriter speed query")
}

func testWorkModeCommandFactoryReflectsCurrentState() {
    let descriptors = WorkModeCommandFactory.descriptors(modes: workModeCommandInputs(currentID: "privacy"))
    expect(descriptors.count == workModeCommandInputs(currentID: "privacy").count,
           "work mode command factory exposes every preset")
    expect(descriptors.map(\.id).count == Set(descriptors.map(\.id)).count,
           "work mode command ids are unique")
    expect(descriptors.first(where: { $0.action == .apply("privacy") })?.subtitle.hasPrefix("当前 - ") == true,
           "work mode command marks the current preset")
    expect(descriptors.first(where: { $0.action == .apply("speed") })?.keywords.contains("低延迟") == true,
           "work mode command keywords include preset intent")
    expect(descriptors.first(where: { $0.action == .apply("quality") })?.title == "切换到质量模式",
           "work mode command titles are user-facing")
}

private func workModeCommandInputs(currentID: String) -> [WorkModeCommandInput] {
    [
        WorkModeCommandInput(id: "standard",
                             title: "标准模式",
                             shortTitle: "标准",
                             summary: "平衡日常效率与完整历史记录。",
                             systemImage: "slider.horizontal.3",
                             keywords: "work mode standard default balanced settings 模式 标准 默认 均衡",
                             isCurrent: currentID == "standard"),
        WorkModeCommandInput(id: "privacy",
                             title: "隐私模式",
                             shortTitle: "隐私",
                             summary: "发送前确认、本地脱敏,历史仅保存元信息。",
                             systemImage: "hand.raised",
                             keywords: "work mode privacy preview redaction metadata history safe 隐私 预览 脱敏 元信息",
                             isCurrent: currentID == "privacy"),
        WorkModeCommandInput(id: "speed",
                             title: "极速模式",
                             shortTitle: "极速",
                             summary: "自动路由到低延迟模型,减少确认步骤。",
                             systemImage: "bolt",
                             keywords: "work mode speed fastest route low latency quick 极速 快速 路由 低延迟",
                             isCurrent: currentID == "speed"),
        WorkModeCommandInput(id: "quality",
                             title: "质量模式",
                             shortTitle: "质量",
                             summary: "自动路由并优先质量,适合长文和复杂任务。",
                             systemImage: "sparkles",
                             keywords: "work mode quality best route reasoning long context 质量 最佳 长文 推理",
                             isCurrent: currentID == "quality")
    ]
}

func testSettingsToggleCommandReflectsCurrentState() {
    let state = SettingsToggleCommandState(privacyPreviewEnabled: false,
                                           redactionEnabled: true,
                                           historyMetadataOnly: false,
                                           autoRouteEnabled: false,
                                           fallbackEnabled: true)

    expect(SettingsToggleCommand.privacyPreview.title(isEnabled: SettingsToggleCommand.privacyPreview.isEnabled(in: state)) == "开启发送前预览",
           "privacy preview command opens disabled feature")
    expect(SettingsToggleCommand.redaction.title(isEnabled: SettingsToggleCommand.redaction.isEnabled(in: state)) == "关闭本地脱敏",
           "redaction command closes enabled feature")
    expect(SettingsToggleCommand.historyMetadataOnly.title(isEnabled: SettingsToggleCommand.historyMetadataOnly.isEnabled(in: state)) == "开启历史仅元信息",
           "history metadata command opens full history storage")
    expect(SettingsToggleCommand.autoRoute.subtitle(isEnabled: SettingsToggleCommand.autoRoute.isEnabled(in: state)).contains("当前已关闭"),
           "auto route subtitle reflects disabled state")
    expect(SettingsToggleCommand.fallback.subtitle(isEnabled: SettingsToggleCommand.fallback.isEnabled(in: state)).contains("当前已开启"),
           "fallback subtitle reflects enabled state")
    expect(SettingsToggleCommand.allCases.map(\.id).count == Set(SettingsToggleCommand.allCases.map(\.id)).count,
           "toggle commands use unique ids")
}

func testSettingsToggleCommandResolvesAliasesAndSetsState() {
    var state = SettingsToggleCommandState(privacyPreviewEnabled: false,
                                           redactionEnabled: false,
                                           historyMetadataOnly: false,
                                           autoRouteEnabled: false,
                                           fallbackEnabled: true)

    expect(SettingsToggleCommand.resolve("privacy-preview") == .privacyPreview,
           "resolves privacy preview alias")
    expect(SettingsToggleCommand.resolve("privacy_preview") == .privacyPreview,
           "resolves underscore privacy preview alias")
    expect(SettingsToggleCommand.resolve("toggle_privacy_preview") == .privacyPreview,
           "resolves underscore stable privacy preview id")
    expect(SettingsToggleCommand.resolve("脱敏") == .redaction,
           "resolves redaction Chinese alias")
    expect(SettingsToggleCommand.resolve("local redaction") == .redaction,
           "resolves spaced local redaction alias")
    expect(SettingsToggleCommand.resolve("history metadata") == .historyMetadataOnly,
           "resolves spaced history metadata alias")
    expect(SettingsToggleCommand.resolve("toggle_history_metadata") == .historyMetadataOnly,
           "resolves underscore stable history metadata id")
    expect(SettingsToggleCommand.resolve("仅元信息") == .historyMetadataOnly,
           "resolves Chinese metadata-only history alias")
    expect(SettingsToggleCommand.resolve("route") == .autoRoute,
           "resolves auto route alias")
    expect(SettingsToggleCommand.resolve("auto route") == .autoRoute,
           "resolves spaced auto route alias")
    expect(SettingsToggleCommand.resolve("toggle_auto_route") == .autoRoute,
           "resolves underscore stable auto route id")
    expect(SettingsToggleCommand.resolve("failover") == .fallback,
           "resolves fallback alias")
    expect(SettingsToggleCommand.resolve("fail over") == .fallback,
           "resolves spaced fallback alias")
    expect(SettingsToggleCommand.resolve("backup_model") == .fallback,
           "resolves underscore backup model alias")
    expect(SettingsToggleCommand.resolve("missing") == nil,
           "rejects unknown toggle command")

    state = SettingsToggleCommand.privacyPreview.settingEnabled(true, in: state)
    state = SettingsToggleCommand.redaction.settingEnabled(true, in: state)
    state = SettingsToggleCommand.historyMetadataOnly.settingEnabled(true, in: state)
    state = SettingsToggleCommand.autoRoute.settingEnabled(true, in: state)
    state = SettingsToggleCommand.fallback.settingEnabled(false, in: state)

    expect(state.privacyPreviewEnabled, "sets privacy preview state")
    expect(state.redactionEnabled, "sets redaction state")
    expect(state.historyMetadataOnly, "sets history metadata-only state")
    expect(state.autoRouteEnabled, "sets auto route state")
    expect(!state.fallbackEnabled, "sets fallback state")

    state = SettingsToggleCommand.historyMetadataOnly.settingEnabled(false, in: state)
    expect(!state.historyMetadataOnly, "restores full history storage state")
}

func testSettingsWindowPinCommandReflectsCurrentState() {
    let state = SettingsWindowPinState()
    expect(!state.isPinned, "settings window pin state defaults to unpinned")
    state.isPinned = true
    expect(state.isPinned, "settings window pin state updates immediately for SwiftUI")

    expect(SettingsWindowPinCommand.title(isPinned: false) == "置顶设置窗口",
           "unpinned settings window command pins the window")
    expect(SettingsWindowPinCommand.subtitle(isPinned: false).contains("保持在其他窗口上方"),
           "unpinned settings window subtitle explains pin behavior")
    expect(SettingsWindowPinCommand.systemImage(isPinned: false) == "pin.fill",
           "unpinned settings window command uses filled pin")
    expect(SettingsWindowPinCommand.statusSystemImage(isPinned: false) == "pin",
           "unpinned settings window status uses outline pin")
    expect(SettingsWindowPinCommand.accessibilityValue(isPinned: false) == "未置顶",
           "unpinned settings window status has an explicit accessibility value")

    expect(SettingsWindowPinCommand.title(isPinned: true) == "取消置顶设置窗口",
           "pinned settings window command unpins the window")
    expect(SettingsWindowPinCommand.subtitle(isPinned: true).contains("当前设置窗口"),
           "pinned settings window subtitle explains current state")
    expect(SettingsWindowPinCommand.systemImage(isPinned: true) == "pin.slash",
           "pinned settings window command uses slash pin")
    expect(SettingsWindowPinCommand.statusSystemImage(isPinned: true) == "pin.fill",
           "pinned settings window status uses filled pin")
    expect(SettingsWindowPinCommand.accessibilityValue(isPinned: true) == "已置顶",
           "pinned settings window status has an explicit accessibility value")
    expect(SettingsWindowPinCommand.keywords.contains("置顶"), "pin command is searchable in Chinese")
}

func testResultPinCommandReflectsCurrentState() {
    expect(ResultPinCommand.title(isPinned: false) == "固定结果窗",
           "unpinned result window command pins the result panel")
    expect(ResultPinCommand.subtitle(isPinned: false).contains("继续追问"),
           "unpinned result window subtitle explains follow-up behavior")
    expect(ResultPinCommand.systemImage(isPinned: false) == "pin.fill",
           "unpinned result window command uses filled pin")

    expect(ResultPinCommand.title(isPinned: true) == "取消固定结果窗",
           "pinned result window command unpins the result panel")
    expect(ResultPinCommand.subtitle(isPinned: true).contains("保持打开"),
           "pinned result window subtitle explains current state")
    expect(ResultPinCommand.systemImage(isPinned: true) == "pin.slash",
           "pinned result window command uses slash pin")
    expect(ResultPinCommand.statusTitle == "已固定",
           "pinned result window status badge has stable title")
    expect(ResultPinCommand.statusSystemImage == "pin.fill",
           "pinned result window status badge uses filled pin")
    expect(ResultPinCommand.keywords.contains("结果"), "result pin command is searchable in Chinese")
    expect(ResultPinCommand.keyEquivalent == "p", "result pin command keeps p shortcut")
    expect(ResultPinCommand.modifiers == [.command, .shift],
           "result pin command keeps command-shift shortcut")
    expect(ResultPinCommand.shortcutText == "⌘⇧P", "result pin command exposes display shortcut")
}

func testDisplayBehaviorCommandFactoryReflectsCurrentState() {
    let descriptors = DisplayBehaviorCommandFactory.descriptors(showDockIcon: true,
                                                                loginItemEnabled: false,
                                                                typewriterSpeeds: typewriterSpeedCommandInputs(currentID: "标准"))

    expect(descriptors.count == 2 + typewriterSpeedCommandInputs(currentID: "标准").count,
           "display behavior commands include dock, login item, and typewriter speeds")
    expect(descriptors[0].id == "dock-icon-toggle", "dock command is first")
    expect(descriptors[0].title == "隐藏 Dock 图标", "dock command reflects visible state")
    expect(descriptors[0].action == .setDockIcon(false), "dock command toggles off")
    expect(descriptors[1].title == "开启开机启动", "login item command reflects disabled state")
    expect(descriptors[1].action == .setLoginItem(true), "login item command toggles on")

    guard let currentSpeed = descriptors.first(where: { $0.action == .setTypewriterSpeed("标准") }),
          let fastSpeed = descriptors.first(where: { $0.action == .setTypewriterSpeed("快") }) else {
        expect(false, "typewriter speed commands exist")
        return
    }
    expect(currentSpeed.subtitle == "当前速度", "current typewriter speed is marked")
    expect(currentSpeed.systemImage == "checkmark.circle.fill", "current typewriter speed uses check icon")
    expect(fastSpeed.subtitle == "更快地显示流式结果", "non-current speed explains behavior")
    expect(fastSpeed.systemImage == "text.cursor", "non-current speed uses text cursor icon")
}

private func typewriterSpeedCommandInputs(currentID: String) -> [TypewriterSpeedCommandInput] {
    [
        TypewriterSpeedCommandInput(id: "关闭", title: "关闭", isCurrent: currentID == "关闭"),
        TypewriterSpeedCommandInput(id: "慢", title: "慢", isCurrent: currentID == "慢"),
        TypewriterSpeedCommandInput(id: "标准", title: "标准", isCurrent: currentID == "标准"),
        TypewriterSpeedCommandInput(id: "快", title: "快", isCurrent: currentID == "快")
    ]
}

func testRoutingContextCommandFactoryReflectsCurrentState() {
    let routing = RoutingContextCommandFactory.routingDescriptors(preferences: routingPreferenceInputs(currentID: "最佳质量"))
    expect(routing.count == routingPreferenceInputs(currentID: "最佳质量").count,
           "routing command includes all preferences")
    expect(routing.first(where: { $0.action == .setRoutingPreference("最佳质量") })?.subtitle.hasPrefix("当前 - ") == true,
           "current routing preference is marked")
    expect(routing.first(where: { $0.action == .setRoutingPreference("最快") })?.systemImage == "point.3.connected.trianglepath.dotted",
           "non-current routing preference uses route icon")

    let enabled = ContextProfileCommandInput(id: "project-a",
                                             name: "项目 A",
                                             content: "术语表",
                                             isEnabled: true)
    let disabled = ContextProfileCommandInput(id: "project-b",
                                              name: "项目 B",
                                              content: "禁用",
                                              isEnabled: false)
    let empty = ContextProfileCommandInput(id: "project-c",
                                           name: "项目 C",
                                           content: " \n ",
                                           isEnabled: true)
    let contexts = RoutingContextCommandFactory.contextDescriptors(
        profiles: [enabled, disabled, empty],
        activeProfileID: enabled.id
    )

    expect(contexts.map(\.id) == ["context-clear", "context-copy-active", "context-copy-effective-prompt", "context-copy-status", "context-project-a"],
           "context command includes clear, copy, effective prompt, status and usable profiles only")
    expect(contexts[0].action == .clearContext, "clear command clears active context")
    expect(contexts[1].action == .copyActiveContext, "copy command copies active context")
    expect(contexts[1].subtitle == "项目 A", "copy command identifies active context profile")
    expect(contexts[1].keywords.contains("术语表"), "copy command is searchable by active context content")
    expect(contexts[2].action == .copyEffectiveSystemPrompt, "effective prompt command copies rendered system prompt")
    expect(contexts[2].subtitle == "全局 System Prompt + 当前上下文", "effective prompt command explains active context inclusion")
    expect(contexts[3].action == .copyContextStatus, "context status command copies safe metadata")
    expect(contexts[3].subtitle == "不包含上下文正文", "context status command explains safe metadata behavior")
    expect(contexts[4].subtitle == "当前上下文包", "active context profile is marked")
    expect(contexts[4].action == .setContextProfile(enabled.id), "context command switches by profile id")

    let noActive = RoutingContextCommandFactory.contextDescriptors(profiles: [enabled],
                                                                   activeProfileID: "")
    expect(noActive.map(\.id) == ["context-copy-effective-prompt", "context-copy-status", "context-project-a"],
           "clear and active context copy commands are hidden when no context is active")
    expect(noActive[0].subtitle == "全局 System Prompt", "effective prompt command explains base-only prompt")

    let slashID = ContextProfileCommandInput(id: "team/A",
                                             name: "团队 A",
                                             content: "背景",
                                             isEnabled: true)
    let spaceID = ContextProfileCommandInput(id: "team A",
                                             name: "团队 A 备份",
                                             content: "背景",
                                             isEnabled: true)
    let slugged = RoutingContextCommandFactory.contextDescriptors(profiles: [slashID, spaceID],
                                                                  activeProfileID: slashID.id)
    expect(slugged.map(\.id) == ["context-clear", "context-copy-active", "context-copy-effective-prompt", "context-copy-status", "context-team-A", "context-team-A-2"],
           "context command ids slug profile ids and disambiguate collisions")
    expect(slugged[4].action == .setContextProfile("team/A"),
           "context command action keeps original slash profile id")
    expect(slugged[5].action == .setContextProfile("team A"),
           "context command action keeps original spaced profile id")

    let unsafeProfile = ContextProfileCommandInput(id: "unsafe",
                                                   name: "项目\n# 注入|`A`",
                                                   content: String(repeating: "上下文\n", count: 80),
                                                   isEnabled: true)
    let unsafeContexts = RoutingContextCommandFactory.contextDescriptors(profiles: [unsafeProfile],
                                                                         activeProfileID: unsafeProfile.id)
    expect(unsafeContexts[1].subtitle == "项目 # 注入/'A'",
           "active context copy command keeps unsafe profile names single-line")
    expect(unsafeContexts[4].title == "切换上下文: 项目 # 注入/'A'",
           "context switch command title keeps unsafe profile names single-line")
    expect(unsafeContexts[4].action == .setContextProfile("unsafe"),
           "context switch command action keeps original profile id")
    expect(!unsafeContexts[4].title.contains("\n"), "context switch command title does not contain newlines")
    expect(unsafeContexts[1].keywords.contains("\n") == false &&
           unsafeContexts[1].keywords.contains("|") == false &&
           unsafeContexts[1].keywords.contains("`") == false,
           "active context copy command keywords are search-safe")
    expect(unsafeContexts[4].keywords.contains("\n") == false &&
           unsafeContexts[4].keywords.contains("|") == false &&
           unsafeContexts[4].keywords.contains("`") == false,
           "context switch command keywords are search-safe")
    expect(unsafeContexts[4].keywords.count < 420,
           "context command keywords cap long context content")
}

private func routingPreferenceInputs(currentID: String) -> [RoutingPreferenceCommandInput] {
    [
        RoutingPreferenceCommandInput(id: "最快",
                                      title: "最快",
                                      detail: "优先低延迟和低成本模型",
                                      isCurrent: currentID == "最快"),
        RoutingPreferenceCommandInput(id: "均衡",
                                      title: "均衡",
                                      detail: "兼顾速度、成本和任务适配",
                                      isCurrent: currentID == "均衡"),
        RoutingPreferenceCommandInput(id: "最佳质量",
                                      title: "最佳质量",
                                      detail: "优先长上下文、推理和复杂任务能力",
                                      isCurrent: currentID == "最佳质量")
    ]
}

func testResultDiagnosticsCommandIsSearchable() {
    expect(ResultDiagnosticsCommand.briefTitle == "复制精简请求诊断", "brief result diagnostics command has clear title")
    expect(ResultDiagnosticsCommand.briefCompactTitle == "复制精简", "brief result diagnostics command has compact title")
    expect(ResultDiagnosticsCommand.briefSubtitle.contains("错误详情"), "brief result diagnostics subtitle explains omitted details")
    expect(ResultDiagnosticsCommand.briefSubtitle.contains("恢复建议"), "brief result diagnostics subtitle mentions recovery suggestions")
    expect(ResultDiagnosticsCommand.title == "复制完整请求诊断", "full result diagnostics command has clear title")
    expect(ResultDiagnosticsCommand.compactTitle == "复制完整", "full result diagnostics command has compact title")
    expect(ResultDiagnosticsCommand.subtitle.contains("fallback"), "result diagnostics subtitle mentions fallback")
    expect(ResultDiagnosticsCommand.subtitle.contains("恢复建议"), "result diagnostics subtitle mentions recovery suggestions")
    expect(ResultDiagnosticsCommand.subtitle.contains("隐私"), "result diagnostics subtitle mentions privacy")
    expect(ResultDiagnosticsCommand.systemImage == "point.3.connected.trianglepath.dotted",
           "result diagnostics command uses route-like symbol")
    expect(ResultDiagnosticsCommand.briefKeywords.contains("summary"), "brief result diagnostics command is searchable by summary")
    expect(ResultDiagnosticsCommand.briefKeywords.contains("recovery"), "brief result diagnostics command is searchable by recovery")
    expect(ResultDiagnosticsCommand.briefKeywords.contains("修复"), "brief result diagnostics command is searchable by Chinese recovery terms")
    expect(ResultDiagnosticsCommand.keywords.contains("route"), "result diagnostics command is searchable in English")
    expect(ResultDiagnosticsCommand.keywords.contains("privacy"), "result diagnostics command is searchable by privacy in English")
    expect(ResultDiagnosticsCommand.keywords.contains("api key"), "result diagnostics command is searchable by API key problems")
    expect(ResultDiagnosticsCommand.keywords.contains("无可用"), "result diagnostics command is searchable by unavailable-route symptoms")
    expect(ResultDiagnosticsCommand.keywords.contains("脱敏"), "result diagnostics command is searchable by redaction in Chinese")
    expect(ResultDiagnosticsCommand.keywords.contains("诊断"), "result diagnostics command is searchable in Chinese")
}

func testResultRecoveryCommandPointsToAISettings() {
    expect(ResultRecoveryCommand.openAISettingsTitle == "打开 AI 设置",
           "result recovery command has a clear AI settings title")
    expect(ResultRecoveryCommand.openAISettingsCompactTitle == "AI 设置",
           "result recovery command has a compact button title")
    expect(ResultRecoveryCommand.openAISettingsSubtitle.contains("API Key"),
           "result recovery command explains API key troubleshooting")
    expect(ResultRecoveryCommand.openAISettingsSubtitle.contains("Base URL"),
           "result recovery command explains endpoint troubleshooting")
    expect(ResultRecoveryCommand.openAISettingsSystemImage == "gearshape.2",
           "result recovery command uses a settings-like symbol")
    expect(ResultRecoveryCommand.openAISettingsKeywords.contains("api key"),
           "result recovery command is searchable by API key problems")
    expect(ResultRecoveryCommand.openAISettingsKeywords.contains("Base URL") == false,
           "result recovery command keeps searchable keywords lowercase where useful")
    expect(ResultRecoveryCommand.openAISettingsKeywords.contains("base url"),
           "result recovery command is searchable by endpoint problems")
    expect(ResultRecoveryCommand.openAISettingsKeywords.contains("修复"),
           "result recovery command is searchable by Chinese recovery terms")

    let missingProvider = ResultRecoveryCommand.openAISettingsDescriptor(recoveryCode: "missing-provider")
    expect(missingProvider.title == "添加 AI 供应商",
           "result recovery command points missing providers to provider setup")
    expect(missingProvider.compactTitle == "添加供应商",
           "missing provider recovery keeps a compact button label")
    expect(missingProvider.subtitle.contains("填写 API Key"),
           "missing provider recovery explains the setup checklist")
    expect(missingProvider.systemImage == "plus.circle",
           "missing provider recovery uses an add-like symbol")
    expect(missingProvider.keywords.contains("无可用"),
           "missing provider recovery is searchable by unavailable-route terms")

    let missingModel = ResultRecoveryCommand.openAISettingsDescriptor(recoveryCode: "missing-model")
    expect(missingModel.title == "选择可用模型",
           "result recovery command points missing models to model selection")
    expect(missingModel.compactTitle == "选择模型",
           "missing model recovery keeps a compact button label")
    expect(missingModel.subtitle.contains("设为当前模型"),
           "missing model recovery explains the current model requirement")
    expect(missingModel.systemImage == "checklist.checked",
           "missing model recovery uses a selection-like symbol")

    let apiKey = ResultRecoveryCommand.openAISettingsDescriptor(recoveryCode: "api-key")
    expect(apiKey.title == "填写 API Key",
           "result recovery command points authentication errors to API key setup")
    expect(apiKey.compactTitle == "API Key",
           "API key recovery keeps a compact button label")
    expect(apiKey.systemImage == "key",
           "API key recovery uses a key symbol")

    let modelNotFound = ResultRecoveryCommand.openAISettingsDescriptor(recoveryCode: "model-not-found")
    expect(modelNotFound.title == "检查模型名称",
           "result recovery command points model lookup failures to model names")
    expect(modelNotFound.compactTitle == "模型名称",
           "model lookup recovery keeps a compact button label")

    let configurationRetry = ResultRecoveryCommand.retryDescriptor(recoveryCode: "api-key")
    expect(configurationRetry.title == "配置后重试",
           "configuration failures ask users to retry after fixing settings")
    expect(configurationRetry.compactTitle == "配置后重试",
           "configuration retry keeps a compact button label")
    expect(configurationRetry.subtitle.contains("AI 设置"),
           "configuration retry explains the required setup step")
    expect(configurationRetry.systemImage == "arrow.clockwise.circle",
           "configuration retry uses a retry-with-context symbol")

    let contextRetry = ResultRecoveryCommand.retryDescriptor(recoveryCode: "context-limit")
    expect(contextRetry.title == "调整后重试",
           "content-shape failures ask users to adjust payload before retrying")
    expect(contextRetry.systemImage == "slider.horizontal.3",
           "content-shape retry uses an adjustment symbol")

    let rateLimitRetry = ResultRecoveryCommand.retryDescriptor(recoveryCode: "rate-limit")
    expect(rateLimitRetry.title == "稍后重试",
           "rate limit failures ask users to wait before retrying")
    expect(rateLimitRetry.systemImage == "timer",
           "rate limit retry uses a time symbol")

    let transientRetry = ResultRecoveryCommand.retryDescriptor(recoveryCode: "network")
    expect(transientRetry.title == "重试请求",
           "transient failures keep a direct retry affordance")
    expect(transientRetry.compactTitle == "重试",
           "transient retry keeps the shortest button label")

    expect(ResultRecoveryCommand.primaryAction(recoveryCode: "api-key") == .settings,
           "configuration failures prefer opening AI settings before retrying")
    expect(ResultRecoveryCommand.primaryAction(recoveryCode: "missing-model") == .settings,
           "missing model failures prefer opening AI settings before retrying")
    expect(ResultRecoveryCommand.primaryAction(recoveryCode: "model-not-found") == .settings,
           "model lookup failures prefer checking model settings before retrying")
    expect(ResultRecoveryCommand.primaryAction(recoveryCode: "context-limit") == .retry,
           "payload adjustment failures prefer the adjusted retry action before generic settings")
    expect(ResultRecoveryCommand.primaryAction(recoveryCode: "payload-too-large") == .retry,
           "large payload failures prefer the adjusted retry action before generic settings")
    expect(ResultRecoveryCommand.primaryAction(recoveryCode: "generic-failure") == .retry,
           "unknown request failures prefer retry before generic settings")
    expect(ResultRecoveryCommand.primaryAction(recoveryCode: nil) == .retry,
           "missing recovery codes keep retry first instead of implying settings are required")
    expect(ResultRecoveryCommand.primaryAction(recoveryCode: "network") == .retry,
           "transient network failures prefer retry first")
    expect(ResultRecoveryCommand.primaryAction(recoveryCode: "provider-service") == .retry,
           "transient provider service failures prefer retry first")
    expect(ResultRecoveryCommand.primaryAction(recoveryCode: "rate-limit") == .retry,
           "rate-limit failures keep retry visible first after waiting")
}

func testResultCommandFactoryHidesCommandsWithoutResultContext() {
    let descriptors = ResultCommandFactory.descriptors(hasResult: false,
                                                       hasDiagnostics: false,
                                                       canWriteBack: false,
                                                       isStreaming: false,
                                                       hasSourceText: false)
    expect(descriptors.isEmpty, "empty result panel contributes no result commands")
}

func testResultCommandStateBuildsFromResultTexts() {
    let ready = ResultCommandState(resultText: "结果",
                                   diagnosticsText: "route ok",
                                   isStreaming: false,
                                   sourceText: "原文")
    expect(ready == ResultCommandState(hasResult: true,
                                       hasDiagnostics: true,
                                       canWriteBack: true,
                                       isStreaming: false,
                                       hasSourceText: true),
           "result command state derives ready state from result texts")

    let streaming = ResultCommandState(resultText: "partial",
                                       diagnosticsText: "",
                                       isStreaming: true,
                                       sourceText: "原文",
                                       protectsContentExport: true)
    expect(streaming.hasResult, "streaming state can still have partial result text")
    expect(!streaming.hasDiagnostics, "blank diagnostics text disables diagnostics")
    expect(!streaming.canWriteBack, "streaming result cannot write back")
    expect(streaming.hasSourceText, "non-empty source enables regenerate after streaming")
    expect(streaming.protectsContentExport, "result command state carries protected export state")
}

func testResultCommandFactoryBuildsStableMenuCommands() {
    let descriptors = ResultCommandFactory.menuDescriptors()
    expect(descriptors.map(\.id) == [
        "result-menu-copy",
        "result-menu-copy-markdown",
        "result-menu-copy-brief-diagnostics",
        "result-menu-copy-diagnostics",
        "result-menu-open-ai-settings",
        "result-menu-replace",
        "result-menu-append",
        "result-menu-export",
        "result-menu-regenerate",
        "result-menu-stop"
    ], "result menu commands keep stable desktop menu order")
    expect(descriptors.map(\.action) == [
        .copyOutput,
        .copyMarkdown,
        .copyBriefDiagnostics,
        .copyDiagnostics,
        .openAISettings,
        .replaceOriginal,
        .appendToDocument,
        .exportConversation,
        .regenerate,
        .stop
    ], "result menu commands carry expected actions")
    expect(descriptors[0].title == "复制结果" &&
           descriptors[0].keyEquivalent == "c" &&
           descriptors[0].modifiers == [.command, .shift],
           "copy result menu command keeps its shortcut")
    expect(descriptors[1].modifiers == [.command, .option],
           "copy markdown menu command keeps command-option shortcut")
    expect(descriptors[2].title == ResultDiagnosticsCommand.briefTitle &&
           descriptors[2].keyEquivalent == "d" &&
           descriptors[2].modifiers == [.command, .shift],
           "brief diagnostics menu command keeps command-shift shortcut")
    expect(descriptors[3].title == ResultDiagnosticsCommand.title &&
           descriptors[3].keyEquivalent == "d" &&
           descriptors[3].modifiers == [.command, .option],
           "full diagnostics menu command keeps command-option shortcut")
    expect(descriptors[4].title == ResultRecoveryCommand.openAISettingsTitle &&
           descriptors[4].keyEquivalent.isEmpty &&
           descriptors[4].modifiers.isEmpty,
           "open AI settings menu command has no direct shortcut")
    expect(descriptors[6].keyEquivalent == "\r" &&
           descriptors[6].modifiers == [.command, .shift],
           "append menu command keeps command-shift-return shortcut")
    expect(descriptors[7].title == "导出对话…",
           "export menu command keeps menu ellipsis")
    expect(descriptors[9].keyEquivalent == "\u{1b}" && descriptors[9].modifiers.isEmpty,
           "stop menu command keeps escape shortcut")
    expect(ResultCommandFactory.descriptor(for: .copyOutput).systemImage == "doc.on.doc",
           "copy output descriptor carries shared icon")
    expect(ResultCommandFactory.descriptor(for: .appendToDocument).title == "追加到文档",
           "append descriptor carries shared title")
    expect(ResultCommandFactory.shortcutText(for: .copyMarkdown) == "⌘⌥C",
           "copy markdown shortcut text is displayable")
    expect(ResultCommandFactory.shortcutText(for: .copyBriefDiagnostics) == "⌘⇧D",
           "brief diagnostics shortcut text is displayable")
    expect(ResultCommandFactory.shortcutText(for: .copyDiagnostics) == "⌘⌥D",
           "full diagnostics shortcut text is displayable")
    expect(ResultCommandFactory.shortcutText(for: .openAISettings) == nil,
           "open AI settings command intentionally has no shortcut")
    expect(ResultCommandFactory.shortcutText(for: .appendToDocument) == "⌘⇧↩",
           "append shortcut text handles return key")
    expect(ResultCommandFactory.shortcutText(for: .stop) == "Esc",
           "stop shortcut text handles escape")
    expect(ResultCommandFactory.helpText(for: .replaceOriginal) == "替换原文 (⌘↩)",
           "result command help combines title and shortcut")
}

func testResultCommandFactoryKeepsMenuShortcutsAndVisibleActionsConsistent() {
    let menuDescriptors = ResultCommandFactory.menuDescriptors()
    let menuIDs = menuDescriptors.map(\.id)
    let menuActions = menuDescriptors.map(\.action)
    let nonEmptyShortcuts = menuDescriptors
        .filter { !$0.keyEquivalent.isEmpty }
        .map { descriptor in
            "\(descriptor.modifiers.map(\.rawValue).joined(separator: "+"))|\(descriptor.keyEquivalent)"
        }

    expect(Set(menuIDs).count == menuIDs.count,
           "result menu command ids stay unique")
    expect(Set(menuActions).count == menuActions.count,
           "result menu command actions stay unique")
    expect(Set(nonEmptyShortcuts).count == nonEmptyShortcuts.count,
           "result menu shortcuts stay conflict-free")

    let fullState = ResultCommandState(resultText: "answer",
                                       diagnosticsText: "route=ok",
                                       isStreaming: false,
                                       sourceText: "source")
    let visibleActions = ResultCommandFactory.descriptors(state: fullState).map(\.action)
    let menuActionSet = Set(menuActions)

    expect(visibleActions.allSatisfy { menuActionSet.contains($0) },
           "every visible result command has a formal menu command")
    expect(visibleActions.allSatisfy { ResultCommandFactory.isEnabled($0, in: fullState) },
           "every visible result command is enabled in the state that produced it")
    expect(ResultCommandFactory.descriptors(state: fullState).allSatisfy { descriptor in
        !descriptor.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !descriptor.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !descriptor.keywords.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }, "visible result commands keep command palette metadata complete")

    let streamingState = ResultCommandState(resultText: "partial",
                                            diagnosticsText: "",
                                            isStreaming: true,
                                            sourceText: "source")
    let streamingActions = ResultCommandFactory.descriptors(state: streamingState).map(\.action)
    expect(streamingActions.contains(.stop), "streaming result command list exposes stop")
    expect(!streamingActions.contains(.replaceOriginal) &&
           !streamingActions.contains(.appendToDocument) &&
           !streamingActions.contains(.regenerate),
           "streaming result command list hides write-back and regenerate actions")
}

func testResultCommandFactoryExplainsProtectedConversationExports() {
    let normalCopy = ResultCommandFactory.descriptor(for: .copyMarkdown)
    expect(normalCopy.subtitle == "Markdown,含原文、结果、模型和路由摘要",
           "normal copy markdown descriptor keeps its full-content subtitle")
    expect(ResultCommandFactory.helpText(for: .copyMarkdown) == "复制完整结果 (⌘⌥C)",
           "normal copy markdown help remains compact")

    let protectedState = ResultCommandState(hasResult: true,
                                            hasDiagnostics: true,
                                            canWriteBack: true,
                                            isStreaming: false,
                                            hasSourceText: true,
                                            protectsContentExport: true)
    let descriptors = ResultCommandFactory.descriptors(state: protectedState)
    let copyMarkdown = descriptors.first { $0.action == .copyMarkdown }
    let exportConversation = descriptors.first { $0.action == .exportConversation }

    expect(copyMarkdown?.subtitle == "高风险保护:Markdown 将省略原文和结果正文",
           "protected copy markdown descriptor explains omitted content")
    expect(copyMarkdown?.keywords.contains("隐私") == true &&
           copyMarkdown?.keywords.contains("省略") == true,
           "protected copy markdown descriptor is searchable by privacy protection")
    expect(exportConversation?.subtitle == "高风险保护:导出的 Markdown 将省略正文",
           "protected export descriptor explains omitted content")
    expect(exportConversation?.keywords.contains("privacy") == true &&
           exportConversation?.keywords.contains("保护") == true,
           "protected export descriptor is searchable by privacy protection")
    expect(ResultCommandFactory.helpText(for: .copyMarkdown, in: protectedState)
        == "复制完整结果: 高风险保护:Markdown 将省略原文和结果正文 (⌘⌥C)",
           "protected copy markdown help includes the protection warning")
    expect(ResultCommandFactory.helpText(for: .exportConversation, in: protectedState)
        == "导出对话: 高风险保护:导出的 Markdown 将省略正文 (⌘E)",
           "protected export help includes the protection warning")
    expect(ResultCommandFactory.helpText(for: .copyOutput, in: protectedState) == "复制结果 (⌘⇧C)",
           "protected export state does not change copy-output help")
    expect(ResultCommandFactory.menuTitle(for: .copyMarkdown, in: protectedState) == "复制完整结果 (省略正文)",
           "protected copy markdown menu title warns about omitted content")
    expect(ResultCommandFactory.menuTitle(for: .exportConversation, in: protectedState) == "导出对话… (省略正文)",
           "protected export menu title warns about omitted content")
    expect(ResultCommandFactory.menuTitle(for: .copyOutput, in: protectedState) == "复制结果",
           "protected export state does not change copy-output menu title")
    expect(ResultCommandFactory.menuToolTip(for: .copyMarkdown, in: protectedState)
        == "高风险保护:Markdown 将省略原文和结果正文",
           "protected copy markdown menu tooltip explains omitted content")
    expect(ResultCommandFactory.menuToolTip(for: .exportConversation, in: protectedState)
        == "高风险保护:导出的 Markdown 将省略正文",
           "protected export menu tooltip explains omitted content")
    expect(ResultCommandFactory.menuToolTip(for: .copyOutput, in: protectedState) == nil,
           "protected export state does not add copy-output tooltip")
    expect(ResultCommandFactory.accessibilityLabel(for: .copyMarkdown, in: protectedState)
        == "复制完整结果, 高风险保护:Markdown 将省略原文和结果正文",
           "protected copy markdown accessibility label includes omitted-content warning")
    expect(ResultCommandFactory.accessibilityLabel(for: .exportConversation, in: protectedState)
        == "导出对话, 高风险保护:导出的 Markdown 将省略正文",
           "protected export accessibility label includes omitted-content warning")
    expect(ResultCommandFactory.accessibilityLabel(for: .copyOutput, in: protectedState) == "复制结果",
           "protected export state does not change copy-output accessibility label")
}

func testResultCommandFactoryAdaptsAISettingsRecoveryCommand() {
    let missingProviderState = ResultCommandState(hasResult: false,
                                                  hasDiagnostics: true,
                                                  canWriteBack: false,
                                                  isStreaming: false,
                                                  hasSourceText: true,
                                                  recoveryCode: "missing-provider")
    let missingProvider = ResultCommandFactory.descriptors(state: missingProviderState)
        .first { $0.action == .openAISettings }
    expect(missingProvider?.title == "添加 AI 供应商",
           "result command palette uses recovery-specific provider setup title")
    expect(missingProvider?.subtitle.contains("配置可用模型") == true,
           "provider setup recovery explains the next setup step")
    expect(missingProvider?.systemImage == "plus.circle",
           "provider setup recovery command uses its recovery icon")
    expect(ResultCommandFactory.helpText(for: .openAISettings, in: missingProviderState) == "添加 AI 供应商",
           "recovery-specific AI settings command keeps help concise without a shortcut")
    expect(ResultCommandFactory.accessibilityLabel(for: .openAISettings, in: missingProviderState) == "添加 AI 供应商",
           "recovery-specific AI settings command exposes the adapted title to accessibility")
    expect(ResultCommandFactory.menuTitle(for: .openAISettings, in: missingProviderState) == "添加 AI 供应商",
           "result menu validation uses the adapted recovery title")
    expect(ResultCommandFactory.menuToolTip(for: .openAISettings, in: missingProviderState)?.contains("API Key") == true,
           "result menu tooltip explains provider recovery")

    let missingModelState = ResultCommandState(hasResult: false,
                                               hasDiagnostics: true,
                                               canWriteBack: false,
                                               isStreaming: false,
                                               hasSourceText: false,
                                               recoveryCode: "missing-model")
    let missingModel = ResultCommandFactory.descriptors(state: missingModelState)
        .first { $0.action == .openAISettings }
    expect(missingModel?.title == "选择可用模型",
           "result command palette uses recovery-specific model setup title")
    expect(missingModel?.keywords.contains("选择") == true,
           "model setup recovery command is searchable by the adapted action")
}

func testResultCommandFactoryAdaptsRetryRecoveryCommand() {
    let apiKeyState = ResultCommandState(hasResult: false,
                                         hasDiagnostics: true,
                                         canWriteBack: false,
                                         isStreaming: false,
                                         hasSourceText: true,
                                         recoveryCode: "api-key")
    let apiKeyRetry = ResultCommandFactory.descriptors(state: apiKeyState)
        .first { $0.action == .regenerate }
    let apiKeyCommands = ResultCommandFactory.descriptors(state: apiKeyState).map(\.action)
    expect(apiKeyCommands.prefix(2) == [.openAISettings, .copyBriefDiagnostics],
           "configuration recovery puts AI settings before retry in the command palette")
    expect(apiKeyCommands.last == .regenerate,
           "configuration recovery keeps retry available after diagnostics")
    expect(apiKeyRetry?.title == "配置后重试",
           "configuration failures adapt regenerate to a setup-first retry command")
    expect(apiKeyRetry?.subtitle == "先修复 AI 设置,再重新发送请求",
           "configuration retry explains why immediate retry may not help")
    expect(apiKeyRetry?.systemImage == "arrow.clockwise.circle",
           "configuration retry command uses its recovery icon")
    expect(ResultCommandFactory.helpText(for: .regenerate, in: apiKeyState) == "配置后重试 (⌘R)",
           "configuration retry keeps the existing regenerate shortcut")
    expect(ResultCommandFactory.accessibilityLabel(for: .regenerate, in: apiKeyState) == "配置后重试",
           "configuration retry exposes the adapted action to accessibility")
    expect(ResultCommandFactory.menuTitle(for: .regenerate, in: apiKeyState) == "配置后重试",
           "result menu validation uses the adapted retry title")
    expect(ResultCommandFactory.menuToolTip(for: .regenerate, in: apiKeyState) == "先修复 AI 设置,再重新发送请求",
           "result menu tooltip explains configuration retry")

    let contextState = ResultCommandState(hasResult: false,
                                          hasDiagnostics: true,
                                          canWriteBack: false,
                                          isStreaming: false,
                                          hasSourceText: true,
                                          recoveryCode: "context-limit")
    let contextRetry = ResultCommandFactory.descriptors(state: contextState)
        .first { $0.action == .regenerate }
    let contextCommands = ResultCommandFactory.descriptors(state: contextState).map(\.action)
    expect(contextCommands.prefix(2) == [.regenerate, .copyBriefDiagnostics],
           "payload adjustment recovery puts adjusted retry before diagnostics and settings")
    expect(contextCommands.last == .openAISettings,
           "payload adjustment recovery keeps settings available after retry guidance")
    expect(contextRetry?.title == "调整后重试",
           "context failures adapt regenerate to an adjust-first retry command")
    expect(contextRetry?.keywords.contains("缩短") == true,
           "context retry command is searchable by payload adjustment terms")
    expect(ResultCommandFactory.menuTitle(for: .regenerate, in: contextState) == "调整后重试",
           "context retry menu title keeps the adjusted retry action prominent")
    expect(ResultCommandFactory.menuToolTip(for: .regenerate, in: contextState)?.contains("缩短内容") == true,
           "context retry menu tooltip explains the adjustment path")

    let networkState = ResultCommandState(hasResult: false,
                                          hasDiagnostics: true,
                                          canWriteBack: false,
                                          isStreaming: false,
                                          hasSourceText: true,
                                          recoveryCode: "network")
    let networkRetry = ResultCommandFactory.descriptors(state: networkState)
        .first { $0.action == .regenerate }
    let networkCommands = ResultCommandFactory.descriptors(state: networkState).map(\.action)
    expect(networkCommands.prefix(2) == [.regenerate, .copyBriefDiagnostics],
           "transient recovery puts retry before diagnostics and settings in the command palette")
    expect(networkCommands.last == .openAISettings,
           "transient recovery keeps settings available after retry guidance")
    expect(networkRetry?.title == "重试请求",
           "transient failures keep a direct retry command")
}

func testResultCommandFactoryUsesStopWhileStreaming() {
    let state = ResultCommandState(hasResult: true,
                                   hasDiagnostics: false,
                                   canWriteBack: false,
                                   isStreaming: true,
                                   hasSourceText: true)
    let descriptors = ResultCommandFactory.descriptors(state: state)

    expect(descriptors.map(\.id) == [
        "result-copy",
        "result-copy-markdown",
        "result-export",
        "result-stop"
    ], "streaming result commands include stop instead of writeback or regenerate")
    expect(descriptors.last?.action == .stop, "streaming command stops the result request")
    expect(!descriptors.contains(where: { $0.action == .regenerate }),
           "streaming result cannot regenerate until the request finishes")
    expect(!descriptors.contains(where: { $0.action == .replaceOriginal || $0.action == .appendToDocument }),
           "streaming result does not expose writeback commands")
    expect(ResultCommandFactory.isEnabled(.stop, in: state), "stop is enabled while streaming")
    expect(!ResultCommandFactory.isEnabled(.regenerate, in: state), "regenerate is disabled while streaming")
    expect(!ResultCommandFactory.isEnabled(.replaceOriginal, in: state), "replace is disabled while streaming")
    expect(!ResultCommandFactory.isEnabled(.appendToDocument, in: state), "append is disabled while streaming")
}

func testResultCommandFactoryOmitsDiagnosticsWhenUnavailable() {
    let state = ResultCommandState(hasResult: true,
                                   hasDiagnostics: false,
                                   canWriteBack: true,
                                   isStreaming: false,
                                   hasSourceText: false)
    let descriptors = ResultCommandFactory.descriptors(state: state)

    expect(!descriptors.contains(where: { $0.action == .copyBriefDiagnostics || $0.action == .copyDiagnostics }),
           "result command hides diagnostics when no diagnostics text exists")
    expect(!descriptors.contains(where: { $0.action == .openAISettings }),
           "result command hides AI settings recovery when no diagnostics text exists")
    expect(!descriptors.contains(where: { $0.action == .regenerate }),
           "result command hides regenerate when no source text exists")
    expect(descriptors.contains(where: { $0.action == .replaceOriginal }),
           "writeback command still appears when writeback is available")
    expect(!ResultCommandFactory.isEnabled(.copyBriefDiagnostics, in: state),
           "brief diagnostics command is disabled without diagnostics text")
    expect(!ResultCommandFactory.isEnabled(.copyDiagnostics, in: state),
           "diagnostics command is disabled without diagnostics text")
    expect(!ResultCommandFactory.isEnabled(.openAISettings, in: state),
           "AI settings recovery command is disabled without diagnostics text")
    expect(!ResultCommandFactory.isEnabled(.regenerate, in: state),
           "regenerate command is disabled without source text")
}

func testResultCommandFactoryShowsRecoverySettingsWithoutDiagnostics() {
    let state = ResultCommandState(hasResult: false,
                                   hasDiagnostics: false,
                                   canWriteBack: false,
                                   isStreaming: false,
                                   hasSourceText: true,
                                   recoveryCode: "api-key")
    let descriptors = ResultCommandFactory.descriptors(state: state)

    expect(!descriptors.contains(where: { $0.action == .copyBriefDiagnostics || $0.action == .copyDiagnostics }),
           "recovery-only command state still hides diagnostics commands")
    expect(descriptors.map(\.action) == [.openAISettings, .regenerate],
           "recovery-only command state keeps settings fix before retry for configuration failures")
    expect(descriptors.first?.title == "填写 API Key",
           "recovery-only command state exposes the concrete settings fix")
    expect(descriptors.last?.title == "配置后重试",
           "recovery-only command state keeps retry available after the fix")
    expect(ResultCommandFactory.isEnabled(.openAISettings, in: state),
           "AI settings recovery is enabled when a recovery code exists without diagnostics")
    expect(!ResultCommandFactory.isEnabled(.copyBriefDiagnostics, in: state),
           "brief diagnostics remain disabled without diagnostics text")
    expect(!ResultCommandFactory.isEnabled(.copyDiagnostics, in: state),
           "full diagnostics remain disabled without diagnostics text")
}

func testHistoryEntryCommandPaletteKeywordsCoverMetadata() {
    let entry = HistoryEntry(date: Date(timeIntervalSince1970: 0),
                             actionName: "总结",
                             source: "release notes",
                             output: "权限诊断",
                             provider: "OpenAI",
                             model: "gpt-4o-mini",
                             isFavorite: true,
                             tags: ["发布", "  ", "诊断", "发布", "多余"])
    let keywords = entry.commandPaletteKeywords
    expect(keywords.contains("总结"), "history command keywords include action")
    expect(keywords.contains("release notes"), "history command keywords include source")
    expect(keywords.contains("权限诊断"), "history command keywords include output")
    expect(keywords.contains("OpenAI"), "history command keywords include provider")
    expect(keywords.contains("gpt-4o-mini"), "history command keywords include model")
    expect(keywords.contains("发布"), "history command keywords include tags")
    expect(!keywords.contains("  "), "history command keywords omit blank tags")
    expect(keywords.components(separatedBy: "发布").count == 2, "history command keywords dedupe repeated tags")

    let subtitle = entry.commandPaletteSubtitle
    expect(subtitle.contains("历史记录"), "history command subtitle identifies history entries")
    expect(subtitle.contains("总结"), "history command subtitle includes action")
    expect(subtitle.contains("OpenAI / gpt-4o-mini"), "history command subtitle includes provider and model")
    expect(subtitle.contains("收藏"), "history command subtitle includes favorite state")
    expect(subtitle.contains("#发布 #诊断"), "history command subtitle includes compact tag summary")
    expect(!subtitle.contains("多余"), "history command subtitle limits tag summary")
    expect(subtitle.count <= 72, "history command subtitle stays compact")

    let longMetadata = HistoryEntry(actionName: "非常非常长的动作名称用于测试命令面板副标题是否会过长",
                                    source: "source",
                                    output: "output",
                                    provider: "VeryLongProviderNameForCommandPalette",
                                    model: "very-long-model-name-for-command-palette-display",
                                    tags: ["很长的标签一", "很长的标签二"])
    expect(longMetadata.commandPaletteSubtitle.count <= 72,
           "long history command subtitle is capped by default")
    expect(longMetadata.commandPaletteSubtitle(maxLength: 1) == "…",
           "history command subtitle handles tiny limits")

    let dirtyMetadata = HistoryEntry(actionName: " 总结 ",
                                     source: "source",
                                     output: "output",
                                     provider: " OpenAI ",
                                     model: " gpt ",
                                     tags: [" 发布 "])
    expect(dirtyMetadata.commandPaletteSubtitle.contains("总结 - OpenAI / gpt"),
           "history command subtitle uses display metadata")
    expect(!dirtyMetadata.commandPaletteSubtitle.contains("  OpenAI  "),
           "history command subtitle avoids raw padded metadata")

    let longSource = "开头可搜索 " + String(repeating: "长原文", count: 500) + " 尾部不应进入命令面板关键词"
    let longOutput = "输出可搜索 " + String(repeating: "长结果", count: 500)
    let longContent = HistoryEntry(actionName: "总结",
                                   source: longSource,
                                   output: longOutput,
                                   provider: "OpenAI",
                                   model: "gpt")
    let longKeywords = longContent.commandPaletteKeywords
    expect(longKeywords.contains("开头可搜索"), "history command keywords keep searchable source prefix")
    expect(longKeywords.contains("输出可搜索"), "history command keywords keep searchable output prefix")
    expect(!longKeywords.contains("尾部不应进入命令面板关键词"),
           "history command keywords omit far-tail long source content")
    expect(longKeywords.count < 1_400, "history command keywords cap long source and output snippets")

    let sensitive = HistoryEntry(actionName: "总结\napi_key=actionsecret123456",
                                 source: "Authorization: Bearer sourceToken123456 keep-searchable",
                                 output: "password=outputsecret123456 sk-proj-history-secret-1234567890",
                                 provider: "Provider|`P`",
                                 model: "model\nsk-proj-model-secret-1234567890",
                                 tags: ["tag|`x`"])
    let sensitiveKeywords = sensitive.commandPaletteKeywords
    expect(sensitiveKeywords.contains("keep-searchable"),
           "history command keywords keep non-sensitive searchable content")
    expect(!sensitiveKeywords.contains("actionsecret123456") &&
           !sensitiveKeywords.contains("sourceToken123456") &&
           !sensitiveKeywords.contains("outputsecret123456") &&
           !sensitiveKeywords.contains("sk-proj-history-secret-1234567890") &&
           !sensitiveKeywords.contains("sk-proj-model-secret-1234567890"),
           "history command keywords redact key-like metadata and content fragments")
    expect(!sensitiveKeywords.contains("\n") &&
           !sensitiveKeywords.contains("|") &&
           !sensitiveKeywords.contains("`"),
           "history command keywords are single-line and markdown-safe")
}

func testHistoryContextCommandFactoryBuildsUsableContextCommands() {
    let useful = HistoryEntry(actionName: "总结",
                              source: "项目背景",
                              output: "项目结论",
                              provider: "OpenAI",
                              model: "gpt-4o-mini",
                              isFavorite: true,
                              tags: ["项目A"])
    let outputOnly = HistoryEntry(actionName: "总结",
                                  source: "",
                                  output: "可复用结论",
                                  provider: "OpenAI",
                                  model: "gpt-4o-mini",
                                  tags: ["项目A"])
    let metadataOnly = HistoryEntry(actionName: "隐私审计",
                                    source: "",
                                    output: "",
                                    provider: "OpenAI",
                                    model: "gpt",
                                    isFavorite: true,
                                    tags: [PrivacyHistoryTag.metadataOnly, "项目A"])
    let blank = HistoryEntry(actionName: "空记录",
                             source: " \n ",
                             output: "",
                             provider: "OpenAI",
                             model: "gpt")

    let descriptors = HistoryContextCommandFactory.descriptors(for: historyContextCommandInputs([useful, outputOnly, metadataOnly, blank]),
                                                               facetLimit: 2)

    expect(descriptors.map(\.id) == [
        "history-context-all",
        "history-context-action-总结",
        "history-context-model-gpt-4o-mini",
        "history-context-tag-项目A",
        "history-context-favorites"
    ], "history context commands include all/action/model/tag/favorite usable facets")
    expect(descriptors[0].subtitle == "2 条可用记录", "all context command counts usable history only")
    expect(descriptors[1].criteria == HistoryContextCommandCriteria(actionFilter: "总结"),
           "action context command carries action filter")
    expect(descriptors[2].criteria == HistoryContextCommandCriteria(modelFilter: "gpt-4o-mini"),
           "model context command carries model filter")
    expect(descriptors[3].criteria == HistoryContextCommandCriteria(tagFilter: "项目A"),
           "tag context command carries tag filter")
    expect(descriptors[4].subtitle == "1 条可用收藏记录",
           "favorite context command ignores metadata-only favorites")
    expect(!descriptors.contains { $0.title.contains("隐私审计") || $0.keywords.contains(PrivacyHistoryTag.metadataOnly) },
           "history context commands do not expose metadata-only records as context sources")

    expect(HistoryContextCommandFactory.descriptors(for: historyContextCommandInputs([metadataOnly, blank])).isEmpty,
           "history context commands are unavailable when no usable history content exists")

    let unsafe = HistoryEntry(actionName: "总结|`A`\n测试",
                              source: "项目背景",
                              output: "项目结论",
                              provider: "OpenAI",
                              model: "gpt|4o\nmini",
                              tags: ["项目|`A`\n标签"])
    let unsafeDescriptors = HistoryContextCommandFactory.descriptors(for: historyContextCommandInputs([unsafe]), facetLimit: 4)
    let unsafeAction = unsafeDescriptors.first { $0.id.hasPrefix("history-context-action-") }
    let unsafeModel = unsafeDescriptors.first { $0.id.hasPrefix("history-context-model-") }
    let unsafeTag = unsafeDescriptors.first { $0.id.hasPrefix("history-context-tag-") }
    expect(unsafeAction?.title == "从总结/'A' 测试历史创建上下文",
           "history context action command keeps unsafe action names single-line")
    expect(unsafeAction?.criteria.actionFilter == "总结|`A` 测试",
           "history context action criteria keeps normalized original action value")
    expect(unsafeAction?.keywords.contains("\n") == false &&
           unsafeAction?.keywords.contains("|") == false &&
           unsafeAction?.keywords.contains("`") == false,
           "history context action command keywords are search-safe")
    expect(unsafeModel?.title == "从模型「gpt/4o mini」历史创建上下文",
           "history context model command keeps unsafe model names single-line")
    expect(unsafeModel?.criteria.modelFilter == "gpt|4o mini",
           "history context model criteria keeps normalized original model value")
    expect(unsafeModel?.keywords.contains("\n") == false &&
           unsafeModel?.keywords.contains("|") == false &&
           unsafeModel?.keywords.contains("`") == false,
           "history context model command keywords are search-safe")
    expect(unsafeTag?.title == "从标签「项目/'A' 标签」历史创建上下文",
           "history context tag command keeps unsafe tag names single-line")
    expect(unsafeTag?.criteria.tagFilter == "项目|`A` 标签",
           "history context tag criteria keeps normalized original tag value")
    expect(unsafeTag?.keywords.contains("\n") == false &&
           unsafeTag?.keywords.contains("|") == false &&
           unsafeTag?.keywords.contains("`") == false,
           "history context tag command keywords are search-safe")
}

func testHistoryExportCommandsUseDisplayTags() {
    let history = [
        HistoryEntry(actionName: " 总结 ",
                     source: "原文",
                     output: "结果",
                     provider: "OpenAI",
                     model: "gpt",
                     tags: [" 发布 ", "", "发布"]),
        HistoryEntry(actionName: "总结",
                     source: "hello",
                     output: "你好",
                     provider: "OpenAI",
                     model: "gpt",
                     tags: ["发布"]),
        HistoryEntry(actionName: " ",
                     source: "空动作历史",
                     output: "结果",
                     provider: "OpenAI",
                     model: " ",
                     tags: ["诊断"])
    ]

    let descriptors = HistoryExportCommandFactory.descriptors(for: historyExportCommandInputs(history))
    let actionDescriptor = descriptors.first { $0.id == "history-copy-action-总结" }
    expect(actionDescriptor?.subtitle.hasPrefix("2 条记录") == true,
           "history export command counts normalized action names")
    expect(actionDescriptor?.criteria.actionFilter == "总结",
           "history export command filters by normalized action name")
    let unnamedActionDescriptor = descriptors.first { $0.id == "history-copy-action-未命名动作" }
    expect(unnamedActionDescriptor?.subtitle.hasPrefix("1 条记录") == true,
           "history export command exposes unnamed display action entries")
    expect(unnamedActionDescriptor?.criteria.actionFilter == "未命名动作",
           "history export command can filter unnamed display action entries")
    let modelDescriptor = descriptors.first { $0.id == "history-copy-model-gpt" }
    expect(modelDescriptor?.subtitle.hasPrefix("2 条记录") == true,
           "history export command counts normalized model names")
    expect(modelDescriptor?.criteria.modelFilter == "gpt",
           "history export command filters by normalized model name")
    let unknownModelDescriptor = descriptors.first { $0.id == "history-copy-model-未知模型" }
    expect(unknownModelDescriptor?.subtitle.hasPrefix("1 条记录") == true,
           "history export command exposes unknown model entries")
    expect(unknownModelDescriptor?.criteria.modelFilter == "未知模型",
           "history export command can filter unknown model entries")
    let tagDescriptor = descriptors.first { $0.id == "history-copy-tag-发布" }
    expect(tagDescriptor?.title == "复制标签「发布」历史",
           "history export command titles use normalized display tags")
    expect(tagDescriptor?.subtitle.hasPrefix("2 条记录") == true,
           "history export command counts deduped display tags per entry")
    expect(tagDescriptor?.criteria.tagFilter == "发布",
           "history export command filters by normalized display tag")
    expect(!descriptors.contains { $0.id.contains(" 发布 ") },
           "history export commands do not expose raw padded tags")

    let unsafeHistory = [
        HistoryEntry(actionName: "总结|`A`\n测试",
                     source: "原文",
                     output: "结果",
                     provider: "OpenAI",
                     model: "gpt|4o\nmini",
                     tags: ["项目|`A`\n标签"])
    ]
    let unsafeDescriptors = HistoryExportCommandFactory.descriptors(for: historyExportCommandInputs(unsafeHistory), facetLimit: 4)
    let unsafeAction = unsafeDescriptors.first { $0.id.hasPrefix("history-copy-action-") }
    let unsafeModel = unsafeDescriptors.first { $0.id.hasPrefix("history-copy-model-") }
    let unsafeTag = unsafeDescriptors.first { $0.id.hasPrefix("history-copy-tag-") }
    expect(unsafeAction?.title == "复制总结/'A' 测试历史",
           "history export action command keeps unsafe action names single-line")
    expect(unsafeAction?.criteria.actionFilter == "总结|`A` 测试",
           "history export action criteria keeps normalized original action value")
    expect(unsafeAction?.keywords.contains("\n") == false &&
           unsafeAction?.keywords.contains("|") == false &&
           unsafeAction?.keywords.contains("`") == false,
           "history export action command keywords are search-safe")
    expect(unsafeModel?.title == "复制模型「gpt/4o mini」历史",
           "history export model command keeps unsafe model names single-line")
    expect(unsafeModel?.criteria.modelFilter == "gpt|4o mini",
           "history export model criteria keeps normalized original model value")
    expect(unsafeModel?.keywords.contains("\n") == false &&
           unsafeModel?.keywords.contains("|") == false &&
           unsafeModel?.keywords.contains("`") == false,
           "history export model command keywords are search-safe")
    expect(unsafeTag?.title == "复制标签「项目/'A' 标签」历史",
           "history export tag command keeps unsafe tag names single-line")
    expect(unsafeTag?.criteria.tagFilter == "项目|`A` 标签",
           "history export tag criteria keeps normalized original tag value")
    expect(unsafeTag?.keywords.contains("\n") == false &&
           unsafeTag?.keywords.contains("|") == false &&
           unsafeTag?.keywords.contains("`") == false,
           "history export tag command keywords are search-safe")
}

func testHistoryExportCommandFactoryBuildsRankedFacetCommands() {
    let entries = [
        HistoryEntry(actionName: "翻译",
                     source: "a",
                     output: "b",
                     provider: "OpenAI",
                     model: "gpt",
                     isFavorite: true,
                     tags: ["项目A", "发布"]),
        HistoryEntry(actionName: "翻译",
                     source: "c",
                     output: "d",
                     provider: "OpenAI",
                     model: "gpt",
                     tags: ["项目A"]),
        HistoryEntry(actionName: "总结",
                     source: "e",
                     output: "f",
                     provider: "OpenAI",
                     model: "gpt",
                     tags: ["  ", "诊断"])
    ]

    let descriptors = HistoryExportCommandFactory.descriptors(for: historyExportCommandInputs(entries), facetLimit: 1)

    expect(descriptors.map(\.id) == [
        "history-copy-markdown",
        "history-copy-action-翻译",
        "history-copy-model-gpt",
        "history-copy-tag-项目A",
        "history-copy-favorites-markdown"
    ], "builds all/action/tag/favorite export commands in stable order")
    expect(descriptors[0].criteria == HistoryExportCommandCriteria(), "all history command uses default criteria")
    expect(descriptors[1].criteria == HistoryExportCommandCriteria(actionFilter: "翻译"), "action command filters by action")
    expect(descriptors[2].criteria == HistoryExportCommandCriteria(modelFilter: "gpt"), "model command filters by model")
    expect(descriptors[3].criteria == HistoryExportCommandCriteria(tagFilter: "项目A"), "tag command filters by tag")
    expect(descriptors[4].criteria == HistoryExportCommandCriteria(favoriteOnly: true), "favorite command filters favorites")
    expect(descriptors[1].subtitle == "2 条记录,Markdown", "action command reports count")
    expect(descriptors[2].keywords.contains("模型"), "model command is searchable by model")
    expect(descriptors[3].keywords.contains("项目A"), "tag command is searchable by tag")
    expect(HistoryExportCommandFactory.descriptors(for: []).isEmpty, "empty history produces no export commands")
}

func testHistoryExportCommandIDsAreStableSlugs() {
    let entries = [
        HistoryEntry(actionName: "A/B",
                     source: "a",
                     output: "b",
                     provider: "OpenAI",
                     model: "gpt/4o mini",
                     tags: ["项目/Alpha"]),
        HistoryEntry(actionName: "A B",
                     source: "c",
                     output: "d",
                     provider: "OpenAI",
                     model: "gpt 4o mini",
                     tags: ["项目 Alpha"])
    ]

    let descriptors = HistoryExportCommandFactory.descriptors(for: historyExportCommandInputs(entries), facetLimit: 4)
    let actionIDs = descriptors
        .filter { $0.id.hasPrefix("history-copy-action-") }
        .map(\.id)
    expect(actionIDs.contains("history-copy-action-A-B"), "history export action ids replace separators with slug dashes")
    expect(actionIDs.contains("history-copy-action-A-B-2"), "history export action ids disambiguate slug collisions")
    expect(descriptors.contains { $0.id == "history-copy-model-gpt-4o-mini" },
           "history export model ids replace slash and spaces")
    expect(descriptors.contains { $0.id == "history-copy-model-gpt-4o-mini-2" },
           "history export model ids disambiguate model slug collisions")
    expect(descriptors.contains { $0.id == "history-copy-tag-项目-Alpha" },
           "history export tag ids keep readable unicode and replace separators")
    expect(descriptors.contains { $0.id == "history-copy-tag-项目-Alpha-2" },
           "history export tag ids disambiguate tag slug collisions")
    expect(descriptors.allSatisfy { !$0.id.contains("/") && !$0.id.contains(" ") },
           "history export command ids do not contain path or whitespace separators")
}
