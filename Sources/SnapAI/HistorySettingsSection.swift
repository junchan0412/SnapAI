import SnapAILogic
import SwiftUI

/// 主窗口「历史与会话」页：直接承载完整的分栏历史搜索、会话恢复与保留策略管理，消除重复窗口与残缺列表。
struct HistorySettingsSection: View {
    @ObservedObject var settings: AppSettings
    let commit: () -> Void
    var onReopen: (HistoryEntry) -> Void = { _ in }
    var onResume: ((ConversationSession) -> Void)? = nil

    @StateObject private var modelHolder: HistorySectionModelHolder

    init(settings: AppSettings,
         commit: @escaping () -> Void,
         onReopen: @escaping (HistoryEntry) -> Void = { _ in },
         onResume: ((ConversationSession) -> Void)? = nil) {
        self.settings = settings
        self.commit = commit
        self.onReopen = onReopen
        self.onResume = onResume
        _modelHolder = StateObject(wrappedValue: HistorySectionModelHolder(settings: settings))
    }

    var body: some View {
        HistoryWindowView(settings: settings,
                          model: modelHolder.model,
                          reopen: onReopen,
                          resume: onResume,
                          embeddedInWorkspace: true,
                          onSettingsCommit: commit)
    }
}

@MainActor
private final class HistorySectionModelHolder: ObservableObject {
    let model: HistoryWindowModel
    init(settings: AppSettings) {
        self.model = HistoryWindowModel(settings: settings)
    }
}
