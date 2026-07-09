import Foundation

public enum TextCaptureRecoveryGuide {
    public static let title = "未检测到选中的文字"
    public static let defaultButtonTitle = "好"
    public static let quickInputButtonTitle = "打开快捷提问"
    public static let permissionHealthButtonTitle = "打开权限健康中心"
    public static let accessibilitySettingsButtonTitle = "打开辅助功能设置"

    public static let message = [
        "请先在当前应用中选中一段文字,再触发 SnapAI。",
        "如果反复失败,通常与辅助功能权限、目标应用选区兼容性或剪贴板复制兜底有关。",
        "你也可以打开快捷提问直接输入问题,或前往权限健康中心查看状态。"
    ].joined(separator: "\n")

    public static var accessibilitySettingsURL: URL {
        SystemPrivacySettings.accessibilityURL
    }
}
