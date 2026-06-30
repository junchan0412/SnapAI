import Combine
import Foundation

final class SettingsWindowPinState: ObservableObject {
    @Published var isPinned: Bool

    init(isPinned: Bool = false) {
        self.isPinned = isPinned
    }
}

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

    static func statusSystemImage(isPinned: Bool) -> String {
        isPinned ? "pin.fill" : "pin"
    }

    static func accessibilityValue(isPinned: Bool) -> String {
        isPinned ? "已置顶" : "未置顶"
    }

    static let keywords = "settings pin window floating top preferences 设置 置顶 窗口 固定"
}
