# SnapAI 1.6.31 迭代报告

## 背景

命令面板匹配器是纯字符串逻辑,由 app-only 的命令面板 UI 消费,适合作为独立迁移对象。迁移后搜索排序规则由 `SnapAILogic` 提供,便于测试与后续复用。

## 本轮完成

- 将 `CommandPaletteMatcher.swift` 从 symlink 改为 `Sources/SnapAILogic` 下的真实源码。
- 删除 app target 中对应的重复源码文件。
- 为命令面板 UI 补充 `SnapAILogic` 依赖。
- 将审计修复脚本扩展到 17 个已迁移实体源码。

## 当前边界状态

- `SnapAILogic` 实体 Swift 源码:17 个。
- `SnapAILogic` 剩余 symlink:59 个。
- 下一步继续优先迁移 app-only 消费的纯逻辑模块。
