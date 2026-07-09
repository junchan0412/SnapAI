# SnapAI 1.6.28 迭代报告

## 背景

审计报告指出 `SnapAILogic` target 仍通过大量 symlink 镜像 app 源文件,target 边界脆弱。本轮延续渐进式迁移策略,只处理不会牵连 app target 业务类型的闭合小模块。

## 本轮完成

- 将 `SettingsWindowPinCommand.swift` 从 symlink 改为 `Sources/SnapAILogic` 下的真实源码。
- 删除 app target 中重复的 `SettingsWindowPinCommand.swift`。
- 为 `SettingsView` 和命令面板入口补充 `SnapAILogic` 依赖。
- 将审计修复脚本扩展到 11 个已迁移实体源码。

## 当前边界状态

- `SnapAILogic` 实体 Swift 源码:11 个。
- `SnapAILogic` 剩余 symlink:65 个。
- 下一步继续优先迁移不携带 duplicated app 类型的命令/诊断小模块。
