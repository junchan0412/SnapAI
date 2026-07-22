import SwiftUI
import AppKit
import SnapAILogic

extension HistoryWindowView {
    func createContextProfileFromFilteredHistory() {
        let presentation = model.presentation
        guard let draft = HistoryContextProfileBuilder.draft(entries: presentation.entries,
                                                              criteria: presentation.criteria) else {
            return
        }
        let willUpdate = settings.hasContextProfile(named: draft.name)

        let alert = NSAlert()
        alert.messageText = willUpdate ? "更新上下文包?" : "创建上下文包?"
        alert.informativeText = """
        将当前筛选中的 \(draft.includedCount) 条历史写入「\(draft.name)」并设为使用中。

        已跳过 \(draft.skippedCount) 条空内容、仅元信息或超出上限的记录。
        """
        alert.alertStyle = .informational
        alert.addButton(withTitle: willUpdate ? "更新并启用" : "创建并启用")
        alert.addButton(withTitle: "取消")

        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let result = settings.upsertContextProfile(from: draft)
        iCloudSync.shared.scheduleUpload(settings)

        // 成功结果改为非模态反馈横幅,避免再用一个模态弹窗打断用户。
        operationCoordinator.showSuccess(
            result.didUpdate
                ? "上下文包「\(result.profile.name)」已更新并启用"
                : "上下文包「\(result.profile.name)」已创建并启用"
        )
    }

    func historyCollectionExport(date: Date = Date()) -> HistoryCollectionExport {
        HistoryCollectionExport(entries: model.presentation.entries,
                                criteria: model.presentation.criteria,
                                date: date)
    }

    func parseTags(_ text: String) -> [String] {
        let separators = CharacterSet(charactersIn: ",，;；")
        return text.components(separatedBy: separators)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    func tagBinding(for entry: HistoryEntry) -> Binding<String> {
        Binding(
            get: { model.tagDrafts[entry.id] ?? entry.displayTags.joined(separator: ", ") },
            set: { model.tagDrafts[entry.id] = $0 }
        )
    }

    func commitTagDraft(id: String) {
        guard let draft = model.tagDrafts[id] else { return }
        settings.updateHistoryTags(id: id, tags: parseTags(draft))
        model.tagDrafts[id] = nil
    }

    func commitTagDrafts(except focusedID: String?) {
        for id in Array(model.tagDrafts.keys) where id != focusedID {
            commitTagDraft(id: id)
        }
    }
}
