import Foundation

public enum ResultPinCommand {
    public static func title(isPinned: Bool) -> String {
        isPinned ? "取消固定结果窗" : "固定结果窗"
    }

    public static func subtitle(isPinned: Bool) -> String {
        isPinned ? "当前结果窗会保持打开" : "保持结果窗打开,便于继续追问"
    }

    public static func systemImage(isPinned: Bool) -> String {
        isPinned ? "pin.slash" : "pin.fill"
    }

    public static let statusTitle = "已固定"
    public static let statusSystemImage = "pin.fill"
    public static let keywords = "result pin window floating top keep 固定 结果 窗口 置顶"
    public static let keyEquivalent = "p"
    public static let modifiers: [ResultMenuModifier] = [.command, .shift]
    public static var shortcutText: String {
        modifiers.map(\.displaySymbol).joined() + keyEquivalent.uppercased()
    }
}
