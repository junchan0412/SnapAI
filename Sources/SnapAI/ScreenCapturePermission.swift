import ApplicationServices
import Foundation

enum ScreenCapturePermission {
    static let recoveryMessage = "请在系统设置 -> 隐私与安全性 -> 屏幕录制中允许 SnapAI 后重试。"

    static func isGranted(preflight: () -> Bool = { CGPreflightScreenCaptureAccess() }) -> Bool {
        preflight()
    }
}
