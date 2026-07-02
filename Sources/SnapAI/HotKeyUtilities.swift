import AppKit
import Carbon.HIToolbox

extension HotKeyCombo {
    static let unset = HotKeyCombo(keyCode: 0, modifiers: 0)
    static let quickPanelDefault = HotKeyCombo(keyCode: UInt32(kVK_Space), modifiers: UInt32(optionKey))

    var isUnset: Bool { modifiers == 0 }

    var nsModifierFlags: NSEvent.ModifierFlags {
        var flags: NSEvent.ModifierFlags = []
        if modifiers & UInt32(controlKey) != 0 { flags.insert(.control) }
        if modifiers & UInt32(optionKey) != 0 { flags.insert(.option) }
        if modifiers & UInt32(shiftKey) != 0 { flags.insert(.shift) }
        if modifiers & UInt32(cmdKey) != 0 { flags.insert(.command) }
        return flags
    }

    var keyEquivalent: String {
        KeyCodeMap.keyEquivalent(for: keyCode)
    }
}

enum HotKeyConflictDetector {
    struct Conflict: Equatable {
        enum Target: Equatable {
            case action(id: String)
            case quickPanel
        }

        var title: String
        var target: Target
    }

    static func conflict(for combo: HotKeyCombo,
                         actions: [AIAction],
                         excludingActionID: String?,
                         quickPanelHotKey: HotKeyCombo?,
                         includeQuickPanel: Bool) -> String? {
        conflictDetail(for: combo,
                       actions: actions,
                       excludingActionID: excludingActionID,
                       quickPanelHotKey: quickPanelHotKey,
                       includeQuickPanel: includeQuickPanel)?.title
    }

    static func conflictDetail(for combo: HotKeyCombo,
                               actions: [AIAction],
                               excludingActionID: String?,
                               quickPanelHotKey: HotKeyCombo?,
                               includeQuickPanel: Bool) -> Conflict? {
        guard !combo.isUnset else { return nil }
        for other in actions where other.id != excludingActionID {
            if other.hotKey == combo {
                return Conflict(title: other.name, target: .action(id: other.id))
            }
        }
        if includeQuickPanel, let quickPanelHotKey, quickPanelHotKey == combo {
            return Conflict(title: "快捷提问面板", target: .quickPanel)
        }
        return nil
    }

    static func systemWarning(for combo: HotKeyCombo) -> String? {
        guard !combo.isUnset else { return nil }
        let commandOnly = combo.nsModifierFlags == [.command]
        let commandOption = combo.nsModifierFlags == [.command, .option]
        if commandOnly {
            switch Int(combo.keyCode) {
            case kVK_ANSI_Q: return "⌘Q 通常用于退出应用。"
            case kVK_ANSI_W: return "⌘W 通常用于关闭窗口。"
            case kVK_ANSI_H: return "⌘H 通常用于隐藏应用。"
            case kVK_ANSI_M: return "⌘M 通常用于最小化窗口。"
            case kVK_ANSI_A: return "⌘A 通常用于全选。"
            case kVK_ANSI_C: return "⌘C 通常用于复制。"
            case kVK_ANSI_V: return "⌘V 通常用于粘贴。"
            case kVK_ANSI_X: return "⌘X 通常用于剪切。"
            case kVK_ANSI_Z: return "⌘Z 通常用于撤销。"
            case kVK_ANSI_S: return "⌘S 通常用于保存。"
            case kVK_ANSI_P: return "⌘P 通常用于打印。"
            case kVK_ANSI_N: return "⌘N 通常用于新建。"
            default: break
            }
        }
        if commandOnly && combo.keyCode == UInt32(kVK_Space) {
            return "⌘Space 通常被系统用于 Spotlight 或输入法切换。"
        }
        if commandOption && combo.keyCode == UInt32(kVK_Escape) {
            return "⌘⌥Esc 通常用于强制退出应用。"
        }
        return nil
    }
}

enum HotKeyRecorderText {
    static let recordingTitle = "录制中..."
    static let unsetTitle = "未设置"
    static let instructions = "点击录制;按 Esc 取消,Delete 清除。建议使用 ⌥ 或 ⌃⌥ 组合,避开系统保留快捷键。"
    static let recordingHelp = "按下带修饰键的组合键完成录制;Esc 取消本次录制,Delete 清除快捷键。"
    static let idleHelp = "点击后录制全局快捷键。Esc 取消,Delete 清除。"

    static func title(for combo: HotKeyCombo, recording: Bool) -> String {
        if recording { return recordingTitle }
        return combo.isUnset ? unsetTitle : combo.displayString
    }

    static func help(for combo: HotKeyCombo, recording: Bool) -> String {
        if recording { return recordingHelp }
        if combo.isUnset { return "\(idleHelp) 当前未设置快捷键。" }
        if let warning = HotKeyConflictDetector.systemWarning(for: combo) {
            return "\(idleHelp) \(warning)"
        }
        return "\(idleHelp) 当前为 \(combo.displayString)。"
    }
}

extension KeyCodeMap {
    static func keyEquivalent(for keyCode: UInt32) -> String {
        switch Int(keyCode) {
        case kVK_ANSI_A: return "a"
        case kVK_ANSI_B: return "b"
        case kVK_ANSI_C: return "c"
        case kVK_ANSI_D: return "d"
        case kVK_ANSI_E: return "e"
        case kVK_ANSI_F: return "f"
        case kVK_ANSI_G: return "g"
        case kVK_ANSI_H: return "h"
        case kVK_ANSI_I: return "i"
        case kVK_ANSI_J: return "j"
        case kVK_ANSI_K: return "k"
        case kVK_ANSI_L: return "l"
        case kVK_ANSI_M: return "m"
        case kVK_ANSI_N: return "n"
        case kVK_ANSI_O: return "o"
        case kVK_ANSI_P: return "p"
        case kVK_ANSI_Q: return "q"
        case kVK_ANSI_R: return "r"
        case kVK_ANSI_S: return "s"
        case kVK_ANSI_T: return "t"
        case kVK_ANSI_U: return "u"
        case kVK_ANSI_V: return "v"
        case kVK_ANSI_W: return "w"
        case kVK_ANSI_X: return "x"
        case kVK_ANSI_Y: return "y"
        case kVK_ANSI_Z: return "z"
        case kVK_ANSI_0: return "0"
        case kVK_ANSI_1: return "1"
        case kVK_ANSI_2: return "2"
        case kVK_ANSI_3: return "3"
        case kVK_ANSI_4: return "4"
        case kVK_ANSI_5: return "5"
        case kVK_ANSI_6: return "6"
        case kVK_ANSI_7: return "7"
        case kVK_ANSI_8: return "8"
        case kVK_ANSI_9: return "9"
        case kVK_Space: return " "
        case kVK_Return: return "\r"
        case kVK_Escape: return "\u{1b}"
        default: return ""
        }
    }
}
