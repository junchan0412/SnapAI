import ApplicationServices
import Foundation

// 无障碍走查:遍历目标应用窗口的 AX 树,报告「可交互但没有可读名称」的控件。
// VoiceOver 朗读的正是这棵树,所以本脚本等价于对窗口内容做一次 VoiceOver 名称走查;
// 朗读顺序、rotor、实时播报与纯键盘 Tab 顺序仍需人工过一遍,
// 清单见 docs/ACCESSIBILITY_WALKTHROUGH.md。
//
// SwiftUI 常把可见标签渲染成控件旁边的兄弟静态文本(而不是控件自身的 label),
// 因此报告里附带「同一父节点下、位于该控件之前的最近一条静态文本」,直接指向
// 该补的 accessibilityLabel 文案。
//
// 用法: ax-audit <pid> [--menu] [--tree]
//       --menu 连主菜单一起走;--tree 打印整棵树(角色 + 可读名称 + 最近静态文本)。

let args = CommandLine.arguments
guard args.count > 1, let pid = pid_t(args[1]) else {
    fputs("usage: ax-audit <pid> [--menu] [--tree]\n", stderr)
    exit(2)
}
let includeMenu = args.contains("--menu")
let printTree = args.contains("--tree")

// 系统窗口按钮(关闭/最小化/缩放/全屏)与滚动条/步进器的箭头子控件由 AppKit 提供,
// 名字挂在父元素(AXScrollBar / AXIncrementor)上,不在本仓库可改范围内。
let systemSubroles: Set<String> = [
    "AXCloseButton", "AXMinimizeButton", "AXZoomButton", "AXFullScreenButton",
    "AXIncrementArrow", "AXDecrementArrow", "AXIncrementPage", "AXDecrementPage"
]
let systemRoles: Set<String> = ["AXScrollBar", "AXValueIndicator"]

let interactive: Set<String> = [
    "AXButton", "AXCheckBox", "AXRadioButton", "AXTextField", "AXTextArea",
    "AXPopUpButton", "AXComboBox", "AXSlider", "AXLink", "AXMenuItem", "AXMenuItemCheckbox",
    "AXIncrementor", "AXSearchField"
]

func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
    var value: CFTypeRef?
    let error = AXUIElementCopyAttributeValue(element, name as CFString, &value)
    return error == .success ? value : nil
}

/// 可读名称:VoiceOver 依次看 Title → Description → Help → Value(静态文本正文在 Value)。
func accessibleName(_ element: AXUIElement, role: String) -> String {
    let title = attribute(element, kAXTitleAttribute as String) as? String ?? ""
    let description = attribute(element, kAXDescriptionAttribute as String) as? String ?? ""
    let help = attribute(element, kAXHelpAttribute as String) as? String ?? ""
    let value = role == "AXStaticText" ? ((attribute(element, kAXValueAttribute as String) as? String) ?? "") : ""
    for candidate in [title, description, help, value] where !candidate.trimmingCharacters(in: .whitespaces).isEmpty {
        return candidate
    }
    return ""
}

var unlabeled: [(role: String, context: String)] = []
var inspected = 0

/// `siblingLabel`:同一父节点下、位于该元素之前的最近一条静态文本。
func walk(_ element: AXUIElement, path: String, depth: Int, siblingLabel: String) {
    guard depth <= 12 else { return }
    inspected += 1

    let role = attribute(element, kAXRoleAttribute as String) as? String ?? "?"
    let subrole = attribute(element, kAXSubroleAttribute as String) as? String ?? ""
    let name = accessibleName(element, role: role)
    let isSystemButton = systemSubroles.contains(subrole) || systemRoles.contains(role)
    let missingName = interactive.contains(role) && !isSystemButton && name.isEmpty

    if printTree {
        let mark = missingName ? "  <-- 无可读名称" : ""
        let suffix = subrole.isEmpty ? "" : " [\(subrole)]"
        let sibling = missingName && !siblingLabel.isEmpty
            ? "   (最近静态文本: \(siblingLabel.prefix(40)))" : ""
        print(String(repeating: "  ", count: max(0, depth))
              + "\(role)\(suffix) | \(name.isEmpty ? "-" : String(name.prefix(48)))\(mark)\(sibling)")
    }
    if missingName {
        let context = siblingLabel.isEmpty ? path : "\(path) | 最近静态文本: \(siblingLabel.prefix(40))"
        unlabeled.append((role, context))
    }

    let childPath: String = {
        if name.isEmpty { return path }
        let short = String(name.prefix(40))
        return path.isEmpty ? short : "\(path) → \(short)"
    }()
    guard let children = attribute(element, kAXChildrenAttribute as String) as? [AXUIElement] else { return }

    // 系统子控件(滚动条箭头等)不参与报告,但仍然遍历以便 --tree 完整。
    if systemRoles.contains(role) || !systemSubroles.isDisjoint(with: [subrole]) {
        if printTree {
            for child in children {
                let childRole = attribute(child, kAXRoleAttribute as String) as? String ?? "?"
                let childSubrole = attribute(child, kAXSubroleAttribute as String) as? String ?? ""
                let childName = accessibleName(child, role: childRole)
                print(String(repeating: "  ", count: depth + 1)
                      + "\(childRole)\(childSubrole.isEmpty ? "" : " [\(childSubrole)]") | \(childName.isEmpty ? "-" : String(childName.prefix(48))) (系统子控件,不计)")
            }
        }
        return
    }

    var inheritedLabel = siblingLabel
    for child in children {
        let childRole = attribute(child, kAXRoleAttribute as String) as? String ?? ""
        let childName = accessibleName(child, role: childRole)
        if childRole == "AXStaticText", !childName.isEmpty {
            inheritedLabel = childName
        } else if !childName.isEmpty {
            // 控件自己有名字,兄弟文本不再归属于它后面的控件。
            inheritedLabel = ""
        }
        walk(child, path: childPath, depth: depth + 1, siblingLabel: inheritedLabel)
    }
}

let app = AXUIElementCreateApplication(pid)
if includeMenu, let menus = attribute(app, kAXMenuBarAttribute as String) as? [AXUIElement] {
    for menu in menus { walk(menu, path: "菜单栏", depth: 0, siblingLabel: "") }
}
guard let windows = attribute(app, kAXWindowsAttribute as String) as? [AXUIElement] else {
    fputs("error: 读不到窗口列表(需要辅助功能权限)\n", stderr)
    exit(3)
}
for (index, window) in windows.enumerated() {
    let title = attribute(window, kAXTitleAttribute as String) as? String ?? "窗口\(index + 1)"
    walk(window, path: title, depth: 0, siblingLabel: "")
}

print("已遍历元素: \(inspected)")
if unlabeled.isEmpty {
    print("无可访问名称的交互控件: 0")
} else {
    print("无可访问名称的交互控件: \(unlabeled.count)")
    for item in unlabeled { print("  [\(item.role)] \(item.context)") }
    exit(1)
}
