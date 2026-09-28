import CoreGraphics
import Foundation

// 打印指定 owner 进程最前面的 on-screen 窗口 ID,供 screencapture -l 使用。
// CGWindowListCopyWindowInfo 的窗口号与 owner 名不需要辅助功能权限,
// 截图本身仍需「屏幕录制」权限(与手工截图一致)。
let owner = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "SnapAI Preview"
guard let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] else {
    exit(2)
}
for window in windows {
    guard let name = window[kCGWindowOwnerName as String] as? String, name == owner else { continue }
    // 列表按 z 序从前到后;浮动面板(结果/快捷提问)层级不为 0,不按 layer 过滤。
    guard let number = window[kCGWindowNumber as String] as? Int else { continue }
    print(number)
    exit(0)
}
exit(1)
