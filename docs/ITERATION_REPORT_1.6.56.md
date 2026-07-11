# SnapAI 1.6.56 迭代报告

## 问题定位

release 构建首次显示设置窗口时 physical footprint 约为 48–50 MB。旧实现将 `settingsWindow` 强持有且设置 `isReleasedWhenClosed = false`,关闭后完整 SwiftUI 内容仍驻留,实测 footprint 可增长并停留在约 81 MB。

## 生命周期方案

- 继续复用 `NSWindow` shell,避免反复创建 AppKit window 对象。
- `windowWillClose` 不在 AppKit 关闭回调栈内直接销毁内容,而是在下一轮主线程清空 `contentViewController`。
- 重开窗口时检测 content 是否为空,仅在需要时创建新的 `NSHostingController`。
- settings navigation 和 pin state 保存在 coordinator 中,释放 UI 不会丢失用户上下文。

## 崩溃审计

初版尝试使用 `isReleasedWhenClosed = true` 并同时解除 Swift 强引用。真实 Accessibility 关闭测试捕获到 `EXC_BAD_ACCESS`,调用栈位于 `objc_release` / `AutoreleasePoolPage::releaseUntil`。最终方案恢复 ARC 单一所有权,只释放重型 content hierarchy。

## 测量与门禁

- 新增统一 runtime memory snapshot 脚本。
- 新增 reusable window content release macOS smoke。
- remediation gate 防止恢复自动 release 或删除延迟重建逻辑。

## 当前结果

- 设置窗口 release build 初始 footprint:48–50 MB。
- 关闭内容释放策略通过独立 AppKit lifecycle smoke。
- SwiftPM build、target boundary 和 remediation gate 通过。
