import AppKit
import SnapAILogic

/// 全局热键装配:注册、失败清单与设置变更后的重注册。
///
/// 从 AppDelegate 抽出:HotKeyCoordinator(SnapAILogic)负责冲突判定与
/// 注册表,本类型持有「这一次注册的结果」,供权限健康中心与状态栏菜单读取。
/// 只持有 weak host,失败清单不再挂在 AppDelegate 上。
@MainActor
final class HotKeyRegistrationCoordinator {
    private weak var host: AppDelegate?
    private let coordinator = HotKeyCoordinator()

    /// 注册失败清单(组合键冲突/被占用),权限健康中心与状态栏菜单读取。
    private(set) var failures: [String] = []

    init(host: AppDelegate) {
        self.host = host
    }

    func register() {
        guard let host else { return }
        failures = coordinator.registerAll(
            settings: host.settings,
            actionHandler: { [weak host] actionID in
                host?.triggerAction(id: actionID)
            },
            quickPanelHandler: { [weak host] in
                host?.toggleQuickInput()
            }
        )
    }
}
