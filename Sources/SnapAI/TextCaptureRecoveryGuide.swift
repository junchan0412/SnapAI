import Foundation

enum TextCaptureRecoveryGuide {
    static let title = "未检测到选中的文字"
    static let defaultButtonTitle = "好"
    static let quickInputButtonTitle = "打开快捷提问"
    static let permissionHealthButtonTitle = "打开权限健康中心"
    static let accessibilitySettingsButtonTitle = "打开辅助功能设置"

    static let message = [
        "请先在当前应用中选中一段文字,再触发 SnapAI。",
        "如果反复失败,通常与辅助功能权限、目标应用选区兼容性或剪贴板复制兜底有关。",
        "你也可以打开快捷提问直接输入问题,或前往权限健康中心查看状态。"
    ].joined(separator: "\n")

    static var accessibilitySettingsURL: URL {
        SystemPrivacySettings.accessibilityURL
    }
}
