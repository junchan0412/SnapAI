import Foundation

public enum WriteBackCommandAction: Equatable {
    case undoLastWriteBack
}

public enum WriteBackCommandOperation: Equatable {
    case replace
    case append
}

public struct WriteBackCommandInput: Equatable {
    public var undoTitle: String
    public var operation: WriteBackCommandOperation
    public var diagnosticSummary: String
    public var isUndoAvailable: Bool

    public init(undoTitle: String,
                operation: WriteBackCommandOperation,
                diagnosticSummary: String,
                isUndoAvailable: Bool) {
        self.undoTitle = undoTitle
        self.operation = operation
        self.diagnosticSummary = diagnosticSummary
        self.isUndoAvailable = isUndoAvailable
    }
}

public struct WriteBackCommandDescriptor: Equatable {
    public var id: String
    public var title: String
    public var subtitle: String
    public var systemImage: String
    public var keywords: String
    public var shortcutText: String
    public var action: WriteBackCommandAction

    public init(id: String,
                title: String,
                subtitle: String,
                systemImage: String,
                keywords: String,
                shortcutText: String,
                action: WriteBackCommandAction) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.systemImage = systemImage
        self.keywords = keywords
        self.shortcutText = shortcutText
        self.action = action
    }
}

public enum WriteBackCommandFactory {
    public static let undoShortcutText = "⌘⌥Z"

    public static func undoDescriptor(for input: WriteBackCommandInput?) -> WriteBackCommandDescriptor? {
        guard let input, input.isUndoAvailable else { return nil }
        return WriteBackCommandDescriptor(
            id: "undo-write-back",
            title: input.undoTitle,
            subtitle: undoSubtitle(for: input.operation),
            systemImage: "arrow.uturn.backward",
            keywords: undoKeywords(for: input.operation),
            shortcutText: undoShortcutText,
            action: .undoLastWriteBack
        )
    }

    public static func undoMenuTitle(for input: WriteBackCommandInput?) -> String {
        undoDescriptor(for: input)?.title ?? "撤销上次写回"
    }

    public static func statusSummary(for input: WriteBackCommandInput?,
                                     fallback: String?) -> String? {
        input?.diagnosticSummary ?? fallback
    }

    public static func undoSubtitle(for operation: WriteBackCommandOperation) -> String {
        switch operation {
        case .replace:
            return "恢复替换前的原文"
        case .append:
            return "移除上次追加内容"
        }
    }

    public static func undoKeywords(for operation: WriteBackCommandOperation) -> String {
        switch operation {
        case .replace:
            return "undo replace writeback revert 撤销 替换 写回 恢复"
        case .append:
            return "undo append writeback revert 撤销 追加 写回 移除"
        }
    }
}
