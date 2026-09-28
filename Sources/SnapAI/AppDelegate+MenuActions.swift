import AppKit
import SnapAILogic

/// 菜单动作:状态栏菜单与主菜单的 @objc 入口。
///
/// 菜单装配在 `StatusMenuBuilder` / `MainMenuBuilder`,装配代码里的
/// `#selector` 全部指向这里的 host 方法 —— 点击行为归属不变。
extension AppDelegate {
    @objc func triggerActionFromMenu(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String else { return }
        triggerAction(id: id)
    }

    @objc func toggleQuickInputFromMenu(_ sender: Any?) {
        toggleQuickInput()
    }

    @objc func openSettingsFromMenu(_ sender: Any?) {
        openSettings()
    }

    @objc func checkForUpdatesFromMenu(_ sender: Any?) {
        checkForUpdates()
    }

    @objc func switchModel(_ sender: NSMenuItem) {
        guard let info = sender.representedObject as? [String: String],
              let pid = info["provider"], let model = info["model"] else { return }
        settings.activate(providerID: pid, model: model, recordManualPreference: true)
        buildMenu()
        installMainMenu()
    }

    @objc func selectWorkModeFromMenu(_ sender: NSMenuItem) {
        guard let rawValue = sender.representedObject as? String,
              let mode = WorkModePreset(rawValue: rawValue) else {
            showSettings(section: .general)
            return
        }
        applyWorkMode(mode)
    }

    @objc func reopenHistory(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String,
              let entry = settings.history.first(where: { $0.id == id }) else { return }
        reopenHistoryEntry(entry)
    }

    func reopenHistoryEntry(_ entry: HistoryEntry) {
        // 用历史里的原文 + 同名动作重新发起
        guard let sourceText = entry.reopenSourceText else { return }
        let historyActionName = HistoryFilterCriteria.normalizedFacetValue(entry.actionName)
        let action = settings.enabledActions.first {
            HistoryFilterCriteria.normalizedFacetValue($0.name) == historyActionName
        }
            ?? settings.enabledActions.first
        guard let action else { return }
        previousApp = currentCaptureTargetApp()
        resultVM.start(text: sourceText, action: action, autoReplaceEnabled: false)
        panelController.show()
    }

    @objc func clearHistory() {
        settings.clearHistory()
        buildMenu()
    }
}
