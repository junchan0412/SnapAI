import Foundation

enum ResultPinCommand {
    static func title(isPinned: Bool) -> String {
        isPinned ? "取消固定结果窗" : "固定结果窗"
    }

    static func subtitle(isPinned: Bool) -> String {
        isPinned ? "当前结果窗会保持打开" : "保持结果窗打开,便于继续追问"
    }

    static func systemImage(isPinned: Bool) -> String {
        isPinned ? "pin.slash" : "pin.fill"
    }

    static let statusTitle = "已固定"
    static let statusSystemImage = "pin.fill"
    static let keywords = "result pin window floating top keep 固定 结果 窗口 置顶"
    static let keyEquivalent = "p"
    static let modifiers: [ResultMenuModifier] = [.command, .shift]
    static var shortcutText: String {
        modifiers.map(\.displaySymbol).joined() + keyEquivalent.uppercased()
    }
}
