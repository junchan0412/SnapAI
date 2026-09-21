# SnapAI 1.6.49 迭代报告

## 背景

`AutomationRouter.swift` 原本只是自动化 URL 解析和设置页 section 解析的薄包装,但仍通过 symlink 进入 `SnapAILogic`。它本身没有 UI 状态,测试已覆盖 URL 解析和 section fallback,适合单独迁移。

## 本轮完成

- 将 `AutomationRouter` 迁入 `SnapAILogic` 真实源码。
- 删除 app target 中的 `AutomationRouter` 副本。
- `AutomationCommandHandler` 改为直接使用 `AutomationURLCommand.parse` 和 `AutomationSettingsSectionSelection.resolve`,避免将 `AutomationURLCommand` 与 `SettingsSection` 为薄包装公开。
- 下调 `SnapAILogic` symlink 上限并提升真实源码下限。

## 当前边界状态

- `SnapAILogic` 实体 Swift 源码:33 个。
- `SnapAILogic` 剩余 symlink:43 个。
- 自动化薄路由完成;后续可继续评估 `FallbackRunner`, `RequestSession`, `HotKeyUtilities`, `WriteBackCommand` 等候选,其中多数需要 DTO 或 app bridge 才适合删除 app 侧同名源码。
