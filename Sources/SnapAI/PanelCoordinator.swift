import AppKit
import SnapAILogic

/// 面板编排:快捷提问、结果面板、双模型对照的显示编排。
///
/// 从 AppDelegate 抽出:只负责「哪个面板此刻该不该出现」,取词、提交、
/// 写回仍在 SubmissionPipeline / AppDelegate 扩展里。与 SubmissionPipeline
/// 同一约束:只持有 weak host,不新增行为。
@MainActor
final class PanelCoordinator {
    private weak var host: AppDelegate?

    init(host: AppDelegate) {
        self.host = host
    }

    /// 状态栏/命令面板/快捷键入口的统一开关:先记下要还焦的前台 App,再切面板。
    func toggleQuickInput() {
        guard let host else { return }
        host.previousApp = host.currentCaptureTargetApp()
        host.previousSelectionSnapshot = nil
        host.previousCaptureMethod = nil
        host.quickInput.toggle()
    }

    /// #bug2 「未检测到选中的文字」改为非模态提示:在结果窗口显示瞬时横幅,不再弹出阻塞式模态 alert。
    /// 动作已在执行时不打扰(guard !isStreaming);快捷提问/权限中心入口由用户从状态栏菜单进入。
    func showNoSelectionNotice(action: AIAction? = nil) {
        guard let host, !host.resultVM.isStreaming else { return }
        host.resultVM.showTransientNotice(TextCaptureRecoveryGuide.title)
        host.panelController.show()
    }

    /// Dock/访达图标被点击且无可见窗口时补开设置窗口。
    func handleReopen(hasVisibleWindows: Bool) -> Bool {
        guard let host, !host.launch.isLaunchSmoke else { return false }
        if !hasVisibleWindows {
            host.openSettings()
        }
        return true
    }

    func openModelCompare() {
        guard let host else { return }
        guard let resultVM = host.resultVM else { return }
        guard !resultVM.isGenerating else {
            resultVM.showTransientNotice("请等待当前生成完成后再打开双模型对照。")
            return
        }
        host.compareWindow.show(session: ModelCompareSession(settings: host.settings,
                                                             action: resultVM.action,
                                                             messages: resultVM.comparisonMessages))
    }
}
