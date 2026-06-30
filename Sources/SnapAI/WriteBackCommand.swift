import AppKit

enum WriteBackCommandAction: Equatable {
    case undoLastWriteBack
}

struct WriteBackCommandDescriptor: Equatable {
    var id: String
    var title: String
    var subtitle: String
    var systemImage: String
    var keywords: String
    var shortcutText: String
    var action: WriteBackCommandAction
}

enum WriteBackCommandFactory {
    static let undoShortcutText = "⌘⌥Z"

    static func undoDescriptor(for record: TextWriteBackRecord?) -> WriteBackCommandDescriptor? {
        guard let record, record.isUndoAvailable else { return nil }
        return WriteBackCommandDescriptor(
            id: "undo-write-back",
            title: record.undoTitle,
            subtitle: undoSubtitle(for: record.operation),
            systemImage: "arrow.uturn.backward",
            keywords: undoKeywords(for: record.operation),
            shortcutText: undoShortcutText,
            action: .undoLastWriteBack
        )
    }

    static func undoMenuTitle(for record: TextWriteBackRecord?) -> String {
        undoDescriptor(for: record)?.title ?? "撤销上次写回"
    }

    static func statusSummary(for record: TextWriteBackRecord?,
                              fallback: String?) -> String? {
        record?.diagnosticSummary ?? fallback
    }

    static func undoSubtitle(for operation: TextWriteBackOperation) -> String {
        switch operation {
        case .replace:
            return "恢复替换前的原文"
        case .append:
            return "移除上次追加内容"
        }
    }

    static func undoKeywords(for operation: TextWriteBackOperation) -> String {
        switch operation {
        case .replace:
            return "undo replace writeback revert 撤销 替换 写回 恢复"
        case .append:
            return "undo append writeback revert 撤销 追加 写回 移除"
        }
    }
}
