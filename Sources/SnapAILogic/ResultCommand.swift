import Foundation

public enum ResultCommandAction: Equatable {
    case copyOutput
    case copyMarkdown
    case exportConversation
    case copyBriefDiagnostics
    case copyDiagnostics
    case openAISettings
    case replaceOriginal
    case appendToDocument
    case stop
    case regenerate
}

public struct ResultCommandState: Equatable {
    public var hasResult: Bool
    public var hasDiagnostics: Bool
    public var canWriteBack: Bool
    public var isStreaming: Bool
    public var hasSourceText: Bool
    public var protectsContentExport: Bool = false
    public var recoveryCode: String? = nil

    public init(hasResult: Bool,
                hasDiagnostics: Bool,
                canWriteBack: Bool,
                isStreaming: Bool,
                hasSourceText: Bool,
                protectsContentExport: Bool = false,
                recoveryCode: String? = nil) {
        self.hasResult = hasResult
        self.hasDiagnostics = hasDiagnostics
        self.canWriteBack = canWriteBack
        self.isStreaming = isStreaming
        self.hasSourceText = hasSourceText
        self.protectsContentExport = protectsContentExport
        self.recoveryCode = recoveryCode
    }
}

public extension ResultCommandState {
    init(resultText: String,
         diagnosticsText: String,
         isStreaming: Bool,
         sourceText: String,
         protectsContentExport: Bool = false,
         recoveryCode: String? = nil) {
        let hasResult = !resultText.isEmpty
        self.init(
            hasResult: hasResult,
            hasDiagnostics: !diagnosticsText.isEmpty,
            canWriteBack: hasResult && !isStreaming,
            isStreaming: isStreaming,
            hasSourceText: !sourceText.isEmpty,
            protectsContentExport: protectsContentExport,
            recoveryCode: recoveryCode
        )
    }
}

public struct ResultCommandDescriptor: Equatable {
    public var id: String
    public var title: String
    public var subtitle: String
    public var systemImage: String
    public var keywords: String
    public var action: ResultCommandAction
}

public enum ResultMenuModifier: String, Equatable {
    case command
    case option
    case shift
}

public struct ResultMenuCommandDescriptor: Equatable {
    public var id: String
    public var title: String
    public var keyEquivalent: String
    public var modifiers: [ResultMenuModifier]
    public var action: ResultCommandAction
}

public enum ResultCommandFactory {
    public static func descriptor(for action: ResultCommandAction) -> ResultCommandDescriptor {
        descriptor(for: action, protectsContentExport: false, recoveryCode: nil)
    }

    public static func descriptor(for action: ResultCommandAction,
                                  protectsContentExport: Bool) -> ResultCommandDescriptor {
        descriptor(for: action, protectsContentExport: protectsContentExport, recoveryCode: nil)
    }

    public static func descriptor(for action: ResultCommandAction,
                                  in state: ResultCommandState) -> ResultCommandDescriptor {
        descriptor(for: action,
                   protectsContentExport: state.protectsContentExport,
                   recoveryCode: state.recoveryCode)
    }

