import AppIntents
import AppKit
import SnapAILogic

enum SnapAIIntentOutputFormat: String, AppEnum {
    case text
    case json

    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "返回格式")
    static var caseDisplayRepresentations: [Self: DisplayRepresentation] = [
        .text: "AI 正文", .json: "JSON（含错误信息）"
    ]
}

/// 用指定动作处理一段文本(默认取剪贴板)。
struct SnapAIRunActionIntent: AppIntent {
    static var title: LocalizedStringResource = "用 SnapAI 处理文本"
    static var description = IntentDescription("用指定的 SnapAI 动作处理文本并等待 AI 正文，可供下一步使用。默认读取剪贴板。")
    static var openAppWhenRun: Bool = true

    @Parameter(title: "文本", description: "留空则读取剪贴板。")
    var text: String?

    @Parameter(title: "动作", description: "留空则使用第一个启用的动作。")
    var action: String?

    @Parameter(title: "返回格式", default: .text)
    var outputFormat: SnapAIIntentOutputFormat

    @Parameter(title: "等待秒数", description: "隐私确认后等待生成完成的最长时间，范围 1–600 秒。", default: 120)
    var timeoutSeconds: Int

    static var parameterSummary: some ParameterSummary {
        Summary("用\(\.$action)处理\(\.$text)") {
            \.$outputFormat
            \.$timeoutSeconds
        }
    }

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        do {
            try Task.checkCancellation()
            let input = (text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let resolved: String
            if !input.isEmpty {
                resolved = input
            } else if let clip = NSPasteboard.general.string(forType: .string)?
                .trimmingCharacters(in: .whitespacesAndNewlines), !clip.isEmpty {
                resolved = clip
            } else {
                throw SnapAIIntentError.emptyInput("剪贴板为空,请传入文本。")
            }
            guard let delegate = NSApp.delegate as? AppDelegate else {
                throw SnapAIIntentError.appUnavailable("SnapAI 未在运行。")
            }
            let output = try await delegate.runAutomationAction(
                actionQuery: action?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
                text: resolved,
                timeout: TimeInterval(min(600, max(1, timeoutSeconds)))
            )
            return .result(value: outputFormat == .json ? try AutomationActionResult(text: output).json() : output)
        } catch {
            let failure = SnapAIIntentError.normalized(error)
            guard outputFormat == .json else { throw failure }
            return .result(value: try AutomationActionResult(error: failure).json())
        }
    }
}

/// 打开快捷提问面板(可预填文本)。
struct SnapAIOpenQuickInputIntent: AppIntent {
    static var title: LocalizedStringResource = "打开 SnapAI 快捷提问"
    static var description = IntentDescription("打开 SnapAI 快捷提问面板,可选预填文本。")
    static var openAppWhenRun: Bool = true

    @Parameter(title: "预填文本")
    var text: String?

    func perform() async throws -> some IntentResult {
        let appDelegate = await MainActor.run { NSApp.delegate as? AppDelegate }
        guard let delegate = appDelegate else {
            throw SnapAIIntentError.appUnavailable("SnapAI 未在运行。")
        }
        let prefill = text?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        await MainActor.run {
            delegate.runAutomationCommand(.openQuickInput(text: prefill))
        }
        return .result()
    }
}

/// 切换模型(供应商/模型均支持模糊匹配,复用命令面板同一套匹配)。
struct SnapAISwitchModelIntent: AppIntent {
    static var title: LocalizedStringResource = "切换 SnapAI 模型"
    static var description = IntentDescription("切换 SnapAI 当前使用的供应商与模型。")
    static var openAppWhenRun: Bool = true

    @Parameter(title: "供应商", description: "留空则只按模型名匹配。")
    var provider: String?

    @Parameter(title: "模型")
    var model: String?

    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        let appDelegate = await MainActor.run { NSApp.delegate as? AppDelegate }
        guard let delegate = appDelegate else {
            throw SnapAIIntentError.appUnavailable("SnapAI 未在运行。")
        }
        let providerQuery = provider?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        let modelQuery = model?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        let outcome = await MainActor.run {
            delegate.switchModelFromAutomation(providerQuery: providerQuery,
                                               modelQuery: modelQuery)
        }
        return .result(value: outcome)
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}

/// 快捷指令快捷方式(Shortcuts App 边栏):三个 Intent 一键可达。
struct SnapAIShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: SnapAIRunActionIntent(),
                    phrases: ["用 SnapAI 处理剪贴板", "用 SnapAI 总结文本"],
                    shortTitle: "SnapAI 处理文本",
                    systemImageName: "wand.and.stars")
        AppShortcut(intent: SnapAIOpenQuickInputIntent(),
                    phrases: ["打开 SnapAI 快捷提问"],
                    shortTitle: "SnapAI 快捷提问",
                    systemImageName: "text.bubble")
        AppShortcut(intent: SnapAISwitchModelIntent(),
                    phrases: ["切换 SnapAI 模型"],
                    shortTitle: "切换 SnapAI 模型",
                    systemImageName: "cpu")
    }
}
