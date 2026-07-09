import Combine
import Foundation

public final class SettingsWindowPinState: ObservableObject {
    @Published public var isPinned: Bool

    public init(isPinned: Bool = false) {
        self.isPinned = isPinned
    }
}

public enum SettingsWindowPinCommand {
    public static func title(isPinned: Bool) -> String {
        isPinned ? "取消置顶设置窗口" : "置顶设置窗口"
    }

    public static func subtitle(isPinned: Bool) -> String {
        isPinned ? "当前设置窗口会保持在其他窗口上方" : "打开设置并保持在其他窗口上方"
    }

    public static func systemImage(isPinned: Bool) -> String {
        isPinned ? "pin.slash" : "pin.fill"
    }

    public static func statusSystemImage(isPinned: Bool) -> String {
        isPinned ? "pin.fill" : "pin"
    }

    public static func accessibilityValue(isPinned: Bool) -> String {
        isPinned ? "已置顶" : "未置顶"
    }

    public static let keywords = "settings pin window floating top preferences 设置 置顶 窗口 固定"
}
