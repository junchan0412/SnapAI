import Foundation

enum SettingsWindowPinCommand {
    static func title(isPinned: Bool) -> String {
        isPinned ? "取消置顶设置窗口" : "置顶设置窗口"
    }

    static func subtitle(isPinned: Bool) -> String {
        isPinned ? "当前设置窗口会保持在其他窗口上方" : "打开设置并保持在其他窗口上方"
    }

    static func systemImage(isPinned: Bool) -> String {
        isPinned ? "pin.slash" : "pin.fill"
    }

    static let keywords = "settings pin window floating top preferences 设置 置顶 窗口 固定"
}
