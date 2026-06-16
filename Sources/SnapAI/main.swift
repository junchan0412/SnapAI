import AppKit

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
// 激活策略由 AppDelegate 按用户设置(是否显示 Dock 图标)决定
app.run()