    public static func descriptor(for action: ResultCommandAction,
                                  protectsContentExport: Bool,
                                  recoveryCode: String?) -> ResultCommandDescriptor {
        switch action {
        case .copyOutput:
            return ResultCommandDescriptor(
                id: "result-copy",
                title: "复制结果",
                subtitle: "当前结果面板",
                systemImage: "doc.on.doc",
                keywords: "result copy output 复制 结果",
                action: .copyOutput
            )
        case .copyMarkdown:
            return ResultCommandDescriptor(
                id: "result-copy-markdown",
                title: "复制完整结果",
                subtitle: protectsContentExport
                    ? "高风险保护:Markdown 将省略原文和结果正文"
                    : "Markdown,含原文、结果、模型和路由摘要",
                systemImage: "doc.richtext",
                keywords: protectsContentExport
                    ? "result markdown export copy protected privacy hidden 完整 结果 隐私 保护 省略"
                    : "result markdown export copy 完整 结果",
                action: .copyMarkdown
            )
        case .exportConversation:
            return ResultCommandDescriptor(
                id: "result-export",
                title: "导出对话",
                subtitle: protectsContentExport
                    ? "高风险保护:导出的 Markdown 将省略正文"
                    : "保存为 Markdown",
                systemImage: "square.and.arrow.up",
                keywords: protectsContentExport
                    ? "result export markdown protected privacy hidden 导出 对话 隐私 保护 省略"
                    : "result export markdown 导出 对话",
                action: .exportConversation
            )
        case .copyBriefDiagnostics:
            return ResultCommandDescriptor(
                id: "result-copy-brief-diagnostics",
                title: ResultDiagnosticsCommand.briefTitle,
                subtitle: ResultDiagnosticsCommand.briefSubtitle,
                systemImage: ResultDiagnosticsCommand.systemImage,
                keywords: ResultDiagnosticsCommand.briefKeywords,
                action: .copyBriefDiagnostics
            )
        case .copyDiagnostics:
            return ResultCommandDescriptor(
                id: "result-copy-diagnostics",
                title: ResultDiagnosticsCommand.title,
                subtitle: ResultDiagnosticsCommand.subtitle,
                systemImage: ResultDiagnosticsCommand.systemImage,
                keywords: ResultDiagnosticsCommand.keywords,
                action: .copyDiagnostics
            )
        case .openAISettings:
            let recovery = ResultRecoveryCommand.openAISettingsDescriptor(recoveryCode: recoveryCode)
            return ResultCommandDescriptor(
                id: "result-open-ai-settings",
                title: recovery.title,
                subtitle: recovery.subtitle,
                systemImage: recovery.systemImage,
                keywords: recovery.keywords,
                action: .openAISettings
            )
        case .replaceOriginal:
            return ResultCommandDescriptor(
                id: "result-replace",
                title: "替换原文",
                subtitle: "先展示差异预览",
                systemImage: "arrow.uturn.left.square",
                keywords: "result replace writeback 替换 原文",
                action: .replaceOriginal
            )
        case .appendToDocument:
            return ResultCommandDescriptor(
                id: "result-append",
                title: "追加到文档",
                subtitle: "写回当前光标位置",
                systemImage: "text.badge.plus",
                keywords: "result append writeback 追加 文档",
                action: .appendToDocument
            )
        case .stop:
            return ResultCommandDescriptor(
                id: "result-stop",
                title: "停止生成",
                subtitle: "当前结果面板",
                systemImage: "stop.fill",
                keywords: "result stop cancel 停止 生成",
                action: .stop
            )
        case .regenerate:
            let retry = ResultRecoveryCommand.retryDescriptor(recoveryCode: recoveryCode)
            return ResultCommandDescriptor(
                id: "result-regenerate",
                title: retry.title,
                subtitle: retry.subtitle,
                systemImage: retry.systemImage,
                keywords: retry.keywords,
                action: .regenerate
            )
        }
    }

    public static func menuDescriptor(for action: ResultCommandAction) -> ResultMenuCommandDescriptor? {
        menuDescriptors().first { $0.action == action }
    }

    public static func shortcutText(for action: ResultCommandAction) -> String? {
        guard let descriptor = menuDescriptor(for: action) else { return nil }
        guard !descriptor.keyEquivalent.isEmpty else { return nil }
        if descriptor.keyEquivalent == "\u{1b}" {
            return "Esc"
        }
        let prefix = descriptor.modifiers.map(\.displaySymbol).joined()
        let key = descriptor.keyEquivalent == "\r"
            ? "↩"
            : descriptor.keyEquivalent.uppercased()
        return "\(prefix)\(key)"
    }

    public static func helpText(for action: ResultCommandAction) -> String {
        helpText(for: action, protectsContentExport: false)
    }

    public static func helpText(for action: ResultCommandAction,
                                in state: ResultCommandState) -> String {
        let descriptor = descriptor(for: action, in: state)
        let title: String
        if state.protectsContentExport,
           action == .copyMarkdown || action == .exportConversation {
            title = "\(descriptor.title): \(descriptor.subtitle)"
        } else {
            title = descriptor.title
        }
        guard let shortcut = shortcutText(for: action), !shortcut.isEmpty else { return title }
        return "\(title) (\(shortcut))"
    }

