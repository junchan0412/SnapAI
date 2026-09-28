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

    /// 打开双模型对照:以当前结果原文为准,左侧为当前模型输出,
    /// 右侧为首个备选路由输出(占位:当前为同一输出的差异演示,待双跑接入后替换)。
    func openModelCompare() {
        guard let host else { return }
        let settings = host.settings
        let resultVM: ResultViewModel = host.resultVM
        let routes = AIRequestRouter.candidates(settings: settings,
                                                action: resultVM.action,
                                                sourceText: resultVM.sourceText,
                                                hasImage: false,
                                                routingTextCharacterCount: max(resultVM.sourceText.count, 1_200))
        let leftTitle = routeTitle(at: 0, routes: routes, settings: settings)
        let rightTitle = routeTitle(at: 1, routes: routes, settings: settings)
        let comparison = ModelCompare.compare(
            left: .init(title: leftTitle, text: resultVM.completeText),
            right: .init(title: rightTitle, text: resultVM.completeText))
        host.compareWindow.show(comparison: comparison, sourceText: resultVM.sourceText)
    }

    private func routeTitle(at index: Int, routes: [AIRequestRoute], settings: AppSettings) -> String {
        guard routes.indices.contains(index) else {
            return index == 0 ? settings.modelSelectionTitle : "备选模型"
        }
        let route = routes[index]
        return "\(route.providerName) / \(route.modelName)"
    }
}
