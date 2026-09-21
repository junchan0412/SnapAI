# SnapAI 1.6.41 迭代报告

## 背景

`RoutingContextCommand.swift` 没有其它 symlink 消费者,但原实现直接接收 `AIRoutingPreference` 和 `ContextProfile`。直接迁移会让命令 factory 的公开 API 暴露 app target 的设置模型类型。

## 本轮完成

- 新增 `RoutingPreferenceCommandInput` 与 `ContextProfileCommandInput`。
- `RoutingContextCommandAction.setRoutingPreference` 改为传递 preference id。
- `AppDelegate+CommandPalette` 负责把轻量 id 映射回 app target 的实际设置类型。
- `RoutingContextCommand.swift` 迁入 `Sources/SnapAILogic`,并从 app target 删除重复源码。
- 下调 `SnapAILogic` symlink 上限并提升真实源码下限。

## 当前边界状态

- `SnapAILogic` 实体 Swift 源码:24 个。
- `SnapAILogic` 剩余 symlink:52 个。
- 命令描述器小簇已完成 6 个文件,后续可继续处理模板、历史导出和历史上下文命令。
