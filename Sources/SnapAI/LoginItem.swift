import Foundation
import ServiceManagement

/// 开机自启动封装,基于 macOS 13+ 的 SMAppService。
enum LoginItem {

    /// 当前是否已注册为登录项
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    /// 设置开机自启。返回是否成功。
    @discardableResult
    static func setEnabled(_ enabled: Bool) -> Bool {
        do {
            if enabled {
                if SMAppService.mainApp.status != .enabled {
                    try SMAppService.mainApp.register()
                }
            } else {
                if SMAppService.mainApp.status == .enabled {
                    try SMAppService.mainApp.unregister()
                }
            }
            return true
        } catch {
            NSLog("SnapAI: 设置开机自启失败 - \(error.localizedDescription)")
            return false
        }
    }
}