    public static func helpText(for action: ResultCommandAction,
                                protectsContentExport: Bool) -> String {
        let descriptor = descriptor(for: action,
                                    protectsContentExport: protectsContentExport,
                                    recoveryCode: nil)
        let title: String
        if protectsContentExport,
           action == .copyMarkdown || action == .exportConversation {
            title = "\(descriptor.title): \(descriptor.subtitle)"
        } else {
            title = descriptor.title
        }
        guard let shortcut = shortcutText(for: action), !shortcut.isEmpty else { return title }
        return "\(title) (\(shortcut))"
    }

    public static func accessibilityLabel(for action: ResultCommandAction,
                                          in state: ResultCommandState) -> String {
        let descriptor = descriptor(for: action,
                                    protectsContentExport: state.protectsContentExport,
                                    recoveryCode: state.recoveryCode)
        if state.protectsContentExport,
           action == .copyMarkdown || action == .exportConversation {
            return "\(descriptor.title), \(descriptor.subtitle)"
        }
        return descriptor.title
    }

    public static func menuTitle(for action: ResultCommandAction,
                                 in state: ResultCommandState) -> String {
        let baseTitle = menuDescriptor(for: action)?.title
            ?? descriptor(for: action,
                          protectsContentExport: state.protectsContentExport,
                          recoveryCode: state.recoveryCode).title
        if action == .openAISettings {
            return descriptor(for: action,
                              protectsContentExport: state.protectsContentExport,
                              recoveryCode: state.recoveryCode).title
        }
        if action == .regenerate, state.recoveryCode != nil {
            return descriptor(for: action,
                              protectsContentExport: state.protectsContentExport,
                              recoveryCode: state.recoveryCode).title
        }
        if state.protectsContentExport,
           action == .copyMarkdown || action == .exportConversation {
            return "\(baseTitle) (省略正文)"
        }
        return baseTitle
    }

    public static func menuToolTip(for action: ResultCommandAction,
                                   in state: ResultCommandState) -> String? {
        guard state.protectsContentExport,
              action == .copyMarkdown || action == .exportConversation else {
            if action == .openAISettings {
                return descriptor(for: action,
                                  protectsContentExport: state.protectsContentExport,
                                  recoveryCode: state.recoveryCode).subtitle
            }
            if action == .regenerate, state.recoveryCode != nil {
                return descriptor(for: action,
                                  protectsContentExport: state.protectsContentExport,
                                  recoveryCode: state.recoveryCode).subtitle
            }
            return nil
        }
        return descriptor(for: action,
                          protectsContentExport: true,
                          recoveryCode: state.recoveryCode).subtitle
    }

    public static func menuDescriptors() -> [ResultMenuCommandDescriptor] {
        [
            ResultMenuCommandDescriptor(
                id: "result-menu-copy",
                title: "复制结果",
                keyEquivalent: "c",
                modifiers: [.command, .shift],
                action: .copyOutput
            ),
            ResultMenuCommandDescriptor(
                id: "result-menu-copy-markdown",
                title: "复制完整结果",
                keyEquivalent: "c",
                modifiers: [.command, .option],
                action: .copyMarkdown
            ),
            ResultMenuCommandDescriptor(
                id: "result-menu-copy-brief-diagnostics",
                title: ResultDiagnosticsCommand.briefTitle,
                keyEquivalent: "d",
                modifiers: [.command, .shift],
                action: .copyBriefDiagnostics
            ),
            ResultMenuCommandDescriptor(
                id: "result-menu-copy-diagnostics",
                title: ResultDiagnosticsCommand.title,
                keyEquivalent: "d",
                modifiers: [.command, .option],
                action: .copyDiagnostics
            ),
            ResultMenuCommandDescriptor(
                id: "result-menu-open-ai-settings",
                title: ResultRecoveryCommand.openAISettingsTitle,
                keyEquivalent: "",
                modifiers: [],
                action: .openAISettings
            ),
            ResultMenuCommandDescriptor(
                id: "result-menu-replace",
                title: "替换原文",
                keyEquivalent: "\r",
                modifiers: [.command],
                action: .replaceOriginal
            ),
            ResultMenuCommandDescriptor(
                id: "result-menu-append",
                title: "追加到文档",
                keyEquivalent: "\r",
                modifiers: [.command, .shift],
                action: .appendToDocument
            ),
            ResultMenuCommandDescriptor(
                id: "result-menu-export",
                title: "导出对话…",
                keyEquivalent: "e",
                modifiers: [.command],
                action: .exportConversation
            ),
            ResultMenuCommandDescriptor(
                id: "result-menu-regenerate",
                title: "重新生成",
                keyEquivalent: "r",
                modifiers: [.command],
                action: .regenerate
            ),
            ResultMenuCommandDescriptor(
                id: "result-menu-stop",
                title: "停止生成",
                keyEquivalent: "\u{1b}",
                modifiers: [],
                action: .stop
            )
        ]
    }

    public static func descriptors(state: ResultCommandState) -> [ResultCommandDescriptor] {
        descriptors(hasResult: state.hasResult,
                    hasDiagnostics: state.hasDiagnostics,
                    canWriteBack: state.canWriteBack,
                    isStreaming: state.isStreaming,
                    hasSourceText: state.hasSourceText,
                    protectsContentExport: state.protectsContentExport,
                    recoveryCode: state.recoveryCode)
    }

    public static func descriptors(hasResult: Bool,
                                   hasDiagnostics: Bool,
                                   canWriteBack: Bool,
                                   isStreaming: Bool,
                                   hasSourceText: Bool,
                                   protectsContentExport: Bool = false,
                                   recoveryCode: String? = nil) -> [ResultCommandDescriptor] {
        var result: [ResultCommandDescriptor] = []
        let trimmedRecoveryCode = recoveryCode?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let hasRecoveryCode = !trimmedRecoveryCode.isEmpty
        let canRegenerate = hasSourceText && !isStreaming
        let canOpenRecoverySettings = hasDiagnostics || hasRecoveryCode
        let regenerateDescriptor = descriptor(for: .regenerate,
                                             protectsContentExport: false,
                                             recoveryCode: recoveryCode)
        let settingsDescriptor = descriptor(for: .openAISettings,
                                            protectsContentExport: false,
                                            recoveryCode: recoveryCode)
        let primaryRecoveryAction = ResultRecoveryCommand.primaryAction(recoveryCode: recoveryCode)

        if hasResult {
            result.append(contentsOf: [
                descriptor(for: .copyOutput),
                descriptor(for: .copyMarkdown,
                           protectsContentExport: protectsContentExport),
                descriptor(for: .exportConversation,
                           protectsContentExport: protectsContentExport)
            ])
        }

        if hasRecoveryCode,
           primaryRecoveryAction == .retry,
           canRegenerate {
            result.append(regenerateDescriptor)
        }

        if hasRecoveryCode,
           primaryRecoveryAction == .settings,
           canOpenRecoverySettings {
            result.append(settingsDescriptor)
        }

        if hasDiagnostics {
            result.append(descriptor(for: .copyBriefDiagnostics))
            result.append(descriptor(for: .copyDiagnostics))
        }

        if canOpenRecoverySettings,
           (!hasRecoveryCode || primaryRecoveryAction == .retry) {
            result.append(settingsDescriptor)
        }

        if canWriteBack {
            result.append(contentsOf: [
                descriptor(for: .replaceOriginal),
                descriptor(for: .appendToDocument)
            ])
        }

        if isStreaming {
            result.append(descriptor(for: .stop))
        } else if canRegenerate,
                  (!hasRecoveryCode || primaryRecoveryAction == .settings) {
            result.append(regenerateDescriptor)
        }

        return result
    }

    public static func isEnabled(_ action: ResultCommandAction, in state: ResultCommandState) -> Bool {
        switch action {
        case .copyOutput, .copyMarkdown, .exportConversation:
            return state.hasResult
        case .copyBriefDiagnostics, .copyDiagnostics, .openAISettings:
            if action == .openAISettings {
                let recoveryCode = state.recoveryCode?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                return state.hasDiagnostics || !recoveryCode.isEmpty
            }
            return state.hasDiagnostics
        case .replaceOriginal, .appendToDocument:
            return state.canWriteBack
        case .stop:
            return state.isStreaming
        case .regenerate:
            return state.hasSourceText && !state.isStreaming
        }
    }
}

public extension ResultMenuModifier {
    var displaySymbol: String {
        switch self {
        case .command:
            return "⌘"
        case .option:
            return "⌥"
        case .shift:
            return "⇧"
        }
    }
}
